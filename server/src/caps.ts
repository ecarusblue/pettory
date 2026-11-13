import type { PushType, Subscription } from "./types.ts";
import { localDay } from "./sleep.ts";

/** Per local day. sick/evolve are "once per state/stage", enforced by dedupeKey instead. */
export const DAILY_CAP: Partial<Record<PushType, number>> = { hunger: 2, poop: 1 };

/** Counts valid for `day` (resets when the local day changed). */
export function countsForDay(sub: Subscription, day: number): Partial<Record<PushType, number>> {
  return sub.sentDay === day ? { ...sub.sentToday } : {};
}

export function underCap(sub: Subscription, type: PushType, nowMs: number): boolean {
  const cap = DAILY_CAP[type];
  if (cap === undefined) return true;
  const day = localDay(nowMs, sub.tzOffsetMinutes);
  return (countsForDay(sub, day)[type] ?? 0) < cap;
}
