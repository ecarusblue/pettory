// QA 추가 테스트: 동시성, 취침 보정 + 상한 연기 조합, tz 음수/경계, 검증 경계.
// [BUG-n] 항목은 qa-report.md 의 버그 재현 테스트이며, 수정 후 skip 을 제거했다.
import test from "node:test";
import assert from "node:assert/strict";
import { runDispatch, DISPATCH_BATCH, MAX_LATENESS_MS } from "../src/dispatch.ts";
import { handleSchedule, handleSubscribe } from "../src/handlers.ts";
import { MemoryStore } from "../src/store.ts";
import { FakeSender } from "../src/fake_sender.ts";
import { adjustForSleep, localDay } from "../src/sleep.ts";
import { MAX_FUTURE_MS, MAX_PAST_MS } from "../src/validate.ts";
import { EP, H, KEYS, MIN, T0, iso, setup, subBody } from "./helpers.ts";


const NO_SLEEP = { sleepStart: null, sleepEnd: null };

async function withSub(over: object = NO_SLEEP, nowMs = T0 + 12 * H, endpoint = EP) {
  const c = setup(nowMs);
  await handleSubscribe({ method: "POST", body: subBody({ ...over, endpoint }) }, c);
  const sub = [...c.store.subs.values()].find((s) => s.endpoint === endpoint)!;
  const put = (items: unknown[], extra: object = {}) =>
    handleSchedule({ method: "PUT", body: { endpoint, auth: KEYS.auth, items, ...extra } }, c);
  return { ...c, put, sub };
}
const run = (c: { store: MemoryStore; sender: FakeSender; now: () => number }) => runDispatch(c);

/** Supabase(PostgREST) 저장소처럼 행마다 구독 객체를 복제해서 돌려주는 저장소. */
class CloningStore extends MemoryStore {
  override async claimDue(nowMs: number, limit: number, token: string, stale: number) {
    const rows = await super.claimDue(nowMs, limit, token, stale);
    return rows.map(({ push, sub }) => ({ push, sub: structuredClone(sub) }));
  }
}

/** SQL 의 unique (subscription_id, type, fire_at) 제약을 흉내 내는 저장소. */
class UniqueStore extends MemoryStore {
  override async reschedule(pushId: number, fireAt: number) {
    const p = this.pushes.find((x) => x.id === pushId)!;
    const clash = this.pushes.some(
      (x) => x.id !== pushId && x.subscriptionId === p.subscriptionId && x.type === p.type && x.fireAt === fireAt,
    );
    if (clash) throw new Error("duplicate key value violates unique constraint");
    p.fireAt = fireAt;
  }
}

// ---------------------------------------------------------------- 동시 디스패치

test("[BUG-8] 동시에 두 번 디스패치해도 같은 알림을 한 번만 보낸다", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  await Promise.all([run(c), run(c)]);
  assert.equal(c.sender.sent.length, 1, `실제 발송 ${c.sender.sent.length}회`);
});

test("순차 디스패치 반복은 중복 발송하지 않는다 (대조군)", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  await run(c);
  await run(c);
  await run(c);
  assert.equal(c.sender.sent.length, 1);
});

test("[BUG-9] 행마다 구독 사본을 주는 저장소(Supabase 방식)에서도 같은 배치의 hunger 상한(2)을 지킨다", async () => {
  const c = setup(T0 + 12 * H);
  const store = new CloningStore();
  const sender = new FakeSender();
  const deps = { store, sender, now: c.now };
  const hd = { store, now: c.now, endpointPolicy: c.endpointPolicy };
  await handleSubscribe({ method: "POST", body: subBody(NO_SLEEP) }, hd);
  await handleSchedule({
    method: "PUT",
    body: { endpoint: EP, auth: KEYS.auth, items: [30, 20, 10].map((m) => ({ type: "hunger", fireAt: iso(c.now() - m * MIN) })) },
  }, hd);
  const r = await runDispatch(deps);
  assert.equal(sender.sent.length, 2, `hunger ${sender.sent.length}건 발송 (상한 2)`);
  assert.equal(r.deferredCap, 1);
});

