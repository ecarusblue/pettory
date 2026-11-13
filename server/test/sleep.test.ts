import test from "node:test";
import assert from "node:assert/strict";
import { adjustForSleep } from "../src/sleep.ts";
import { KST, MIN, T0 } from "./helpers.ts";

// KST local 00:00 = T0. Sleep 22:00-07:00 (crosses midnight).
const w = { start: 22 * 60, end: 7 * 60 };
const at = (h: number, m = 0) => T0 + (h * 60 + m) * MIN; // local time on 2026-11-14

test("outside window is unchanged", () => {
  assert.equal(adjustForSleep(at(12), w, KST), at(12));
  assert.equal(adjustForSleep(at(7), w, KST), at(7)); // end is exclusive
  assert.equal(adjustForSleep(at(21, 59), w, KST), at(21, 59));
});
test("after midnight part of a midnight-crossing window -> same day 07:30", () => {
  assert.equal(adjustForSleep(at(2), w, KST), at(7, 30));
  assert.equal(adjustForSleep(at(0), w, KST), at(7, 30));
});
test("evening part of a midnight-crossing window -> next day 07:30", () => {
  assert.equal(adjustForSleep(at(22), w, KST), at(24 + 7, 30));
  assert.equal(adjustForSleep(at(23, 30), w, KST), at(24 + 7, 30));
});
test("non-crossing window (13:00-15:00 nap)", () => {
  const n = { start: 13 * 60, end: 15 * 60 };
  assert.equal(adjustForSleep(at(14), n, KST), at(15, 30));
  assert.equal(adjustForSleep(at(15), n, KST), at(15));
});
test("tz offset is applied: same UTC instant, different offsets", () => {
  // 2026-11-14T01:00Z is 10:00 KST (awake) but 01:00 at UTC+0 (asleep).
  const t = Date.parse("2026-11-14T01:00:00Z");
  assert.equal(adjustForSleep(t, w, KST), t);
  assert.equal(adjustForSleep(t, w, 0), Date.parse("2026-11-14T07:30:00Z"));
  // negative offset: UTC-5, 2026-11-14T03:00Z = 22:00 local previous day -> asleep until next 07:30 local
  assert.equal(adjustForSleep(Date.parse("2026-11-14T03:00:00Z"), w, -300), Date.parse("2026-11-14T12:30:00Z"));
});
test("disabled windows: null or start===end", () => {
  assert.equal(adjustForSleep(at(3), { start: null, end: null }, KST), at(3));
  assert.equal(adjustForSleep(at(3), { start: 60, end: 60 }, KST), at(3));
});
