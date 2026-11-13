// 2차 라운드: 디스패치 선점(claim), 구독 소유권, endpoint 정책, 타임아웃/예산, 남용 완화.
import test from "node:test";
import assert from "node:assert/strict";
import { runDispatch, CLAIM_STALE_MS } from "../src/dispatch.ts";
import { handleSchedule, handleSubscribe } from "../src/handlers.ts";
import { MemoryStore, SubscriptionConflictError } from "../src/store.ts";
import { FakeSender } from "../src/fake_sender.ts";
import { createEndpointPolicy, defaultEndpointPolicy } from "../src/endpoint_policy.ts";
import { MemoryRateLimiter } from "../src/rate_limit.ts";
import { MAX_BODY_BYTES, parseJsonBody } from "../src/body_limit.ts";
import { validateSchedule, validateSubscribe } from "../src/validate.ts";
import type { PushSender } from "../src/types.ts";
import { EP, H, KEYS, MIN, T0, iso, setup, subBody } from "./helpers.ts";

const NO_SLEEP = { sleepStart: null, sleepEnd: null };
const NOON = T0 + 12 * H;

async function withSub(over: object = NO_SLEEP, nowMs = NOON) {
  const c = setup(nowMs);
  await handleSubscribe({ method: "POST", body: subBody(over) }, c);
  const sub = [...c.store.subs.values()][0];
  const put = (items: unknown[], extra: object = {}) =>
    handleSchedule({ method: "PUT", body: { endpoint: EP, auth: KEYS.auth, items, ...extra } }, c);
  return { ...c, put, sub };
}
const delay = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Sender that yields to the event loop, so overlapping runs really interleave. */
class SlowSender extends FakeSender {
  override async send(sub: { endpoint: string }, payload: string) {
    await delay(15);
    return super.send(sub, payload);
  }
}

// ------------------------------------------------------------------ BUG-8 claim

test("동시 3중 디스패치(느린 전송)에서도 행마다 정확히 1회 발송", async () => {
  const c = await withSub();
  const sender = new SlowSender();
  await c.put([
    { type: "hunger", fireAt: iso(NOON - 2 * MIN) },
    { type: "poop", fireAt: iso(NOON - MIN) },
    { type: "sick", fireAt: iso(NOON - MIN), dedupeKey: "sick:1" },
  ]);
  const deps = { store: c.store, sender, now: c.now };
  const rs = await Promise.all([runDispatch(deps), runDispatch(deps), runDispatch(deps)]);
  assert.equal(sender.sent.length, 3);
  assert.equal(rs.reduce((n, r) => n + r.sent, 0), 3);
  assert.equal(c.store.unsent(c.sub.id).length, 0);
});

test("일시 오류면 claim 이 해제되어 다음 실행에서 재시도, 성공하면 1회만", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(NOON - MIN) }]);
  c.sender.failWith.set(EP, 503);
  const r1 = await runDispatch(c);
  assert.equal(r1.failedTransient, 1);
  assert.equal(r1.sent, 0);
  c.sender.failWith.clear();
  const r2 = await runDispatch(c);
  assert.equal(r2.sent, 1);
  assert.equal((await runDispatch(c)).sent, 0);
  assert.equal(c.sender.sent.length, 1);
});

test("claim 은 5분 지나면 회수된다(죽은 디스패처), 그 전에는 다른 실행이 건드리지 않는다", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(NOON - MIN) }]);
  const a = await c.store.claimDue(NOON, 10, "dead-run", CLAIM_STALE_MS);
  assert.equal(a.length, 1);
  assert.equal((await c.store.claimDue(NOON, 10, "other", CLAIM_STALE_MS)).length, 0);
  c.clock.t = NOON + CLAIM_STALE_MS - 1;
  assert.equal((await c.store.claimDue(c.clock.t, 10, "other", CLAIM_STALE_MS)).length, 0);
  c.clock.t = NOON + CLAIM_STALE_MS + 1;
  assert.equal((await runDispatch(c)).sent, 1);
  assert.equal(c.sender.sent.length, 1);
});

test("releaseClaim 은 토큰이 다르면 무시(남의 claim 을 풀지 않음)", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(NOON - MIN) }]);
  const [{ push }] = await c.store.claimDue(NOON, 10, "mine", CLAIM_STALE_MS);
  await c.store.releaseClaim(push.id, "someone-else");
  assert.equal((await c.store.claimDue(NOON, 10, "x", CLAIM_STALE_MS)).length, 0);
  await c.store.releaseClaim(push.id, "mine");
  assert.equal((await c.store.claimDue(NOON, 10, "x", CLAIM_STALE_MS)).length, 1);
});