test("[BUG-10] sick/evolve 는 같은 dedupeKey 가 서로 다른 fireAt 으로 두 건 들어와도 한 번만 발송", async () => {
  const c = await withSub();
  const r = await c.put([
    { type: "sick", fireAt: iso(c.now() - 3 * MIN), dedupeKey: "sick:1" },
    { type: "sick", fireAt: iso(c.now() - 2 * MIN), dedupeKey: "sick:1" },
  ]);
  assert.equal(r.status, 200);
  await run(c);
  assert.equal(c.sender.sent.length, 1, `sick 발송 ${c.sender.sent.length}회`);
});

test("[BUG-11] dispatch 중 저장소 제약 위반 예외가 나도 배치 전체가 중단되지 않는다", async () => {
  const c = setup(T0 + 12 * H);
  const store = new UniqueStore();
  const sender = new FakeSender();
  const deps = { store, sender, now: c.now };
  const hd = { store, now: c.now, endpointPolicy: c.endpointPolicy };
  await handleSubscribe({ method: "POST", body: subBody(NO_SLEEP) }, hd);
  // hunger 4건이 동시에 due: 2건 발송, 2건은 상한으로 같은 자정에 연기 -> unique 충돌
  await handleSchedule({
    method: "PUT",
    body: { endpoint: EP, auth: KEYS.auth, items: [40, 30, 20, 10].map((m) => ({ type: "hunger", fireAt: iso(c.now() - m * MIN) })) },
  }, hd);
  await assert.doesNotReject(() => runDispatch(deps));
});

// ---------------------------------------------------------------- 취침 보정 + 상한 연기 조합

test("취침 22~07 + hunger 3번째가 21:00 KST 에 상한 초과 -> 다음 날 07:30 으로 연기, 다음 날 발송", async () => {
  const c = await withSub({ sleepStart: 22 * 60, sleepEnd: 7 * 60 }, T0 + 21 * H);
  await c.put([20, 10, 5].map((m) => ({ type: "hunger", fireAt: iso(c.now() - m * MIN) })));
  const r = await run(c);
  assert.equal(r.sent, 2);
  assert.equal(r.deferredCap, 1);
  // 다음 로컬 자정(24:00)은 취침 시간대 -> 07:30
  assert.deepEqual(c.store.unsent(c.sub.id).map((p) => p.fireAt), [T0 + 24 * H + 7.5 * H]);
  // 07:29 에는 아직 안 나감, 07:30 에 나감 (카운터는 새 로컬 날짜로 리셋)
  c.clock.t = T0 + 24 * H + 7 * H + 29 * MIN;
  assert.equal((await run(c)).sent, 0);
  c.clock.t = T0 + 24 * H + 7 * H + 30 * MIN;
  assert.equal((await run(c)).sent, 1);
});

test("취침이 자정을 포함하지 않는 설정(01~05)이면 상한 연기는 정확히 다음 로컬 0시", async () => {
  const c = await withSub({ sleepStart: 1 * 60, sleepEnd: 5 * 60 }, T0 + 12 * H);
  await c.put([20, 10, 5].map((m) => ({ type: "hunger", fireAt: iso(c.now() - m * MIN) })));
  await run(c);
  assert.deepEqual(c.store.unsent(c.sub.id).map((p) => p.fireAt), [T0 + 24 * H]);
});

test("poop 상한(1) 초과분이 취침 중 자정에 걸리면 기상+30분, 취침 중 도래한 sick(상한 없음)도 07:30 으로 보류", async () => {
  const c = await withSub({ sleepStart: 22 * 60, sleepEnd: 7 * 60 }, T0 + 20 * H);
  await c.put([
    { type: "poop", fireAt: iso(c.now() - 3 * MIN) },
    { type: "poop", fireAt: iso(c.now() - 2 * MIN) },
  ]);
  const r1 = await run(c);
  assert.equal(r1.sent, 1);
  assert.equal(r1.deferredCap, 1);
  assert.equal(c.store.unsent(c.sub.id)[0].fireAt, T0 + 24 * H + 7.5 * H);
  // 22:30: PUT 시점 보정을 우회해(설정이 나중에 바뀐 상황) 취침 중 due 인 sick 을 직접 심는다
  c.clock.t = T0 + 22 * H + 30 * MIN;
  c.store.pushes.push({ id: 901, subscriptionId: c.sub.id, type: "sick", fireAt: c.now() - MIN, dedupeKey: "sick:1", sentAt: null });
  const r2 = await run(c);
  assert.equal(r2.sent, 0);
  assert.equal(r2.deferredSleep, 1);
  assert.equal(c.store.pushes.find((p) => p.id === 901)!.fireAt, T0 + 24 * H + 7.5 * H);
});

