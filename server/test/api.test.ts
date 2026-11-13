import test from "node:test";
import assert from "node:assert/strict";
import { handleSchedule, handleSubscribe, handleTime, handleDispatch } from "../src/handlers.ts";
import { EP, KEYS, T0, H, iso, setup, subBody } from "./helpers.ts";

const sched = (items: unknown[], extra: object = {}) => ({ endpoint: EP, auth: KEYS.auth, items, ...extra });

async function subscribed() {
  const c = setup();
  const r = await handleSubscribe({ method: "POST", body: subBody() }, c);
  assert.equal(r.status, 200);
  return c;
}

test("subscribe is idempotent (one row)", async () => {
  const c = await subscribed();
  await handleSubscribe({ method: "POST", body: subBody({ sleepStart: 23 * 60 }) }, c);
  assert.equal(c.store.subs.size, 1);
  assert.equal([...c.store.subs.values()][0].sleepStart, 23 * 60);
});

test("PUT /schedule replaces the whole list, and repeating it gives the same result", async () => {
  const c = await subscribed();
  const items = [
    { type: "hunger", fireAt: iso(T0 + 10 * H) },
    { type: "poop", fireAt: iso(T0 + 11 * H) },
  ];
  const sub = [...c.store.subs.values()][0];
  const snap = () => JSON.stringify(c.store.unsent(sub.id).map(({ id: _i, ...r }) => r).sort((a, b) => a.fireAt - b.fireAt));
  const r1 = await handleSchedule({ method: "PUT", body: sched(items) }, c);
  const a = snap();
  const r2 = await handleSchedule({ method: "PUT", body: sched(items) }, c);
  assert.deepEqual([r1.status, r2.status], [200, 200]);
  assert.equal(snap(), a);
  assert.equal(c.store.unsent(sub.id).length, 2);
  // a different list replaces, not appends
  await handleSchedule({ method: "PUT", body: sched([{ type: "hunger", fireAt: iso(T0 + 12 * H) }]) }, c);
  assert.equal(c.store.unsent(sub.id).length, 1);
  // empty list clears
  await handleSchedule({ method: "PUT", body: sched([]) }, c);
  assert.equal(c.store.unsent(sub.id).length, 0);
});

test("duplicate entries inside one request collapse", async () => {
  const c = await subscribed();
  const it = { type: "hunger", fireAt: iso(T0 + 10 * H) };
  await handleSchedule({ method: "PUT", body: sched([it, it]) }, c);
  assert.equal(c.store.pushes.length, 1);
});

test("sleep correction is applied on store (03:00 KST -> 07:30 KST)", async () => {
  const c = await subscribed();
  await handleSchedule({ method: "PUT", body: sched([{ type: "hunger", fireAt: iso(T0 + 3 * H) }]) }, c);
  assert.equal(c.store.pushes[0].fireAt, T0 + 7.5 * H);
});

test("PUT with wrong auth or unknown endpoint -> 404; delete is idempotent", async () => {
  const c = await subscribed();
  const bad = await handleSchedule({ method: "PUT", body: sched([], { auth: "wrong-auth-key" }) }, c);
  assert.equal(bad.status, 404);
  const del = () => handleSubscribe({ method: "DELETE", body: { endpoint: EP, auth: KEYS.auth } }, c);
  assert.equal((await del()).status, 200);
  assert.equal(c.store.subs.size, 0);
  assert.equal((await del()).status, 200);
  assert.equal((await handleSchedule({ method: "PUT", body: sched([]) }, c)).status, 404);
});

test("input validation failures -> 400", async () => {
  const c = await subscribed();
  const cases: Array<[string, () => Promise<{ status: number }>]> = [
    ["http endpoint", () => handleSubscribe({ method: "POST", body: subBody({ endpoint: "http://x.test/a" }) }, c)],
    ["missing keys", () => handleSubscribe({ method: "POST", body: subBody({ keys: undefined }) }, c)],
    ["sleep out of range", () => handleSubscribe({ method: "POST", body: subBody({ sleepStart: 1440 }) }, c)],
    ["tz out of range", () => handleSubscribe({ method: "POST", body: subBody({ tzOffsetMinutes: 5000 }) }, c)],
    ["non-object body", () => handleSubscribe({ method: "POST", body: "x" }, c)],
    ["unknown type", () => handleSchedule({ method: "PUT", body: sched([{ type: "happy", fireAt: iso(T0 + H) }]) }, c)],
    ["bad date", () => handleSchedule({ method: "PUT", body: sched([{ type: "hunger", fireAt: "tomorrow" }]) }, c)],
    ["date without tz", () => handleSchedule({ method: "PUT", body: sched([{ type: "hunger", fireAt: "2026-11-14T10:00:00" }]) }, c)],
    ["too far future", () => handleSchedule({ method: "PUT", body: sched([{ type: "hunger", fireAt: iso(T0 + 30 * 24 * H) }]) }, c)],
    ["evolve without dedupeKey", () => handleSchedule({ method: "PUT", body: sched([{ type: "evolve", fireAt: iso(T0 + H) }]) }, c)],
    ["too many items", () => handleSchedule({ method: "PUT", body: sched(Array.from({ length: 17 }, (_, i) => ({ type: "hunger", fireAt: iso(T0 + (i + 1) * H) }))) }, c)],
    ["items not array", () => handleSchedule({ method: "PUT", body: sched("x" as unknown as unknown[]) }, c)],
    ["extra character name is not accepted into storage", async () => {
      // unknown fields are ignored, never persisted
      const r = await handleSubscribe({ method: "POST", body: subBody({ name: "몽이" }) }, c);
      assert.ok(!JSON.stringify([...c.store.subs.values()]).includes("몽이"));
      return { status: 400 };
    }],
  ];
  for (const [name, fn] of cases) assert.equal((await fn()).status, 400, name);
});

test("GET /time returns server time; other methods 405", async () => {
  const c = setup(Date.parse("2026-11-13T12:34:56.789Z"));
  const r = await handleTime({ method: "GET" }, c);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { now: "2026-11-13T12:34:56.789Z", epochMs: Date.parse("2026-11-13T12:34:56.789Z") });
  assert.equal((await handleTime({ method: "POST" }, c)).status, 405);
});

test("dispatch endpoint requires the secret", async () => {
  const c = setup();
  const d = { ...c, secret: "s3cret" };
  assert.equal((await handleDispatch({ method: "POST" }, d)).status, 401);
  assert.equal((await handleDispatch({ method: "POST", headers: { "x-dispatch-secret": "nope" } }, d)).status, 401);
  assert.equal((await handleDispatch({ method: "POST", headers: { "x-dispatch-secret": "s3cret" } }, d)).status, 200);
  assert.equal((await handleDispatch({ method: "POST", headers: { "x-dispatch-secret": "x" } }, { ...c, secret: undefined })).status, 401);
});