test("전송 중(claim 된) 행이 있을 때 PUT /schedule 로 같은 항목을 다시 보내도 재발송되지 않는다", async () => {
  const c = await withSub();
  const item = { type: "sick", fireAt: iso(NOON - MIN), dedupeKey: "sick:1" };
  await c.put([item]);
  const [{ push }] = await c.store.claimDue(NOON, 10, "run-A", CLAIM_STALE_MS); // 전송 중
  await c.put([item]); // 클라이언트가 전체 목록 재전송
  await c.store.markSent(push.id, NOON, c.sub.id, 0, {}, "run-A"); // 전송 완료 기록
  assert.equal(c.store.unsent(c.sub.id).length, 0);
  assert.equal((await runDispatch(c)).sent, 0);
});

// ------------------------------------------------------------------ BUG-11/BUG-9

test("한 행의 저장소 오류(markSent 예외)가 같은 배치의 다른 행을 막지 않는다", async () => {
  class FlakyStore extends MemoryStore {
    override async markSent(...a: Parameters<MemoryStore["markSent"]>) {
      if (a[0] === this.pushes[0].id) throw new Error("db down");
      return super.markSent(...a);
    }
  }
  const c = setup(NOON);
  const store = new FlakyStore();
  const hd = { store, now: c.now, endpointPolicy: c.endpointPolicy };
  await handleSubscribe({ method: "POST", body: subBody(NO_SLEEP) }, hd);
  await handleSchedule({ method: "PUT", body: { endpoint: EP, auth: KEYS.auth, items: [
    { type: "hunger", fireAt: iso(NOON - 2 * MIN) }, { type: "poop", fireAt: iso(NOON - MIN) }] } }, hd);
  const r = await runDispatch({ store, sender: c.sender, now: c.now });
  assert.equal(r.errors, 1);
  assert.equal(c.sender.sent.length, 2); // 첫 행은 이미 보냈고 둘째 행도 처리됨
});

test("배치 내 상한: 한 구독의 hunger 5건이 동시에 due -> 2건 발송, 3건 연기", async () => {
  const c = await withSub();
  await c.put([50, 40, 30, 20, 10].map((m) => ({ type: "hunger", fireAt: iso(NOON - m * MIN) })));
  const r = await runDispatch(c);
  assert.equal(r.sent, 2);
  assert.equal(r.deferredCap, 3);
  assert.equal(c.sub.sentToday.hunger, 2);
});

// ------------------------------------------------------------------ BUG-10

test("PUT 검증은 같은 type+dedupeKey 를 가장 이른 시각 1건으로 접는다", () => {
  const f = (m: number) => iso(NOON + m * MIN);
  const r = validateSchedule({ endpoint: EP, auth: KEYS.auth, items: [
    { type: "sick", fireAt: f(30), dedupeKey: "sick:1" },
    { type: "sick", fireAt: f(10), dedupeKey: "sick:1" },
    { type: "sick", fireAt: f(20), dedupeKey: "sick:2" },
    { type: "evolve", fireAt: f(20), dedupeKey: "sick:1" }, // type 이 다르면 별개
  ] }, NOON);
  assert.ok(r.ok);
  if (r.ok) {
    assert.equal(r.value.items.length, 3);
    assert.equal(r.value.items[0].fireAt, NOON + 10 * MIN);
  }
});

test("디스패치 단계에서도 같은 dedupeKey 행이 둘 있으면 한 번만 보낸다(이력 기준)", async () => {
  const c = await withSub();
  for (const [id, m] of [[1, 3], [2, 2]] as const) {
    c.store.pushes.push({ id, subscriptionId: c.sub.id, type: "evolve", fireAt: NOON - m * MIN, dedupeKey: "stage:2", sentAt: null });
  }
  const r = await runDispatch(c);
  assert.equal(r.sent, 1);
  assert.equal(r.droppedDuplicate, 1);
  assert.equal(c.sender.sent.length, 1);
  // 이미 발송된 키는 PUT 으로 다시 와도 저장되지 않는다
  await c.put([{ type: "evolve", fireAt: iso(NOON + H), dedupeKey: "stage:2" }]);
  assert.equal(c.store.unsent(c.sub.id).length, 0);
});