test("취침 보정 후 늦음 판정: 보정된 시각이 기준이라 밤새 보류된 알림이 stale 로 버려지지 않는다", async () => {
  const c = await withSub({ sleepStart: 22 * 60, sleepEnd: 7 * 60 }, T0 + 22 * H + 30 * MIN);
  c.store.pushes.push({ id: 900, subscriptionId: c.sub.id, type: "hunger", fireAt: c.now() - MIN, dedupeKey: null, sentAt: null });
  const r = await run(c);
  assert.equal(r.deferredSleep, 1);
  assert.equal(r.droppedStale, 0);
  c.clock.t = T0 + 24 * H + 7.5 * H + MIN;
  assert.equal((await run(c)).sent, 1);
});

test("stale 경계: 정확히 2시간 늦음은 발송, 1ms 더 늦으면 폐기", async () => {
  const a = await withSub();
  a.store.pushes.push({ id: 1, subscriptionId: a.sub.id, type: "hunger", fireAt: a.now() - MAX_LATENESS_MS, dedupeKey: null, sentAt: null });
  assert.equal((await run(a)).sent, 1);
  const b = await withSub();
  b.store.pushes.push({ id: 1, subscriptionId: b.sub.id, type: "hunger", fireAt: b.now() - MAX_LATENESS_MS - 1, dedupeKey: null, sentAt: null });
  const r = await run(b);
  assert.equal(r.droppedStale, 1);
  assert.equal(r.sent, 0);
});

test("한 번에 500건(DISPATCH_BATCH)까지만 처리하고 나머지는 다음 실행에서 처리", async () => {
  const c = setup(T0 + 12 * H);
  let n = 0;
  for (let s = 0; s < 36; s++) {
    const endpoint = `https://push.example.test/send/bulk-${s}`;
    await handleSubscribe({ method: "POST", body: subBody({ ...NO_SLEEP, endpoint }) }, c);
    const items = Array.from({ length: 16 }, (_, i) => ({ type: "sick", fireAt: iso(c.now() - (i + 1) * MIN), dedupeKey: `sick:${i}` }));
    const r = await handleSchedule({ method: "PUT", body: { endpoint, auth: KEYS.auth, items } }, c);
    assert.equal(r.status, 200);
    n += 16;
  }
  assert.equal(n, 576);
  const r1 = await run(c);
  assert.equal(r1.sent, DISPATCH_BATCH);
  const r2 = await run(c);
  assert.equal(r2.sent, n - DISPATCH_BATCH);
  assert.equal(c.sender.sent.length, n);
});

test("한 구독의 만료(410)가 다른 구독 발송을 막지 않는다", async () => {
  const c = setup(T0 + 12 * H);
  const eps = ["https://push.example.test/send/a", "https://push.example.test/send/b"];
  for (const endpoint of eps) {
    await handleSubscribe({ method: "POST", body: subBody({ ...NO_SLEEP, endpoint }) }, c);
    await handleSchedule({ method: "PUT", body: { endpoint, auth: KEYS.auth, items: [{ type: "poop", fireAt: iso(c.now() - MIN) }] } }, c);
  }
  c.sender.failWith.set(eps[0], 410);
  const r = await run(c);
  assert.equal(r.subscriptionsDeleted, 1);
  assert.equal(r.sent, 1);
  assert.equal(c.sender.sent[0].endpoint, eps[1]);
});

// ---------------------------------------------------------------- tz 음수 / 경계

