import test from "node:test";
import assert from "node:assert/strict";
import { runDispatch } from "../src/dispatch.ts";
import { handleSchedule, handleSubscribe } from "../src/handlers.ts";
import { MIN, H, T0, EP, KEYS, iso, setup, subBody } from "./helpers.ts";

// T0 = 00:00 KST. Use no sleep window unless stated, and "noon" = T0 + 12h.
async function withSub(over: object = { sleepStart: null, sleepEnd: null }) {
  const c = setup(T0 + 12 * H);
  await handleSubscribe({ method: "POST", body: subBody(over) }, c);
  const put = (items: unknown[]) =>
    handleSchedule({ method: "PUT", body: { endpoint: EP, auth: KEYS.auth, items } }, c);
  return { ...c, put, sub: [...c.store.subs.values()][0] };
}
const run = (c: { store: any; sender: any; now: () => number }) => runDispatch(c);

test("sends due items only, with fixed template and no name", async () => {
  const c = await withSub();
  await c.put([
    { type: "hunger", fireAt: iso(c.now() - 5 * MIN) },
    { type: "poop", fireAt: iso(c.now() + 30 * MIN) },
  ]);
  const r = await run(c);
  assert.equal(r.sent, 1);
  assert.equal(c.sender.sent.length, 1);
  const p = JSON.parse(c.sender.sent[0].payload);
  assert.deepEqual(Object.keys(p).sort(), ["body", "tag", "title", "type", "v"]);
  assert.equal(p.type, "hunger");
  // later it becomes due
  c.clock.t += 31 * MIN;
  assert.equal((await run(c)).sent, 1);
});

test("re-running dispatch does not double send", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  await run(c);
  await run(c);
  assert.equal(c.sender.sent.length, 1);
});

test("hunger capped at 2/day, poop at 1/day; excess deferred to next local day", async () => {
  const c = await withSub();
  const base = c.now();
  await c.put([
    { type: "hunger", fireAt: iso(base - 30 * MIN) },
    { type: "hunger", fireAt: iso(base - 20 * MIN) },
    { type: "hunger", fireAt: iso(base - 10 * MIN) },
    { type: "poop", fireAt: iso(base - 9 * MIN) },
    { type: "poop", fireAt: iso(base - 8 * MIN) },
  ]);
  const r = await run(c);
  assert.equal(r.sent, 3);
  assert.equal(r.deferredCap, 2);
  const types = c.sender.sent.map((s: any) => JSON.parse(s.payload).type);
  assert.deepEqual(types.sort(), ["hunger", "hunger", "poop"]);
  // deferred ones land at next local midnight (T0 + 24h)
  assert.deepEqual(c.store.unsent(c.sub.id).map((p: any) => p.fireAt), [T0 + 24 * H, T0 + 24 * H]);
  // next day: counter resets, deferred ones go out (1 hunger, 1 poop)
  c.clock.t = T0 + 24 * H + MIN;
  const r2 = await run(c);
  assert.equal(r2.sent, 2);
});

test("day boundary uses the subscriber's local day (KST), not UTC", async () => {
  const c = await withSub();
  // 23:50 KST: send 2 hunger. 00:10 KST (next local day, same UTC day 15:10Z): cap reset.
  c.clock.t = T0 + 23 * H + 50 * MIN;
  await c.put([
    { type: "hunger", fireAt: iso(c.now() - 2 * MIN) },
    { type: "hunger", fireAt: iso(c.now() - MIN) },
  ]);
  assert.equal((await run(c)).sent, 2);
  c.clock.t = T0 + 24 * H + 10 * MIN;
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  assert.equal((await run(c)).sent, 1);
});

test("sick/evolve: once per dedupeKey even if client re-sends the list", async () => {
  const c = await withSub();
  const items = [
    { type: "sick", fireAt: iso(c.now() - MIN), dedupeKey: "sick:7" },
    { type: "evolve", fireAt: iso(c.now() - MIN), dedupeKey: "stage:2" },
  ];
  await c.put(items);
  assert.equal((await run(c)).sent, 2);
  await c.put(items); // idempotent replace after send
  assert.equal(c.store.unsent(c.sub.id).length, 0);
  // same state, different fire_at, same key: still suppressed
  await c.put([{ type: "sick", fireAt: iso(c.now() + 5 * MIN), dedupeKey: "sick:7" }]);
  assert.equal(c.store.unsent(c.sub.id).length, 0);
  // new stage key is allowed
  await c.put([{ type: "evolve", fireAt: iso(c.now() + 5 * MIN), dedupeKey: "stage:3" }]);
  assert.equal(c.store.unsent(c.sub.id).length, 1);
});

test("hunger re-sent with the same fireAt after it was sent is not re-sent", async () => {
  const c = await withSub();
  const it = { type: "hunger", fireAt: iso(c.now() - MIN) };
  await c.put([it]);
  await run(c);
  await c.put([it]);
  await run(c);
  assert.equal(c.sender.sent.length, 1);
});

test("sleep window at dispatch time defers to wake + 30m (midnight-crossing)", async () => {
  // sleep 22:00-07:00; it is 23:00 KST and the setting was changed after scheduling.
  const c = await withSub({ sleepStart: null, sleepEnd: null });
  c.clock.t = T0 + 20 * H;
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  c.clock.t = T0 + 23 * H;
  await c.store.updateSettings(c.sub.id, { sleepStart: 22 * 60, sleepEnd: 7 * 60 });
  c.store.pushes[0].fireAt = c.now() - MIN; // due now
  const r = await run(c);
  assert.equal(r.sent, 0);
  assert.equal(r.deferredSleep, 1);
  assert.equal(c.store.pushes[0].fireAt, T0 + 24 * H + 7.5 * H);
});

test("HTTP 410 and 404 delete the subscription and its schedule; other errors keep it", async () => {
  for (const code of [410, 404]) {
    const c = await withSub();
    await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }, { type: "poop", fireAt: iso(c.now() - MIN) }]);
    c.sender.failWith.set(EP, code);
    const r = await run(c);
    assert.equal(r.subscriptionsDeleted, 1, `code ${code}`);
    assert.equal(c.store.subs.size, 0);
    assert.equal(c.store.pushes.length, 0);
    // client re-registers on next launch
    assert.equal((await handleSubscribe({ method: "POST", body: subBody() }, c)).status, 200);
  }
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - MIN) }]);
  c.sender.failWith.set(EP, 500);
  const r = await run(c);
  assert.equal(r.failedTransient, 1);
  assert.equal(c.store.subs.size, 1);
  assert.equal(c.store.unsent(c.sub.id).length, 1); // retried next minute
  c.sender.failWith.clear();
  assert.equal((await run(c)).sent, 1);
});

test("stale items (> 2h late) are dropped instead of sent", async () => {
  const c = await withSub();
  await c.put([{ type: "hunger", fireAt: iso(c.now() - 3 * H) }]);
  const r = await run(c);
  assert.equal(r.droppedStale, 1);
  assert.equal(c.sender.sent.length, 0);
  assert.equal(c.store.pushes.length, 0);
});