// ------------------------------------------------------------------ BUG-12

test("같은 auth 의 재구독은 설정(취침/tz)과 p256dh 를 갱신하고 카운터를 유지", async () => {
  const c = await withSub();
  const r = await handleSubscribe({ method: "POST", body: subBody({ sleepStart: 23 * 60, tzOffsetMinutes: 0, keys: { p256dh: "BNew-p256dh-key-123", auth: KEYS.auth } }) }, c);
  assert.equal(r.status, 200);
  assert.equal(c.store.subs.size, 1);
  assert.equal(c.sub.sleepStart, 23 * 60);
  assert.equal(c.sub.tzOffsetMinutes, 0);
  assert.equal(c.sub.p256dh, "BNew-p256dh-key-123");
});

test("다른 auth 의 POST 는 409 이고 키/설정이 바뀌지 않는다 (정당 소유자는 계속 동작)", async () => {
  const c = await withSub();
  const r = await handleSubscribe({ method: "POST", body: subBody({ sleepStart: 1, tzOffsetMinutes: 0, keys: { p256dh: "BAttacker-p256dh-key", auth: "attacker-auth-1" } }) }, c);
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: "subscription_conflict" });
  assert.equal(c.sub.auth, KEYS.auth);
  assert.equal(c.sub.p256dh, KEYS.p256dh);
  assert.equal(c.sub.sleepStart, null);
  assert.equal(c.sub.tzOffsetMinutes, 540);
  assert.equal((await c.put([])).status, 200);
});

test("정당한 재구독: 만료 후 새 endpoint 는 새 키로 그대로 등록된다", async () => {
  const c = await withSub();
  const r = await handleSubscribe({ method: "POST", body: subBody({ endpoint: "https://push.example.test/send/new", keys: { p256dh: "BNew-p256dh-key-123", auth: "new-auth-key-1" } }) }, c);
  assert.equal(r.status, 200);
  assert.equal(c.store.subs.size, 2);
});

test("store.upsertSubscription 자체도 다른 auth 를 거부(경쟁 상태 방어)", async () => {
  const c = await withSub();
  await assert.rejects(
    c.store.upsertSubscription({ endpoint: EP, p256dh: "BAttacker-p256dh-key", auth: "attacker-auth-1", ...NO_SLEEP, tzOffsetMinutes: 540 }),
    SubscriptionConflictError,
  );
  assert.equal(c.sub.auth, KEYS.auth);
});

// ------------------------------------------------------------------ BUG-13

test("endpoint 정책: 허용 호스트/차단 호스트 표", () => {
  const ok = [
    "https://fcm.googleapis.com/fcm/send/abc",
    "https://updates.push.services.mozilla.com/wpush/v2/abc",
    "https://web.push.apple.com/abc",
    "https://wns2-par02p.notify.windows.com/w/?token=abc",
    "https://FCM.googleapis.com/x",
  ];
  const bad = [
    "http://fcm.googleapis.com/x", // http
    "https://fcm.googleapis.com:8443/x", // port
    "https://user:pw@fcm.googleapis.com/x", // credentials
    "https://fcm.googleapis.com.evil.com/x", // suffix trick
    "https://evilpush.apple.com.attacker.io/x",
    "https://notpush.apple.com/x", // 서브도메인 아님(*.push.apple.com 은 .push.apple.com 만)
    "https://push.apple.com/x", // 와일드카드는 서브도메인만
    "https://169.254.169.254/latest", "https://127.0.0.1/x", "https://10.0.0.5/x", "https://192.168.0.1/x",
    "https://[::1]/x", "https://[fe80::1]/x", "https://2130706433/x", "https://0x7f000001/x",
    "https://localhost/x", "https://foo.localhost/x", "https://db.internal/x", "https://printer.local/x",
    "https://attacker.example.com/collect",
  ];
  for (const u of ok) assert.equal(defaultEndpointPolicy(new URL(u)), null, u);
  for (const u of bad) assert.notEqual(defaultEndpointPolicy(new URL(u)), null, u);
});

test("endpoint 정책 주입: 추가 호스트(와일드카드)는 허용하지만 사설 IP 는 목록에 있어도 거부", () => {
  const p = createEndpointPolicy(undefined, ["*.corp-push.net", "10.0.0.5"]);
  assert.equal(p(new URL("https://a.corp-push.net/x")), null);
  assert.notEqual(p(new URL("https://corp-push.net/x")), null);
  assert.notEqual(p(new URL("https://10.0.0.5/x")), null);
});

