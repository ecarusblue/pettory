import type { SleepWindow } from "./types.ts";

const MIN = 60_000;
const DAY = 86_400_000;
export const WAKE_DELAY_MIN = 30;

/** Floor-division local day number for an epoch-ms instant. */
export function localDay(epochMs: number, tzOffsetMinutes: number): number {
  return Math.floor((epochMs + tzOffsetMinutes * MIN) / DAY);
}

export function hasWindow(w: SleepWindow): w is { start: number; end: number } {
  return w.start !== null && w.end !== null && w.start !== w.end;
}

export function inSleepWindow(epochMs: number, w: SleepWindow, tz: number): boolean {
  if (!hasWindow(w)) return false;
  const local = epochMs + tz * MIN;
  const m = (local - Math.floor(local / DAY) * DAY) / MIN;
  return w.start < w.end ? m >= w.start && m < w.end : m >= w.start || m < w.end;
}

/**
 * If fireAt falls in the sleep window, return wake time + 30 minutes
 * (the next wake time at or after fireAt); otherwise return fireAt unchanged.
 * Window may cross midnight (start > end). start === end or nulls = no window.
 */
export function adjustForSleep(fireAt: number, w: SleepWindow, tz: number): number {
  if (!inSleepWindow(fireAt, w, tz) || !hasWindow(w)) return fireAt;
  const local = fireAt + tz * MIN;
  const dayStart = Math.floor(local / DAY) * DAY;
  const m = (local - dayStart) / MIN;
  let wakeLocal = dayStart + w.end * MIN;
  if (w.start > w.end && m >= w.start) wakeLocal += DAY; // evening part of a midnight-crossing window
  return wakeLocal - tz * MIN + WAKE_DELAY_MIN * MIN;
}
