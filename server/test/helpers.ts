import { MemoryStore } from "../src/store.ts";
import { createEndpointPolicy } from "../src/endpoint_policy.ts";
import { FakeSender } from "../src/fake_sender.ts";

export const KST = 540;
export const MIN = 60_000;
export const H = 3_600_000;
/** 2026-11-14 00:00 KST = 2026-11-13T15:00Z */
export const T0 = Date.parse("2026-11-13T15:00:00Z");
export const EP = "https://push.example.test/send/abc123";
export const KEYS = { p256dh: "BPk-p256dh-test-key", auth: "auth-secret-1" };

/** Production allow-list plus the fake host the tests use. */
export const testEndpointPolicy = createEndpointPolicy(undefined, ["push.example.test"]);

export function setup(nowMs = T0) {
  const clock = { t: nowMs };
  return { store: new MemoryStore(), sender: new FakeSender(), clock, now: () => clock.t, endpointPolicy: testEndpointPolicy };
}
export const subBody = (over: object = {}) => ({
  endpoint: EP, keys: KEYS, sleepStart: 22 * 60, sleepEnd: 7 * 60, tzOffsetMinutes: KST, ...over,
});
export const iso = (ms: number) => new Date(ms).toISOString();