test("tz 음수(UTC-5): 로컬 날짜 경계(05:00Z)에서 상한이 리셋된다", async () => {
  // 로컬 23:50 = 04:50Z
  const base = Date.parse("2026-11-14T04:50:00Z");
  const c = await withSub({ ...NO_SLEEP, tzOffsetMinutes: -300 }, base);
  await c.put([{ type: "hunger", fireAt: iso(base - 2 * MIN) }, { type: "hunger", fireAt: iso(base - MIN) }]);
  assert.equal((await run(c)).sent, 2);
  c.clock.t = base + 5 * MIN; // 로컬 23:55: 아직 같은 날 -> 3번째는 연기
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  const r = await run(c);
  assert.equal(r.sent, 0);
  assert.equal(r.deferredCap, 1);
  assert.equal(c.store.unsent(c.sub.id)[0].fireAt, Date.parse("2026-11-14T05:00:00Z"));
  c.clock.t = Date.parse("2026-11-14T05:00:00Z");
  assert.equal((await run(c)).sent, 1);
});

test("localDay: 음수 오프셋/경계/에폭 이전 값에서 floor 나눗셈", () => {
  assert.equal(localDay(Date.parse("2026-11-14T04:59:59Z"), -300), localDay(Date.parse("2026-11-14T00:00:00Z"), 0) - 1);
  assert.equal(localDay(Date.parse("2026-11-14T05:00:00Z"), -300), localDay(Date.parse("2026-11-14T00:00:00Z"), 0));
  assert.equal(localDay(Date.parse("2026-11-14T14:59:59Z"), 540), localDay(Date.parse("2026-11-14T00:00:00Z"), 0));
  assert.equal(localDay(Date.parse("2026-11-14T15:00:00Z"), 540), localDay(Date.parse("2026-11-14T00:00:00Z"), 0) + 1);
  assert.equal(localDay(-1, 0), -1); // 1969-12-31
  assert.equal(localDay(0, -1), -1);
});

test("tz 극단값/분 단위 오프셋: -840, 840, 345(+05:45) 허용, 841/-841/5.5 는 400", async () => {
  const c = setup();
  for (const tz of [-840, 840, 345, 0, -30]) {
    const r = await handleSubscribe({ method: "POST", body: subBody({ tzOffsetMinutes: tz, endpoint: `https://push.example.test/tz${tz}` }) }, c);
    assert.equal(r.status, 200, `tz=${tz}`);
  }
  for (const tz of [841, -841, 5.5, "540", null, Number.NaN]) {
    const r = await handleSubscribe({ method: "POST", body: subBody({ tzOffsetMinutes: tz }) }, c);
    assert.equal(r.status, 400, `tz=${String(tz)}`);
  }
});

test("adjustForSleep: 극단 tz(+14:00/-14:00)와 분 단위 경계, 0 시작 창", () => {
  const w = { start: 22 * 60, end: 7 * 60 };
  // UTC+14: 2026-11-14T10:00Z = 로컬 00:00 (취침) -> 로컬 07:30 = 17:30Z
  assert.equal(adjustForSleep(Date.parse("2026-11-14T10:00:00Z"), w, 840), Date.parse("2026-11-14T17:30:00Z"));
  // UTC-14: 2026-11-14T16:00Z = 로컬 02:00 -> 로컬 07:30 = 21:30Z
  assert.equal(adjustForSleep(Date.parse("2026-11-14T16:00:00Z"), w, -840), Date.parse("2026-11-14T21:30:00Z"));
  // 창이 정확히 0분 시작(00:00~07:00)
  const z = { start: 0, end: 7 * 60 };
  assert.equal(adjustForSleep(T0, z, 540), T0 + 7.5 * H);
  assert.equal(adjustForSleep(T0 - MIN, z, 540), T0 - MIN); // 전날 23:59 는 창 밖
  // 보정 결과는 항상 창 밖이고 멱등
  for (let m = 0; m < 1440; m += 7) {
    const t = T0 + m * MIN;
    const once = adjustForSleep(t, w, 540);
    assert.equal(adjustForSleep(once, w, 540), once, `m=${m}`);
    assert.ok(once >= t);
  }
});

test("PUT 의 tzOffsetMinutes/sleep 일부만 보내면 나머지는 기존 값을 쓰고, null 은 취침 해제", async () => {
  const c = await withSub({ sleepStart: 22 * 60, sleepEnd: 7 * 60 }, T0 + 12 * H);
  // tz 만 UTC-5 로 변경: 03:00Z 는 로컬 22:00 -> 취침, 12:30Z 로 이동
  await c.put([{ type: "hunger", fireAt: "2026-11-14T03:00:00Z" }], { tzOffsetMinutes: -300 });
  assert.equal(c.store.unsent(c.sub.id)[0].fireAt, Date.parse("2026-11-14T12:30:00Z"));
  assert.equal(c.sub.sleepStart, 22 * 60);
  // sleepStart null 이면 창 해제
  await c.put([{ type: "hunger", fireAt: "2026-11-14T03:00:00Z" }], { sleepStart: null });
  assert.equal(c.store.unsent(c.sub.id)[0].fireAt, Date.parse("2026-11-14T03:00:00Z"));
});