test("validateSubscribe 기본 정책은 엄격(주입 없으면 테스트 호스트도 거부)", () => {
  assert.equal(validateSubscribe(subBody()).ok, false);
  assert.equal(validateSubscribe(subBody({ endpoint: "https://fcm.googleapis.com/fcm/send/abc" })).ok, true);
});

// ------------------------------------------------------------------ BUG-14

test("전송 타임아웃은 일시 오류: claim 해제, 다음 실행에서 재시도", async () => {
  const c = await withSub();
  await c.put([{ type: "poop", fireAt: iso(NOON - MIN) }]);
  let hang = true;
  const sender: PushSender = {
    send: (...a) => (hang ? new Promise<void>(() => {}) : c.sender.send(...a)),
  };
  const r1 = await runDispatch({ store: c.store, sender, now: c.now }, { sendTimeoutMs: 20 });
  assert.equal(r1.failedTransient, 1);
  assert.equal(c.store.unsent(c.sub.id).length, 1);
  hang = false;
  assert.equal((await runDispatch({ store: c.store, sender, now: c.now }, { sendTimeoutMs: 20 })).sent, 1);
});

test("실행 예산 초과 시 남은 행은 발송하지 않고 claim 을 풀어 다음 실행으로", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(NOON - 3 * MIN) }, { type: "poop", fireAt: iso(NOON - 2 * MIN) }, { type: "sick", fireAt: iso(NOON - MIN), dedupeKey: "sick:1" }]);
  let t = 0;
  const clock = () => (t += 30_000); // 호출마다 30초 경과
  const r = await runDispatch(c, { budgetMs: 70_000, clock });
  assert.ok(r.sent >= 1 && r.sent < 3, `sent=${r.sent}`);
  assert.equal(r.releasedBudget, 3 - r.sent);
  assert.equal((await runDispatch(c)).sent, 3 - r.sent);
  assert.equal(c.sender.sent.length, 3);
});

// ------------------------------------------------------------------ 남용 완화

test("MemoryRateLimiter: 창 안에서 limit 초과 거부, 창이 지나면 리셋, 키별 독립", () => {
  const rl = new MemoryRateLimiter(3, 60_000);
  assert.deepEqual([0, 1, 2, 3].map(() => rl.allow("a", 1000)), [true, true, true, false]);
  assert.equal(rl.allow("b", 1000), true);
  assert.equal(rl.allow("a", 1000 + 59_999), false);
  assert.equal(rl.allow("a", 1000 + 60_000), true);
});

test("핸들러: rate limit 초과 시 429 (IP 기준, endpoint 기준)", async () => {
  const c = setup();
  const rateLimiter = new MemoryRateLimiter(2, 60_000);
  const d = { ...c, rateLimiter };
  const post = (ip: string, endpoint = EP) => handleSubscribe({ method: "POST", ip, body: subBody({ endpoint }) }, d);
  assert.equal((await post("1.1.1.1")).status, 200);
  assert.equal((await post("1.1.1.1", "https://push.example.test/send/b")).status, 200);
  const r = await post("1.1.1.1", "https://push.example.test/send/c");
  assert.equal(r.status, 429);
  assert.deepEqual(r.body, { error: "rate_limited" });
  assert.equal((await post("2.2.2.2", "https://push.example.test/send/d")).status, 200); // 다른 IP
  assert.equal((await post("3.3.3.3")).status, 200); // EP 두 번째
  assert.equal((await post("4.4.4.4")).status, 429); // endpoint 기준 초과
  const s = await handleSchedule({ method: "PUT", ip: "9.9.9.9", body: { endpoint: EP, auth: KEYS.auth, items: [] } }, d);
  assert.equal(s.status, 200); // schedule 은 별도 카운터
});

test("본문 크기 제한: 8KB 초과 413, 깨진 JSON 400, 정상 통과", () => {
  assert.equal(parseJsonBody(JSON.stringify(subBody())).ok, true);
  const big = parseJsonBody(JSON.stringify({ x: "a".repeat(MAX_BODY_BYTES) }));
  assert.ok(!big.ok && big.status === 413);
  const multibyte = parseJsonBody(JSON.stringify({ x: "가".repeat(3000) })); // 9000+ bytes
  assert.ok(!multibyte.ok && multibyte.status === 413);
  const bad = parseJsonBody("{nope");
  assert.ok(!bad.ok && bad.status === 400);
});