// ---------------------------------------------------------------- 검증 경계

test("fireAt 허용 범위 경계: -24h 와 +14d 는 허용, 1ms 벗어나면 400", async () => {
  const c = await withSub();
  const ok = async (ms: number) => (await c.put([{ type: "hunger", fireAt: iso(ms) }])).status;
  assert.equal(await ok(c.now() - MAX_PAST_MS), 200);
  assert.equal(await ok(c.now() - MAX_PAST_MS - 1), 400);
  assert.equal(await ok(c.now() + MAX_FUTURE_MS), 200);
  assert.equal(await ok(c.now() + MAX_FUTURE_MS + 1), 400);
});

test("fireAt 형식: 오프셋 포함 문자열은 같은 순간으로 저장, 숫자/오프셋 없음/잘못된 값은 400", async () => {
  const c = await withSub();
  const T = c.now() + 3 * H;
  for (const s of [iso(T), iso(T).replace("Z", "+00:00"), iso(T + 9 * H).replace("Z", "+09:00")]) {
    const r = await c.put([{ type: "poop", fireAt: s }]);
    assert.equal(r.status, 200, s);
  }
  for (const bad of [T, String(T), "2026-11-14T10:00:00", "", null, {}, "9999-99-99T99:99:99Z"]) {
    const r = await c.put([{ type: "poop", fireAt: bad }]);
    assert.equal(r.status, 400, JSON.stringify(bad));
  }
});

test("dedupeKey 검증: 33자/한글/공백/빈 문자열은 400, 32자 허용, hunger 에 붙여도 허용", async () => {
  const c = await withSub();
  const f = iso(c.now() + H);
  const st = async (key: unknown, type = "sick") => (await c.put([{ type, fireAt: f, dedupeKey: key }])).status;
  assert.equal(await st("a".repeat(32)), 200);
  assert.equal(await st("a".repeat(33)), 400);
  assert.equal(await st("몽이"), 400);
  assert.equal(await st("a b"), 400);
  assert.equal(await st(""), 400);
  assert.equal(await st(123), 400);
  assert.equal(await st("stage:2", "evolve"), 200);
  assert.equal(await st("k1", "hunger"), 200);
  assert.equal(await st(null, "sick"), 400); // sick 는 null 불가
});

test("요청 본문에 캐릭터 이름 등 임의 필드가 있어도 저장소 어디에도 남지 않는다", async () => {
  const c = await withSub();
  await handleSubscribe({ method: "POST", body: { ...subBody({ endpoint: EP }), name: "몽이", species: "eggA", stats: { hunger: 1 } } }, c);
  await c.put([{ type: "hunger", fireAt: iso(c.now() + H), name: "몽이", note: "몽이" }], { name: "몽이" });
  const dump = JSON.stringify([...c.store.subs.values(), ...c.store.pushes]);
  assert.ok(!dump.includes("몽이"));
  assert.ok(!dump.includes("species"));
});

// ---------------------------------------------------------------- 소유 증명 / 보안

test("잘못된 auth 의 DELETE 는 200 을 주되 실제로 지우지 않는다", async () => {
  const c = await withSub();
  const r = await handleSubscribe({ method: "DELETE", body: { endpoint: EP, auth: "wrong-auth-key" } }, c);
  assert.equal(r.status, 200);
  assert.equal(c.store.subs.size, 1);
});

test("[BUG-12] endpoint 만 아는 제3자는 /subscribe 로 기존 구독의 키(auth)를 바꿀 수 없다", async () => {
  const c = await withSub();
  const hijack = await handleSubscribe({
    method: "POST",
    body: subBody({ keys: { p256dh: "BAttacker-p256dh-key", auth: "attacker-auth-1" } }),
  }, c);
  assert.notEqual(hijack.status, 200, "기존 구독을 덮어쓰면 소유 증명이 무의미");
  const legit = await handleSchedule({ method: "PUT", body: { endpoint: EP, auth: KEYS.auth, items: [] } }, c);
  assert.equal(legit.status, 200);
});

test("subscribe 입력 검증: 키 형식, 길이, 비 https, 2048자 초과", async () => {
  const c = setup();
  const cases: Array<[string, object]> = [
    ["auth 짧음", subBody({ keys: { p256dh: KEYS.p256dh, auth: "short" } })],
    ["auth 65자", subBody({ keys: { p256dh: KEYS.p256dh, auth: "a".repeat(65) } })],
    ["p256dh 불가 문자", subBody({ keys: { p256dh: "bad key with spaces!", auth: KEYS.auth } })],
    ["endpoint 2049자", subBody({ endpoint: "https://x.test/" + "a".repeat(2040) })],
    ["endpoint javascript:", subBody({ endpoint: "javascript:alert(1)" })],
    ["sleepStart 소수", subBody({ sleepStart: 10.5 })],
    ["sleepEnd 음수", subBody({ sleepEnd: -1 })],
    ["tz 누락", { endpoint: EP, keys: KEYS, sleepStart: 0, sleepEnd: 0 }],
  ];
  for (const [name, body] of cases) {
    assert.equal((await handleSubscribe({ method: "POST", body }, c)).status, 400, name);
  }
  assert.equal(c.store.subs.size, 0);
  assert.equal((await handleSubscribe({ method: "PATCH", body: {} }, c)).status, 405);
  assert.equal((await handleSchedule({ method: "POST", body: {} }, c)).status, 405);
});

test("재구독(만료 후 재등록)은 보낸 횟수 카운터를 유지하고 예약은 없다", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  await run(c);
  assert.equal(c.sub.sentToday.hunger, 1);
  await handleSubscribe({ method: "POST", body: subBody(NO_SLEEP) }, c);
  assert.equal(c.sub.sentToday.hunger, 1);
});

// ---------------------------------------------------------------- 보안 / 가용성

test("[BUG-13] endpoint 는 알려진 푸시 서비스 호스트만 허용 (내부 주소/임의 호스트 거부)", async () => {
  const c = setup();
  for (const endpoint of ["https://169.254.169.254/latest/meta-data", "https://localhost/x", "https://10.0.0.5/push", "https://attacker.example.com/collect"]) {
    const r = await handleSubscribe({ method: "POST", body: subBody({ endpoint }) }, c);
    assert.equal(r.status, 400, endpoint);
  }
  // 실제 푸시 서비스는 허용
  for (const endpoint of ["https://fcm.googleapis.com/fcm/send/abc", "https://updates.push.services.mozilla.com/wpush/v2/abc", "https://web.push.apple.com/abc"]) {
    const r = await handleSubscribe({ method: "POST", body: subBody({ endpoint }) }, c);
    assert.equal(r.status, 200, endpoint);
  }
});

test("[BUG-14] 응답 없는 push endpoint 하나가 디스패치 배치 전체를 멈추지 않는다 (전송 타임아웃)", async () => {
  const c = setup(T0 + 12 * H);
  const hang = "https://push.example.test/send/hang";
  const good = "https://push.example.test/send/good";
  const sent: string[] = [];
  const sender = {
    send: (sub: { endpoint: string }) => (sub.endpoint === hang ? new Promise<void>(() => {}) : (sent.push(sub.endpoint), Promise.resolve())),
  };
  for (const endpoint of [hang, good]) {
    await handleSubscribe({ method: "POST", body: subBody({ ...NO_SLEEP, endpoint }) }, c);
    await handleSchedule({ method: "PUT", body: { endpoint, auth: KEYS.auth, items: [{ type: "poop", fireAt: iso(c.now() - (endpoint === hang ? 2 : 1) * MIN) }] } }, c);
  }
  const done = await Promise.race([
    runDispatch({ store: c.store, sender, now: c.now }, { sendTimeoutMs: 50 }).then(() => true),
    new Promise<boolean>((res) => setTimeout(() => res(false), 300)),
  ]);
  assert.ok(done, "dispatch 가 300ms 안에 끝나야 함");
  assert.deepEqual(sent, [good]);
});
