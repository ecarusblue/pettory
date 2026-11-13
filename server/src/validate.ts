import { defaultEndpointPolicy, type EndpointPolicy } from "./endpoint_policy.ts";
import { PUSH_TYPES, type PushType, type ScheduleItem } from "./types.ts";

export type Result<T> = { ok: true; value: T } | { ok: false; errors: string[] };

export const MAX_ITEMS = 16;
export const MAX_FUTURE_MS = 14 * 86_400_000;
export const MAX_PAST_MS = 86_400_000;

const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown, lo: number, hi: number): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
const b64url = /^[A-Za-z0-9_\-+/=]+$/;

/** policy: extra host rules (subscribe only). Without it just "valid https URL" (lookups by string need no more). */
function checkEndpoint(v: unknown, errors: string[], policy?: EndpointPolicy): string {
  if (typeof v !== "string" || v.length === 0 || v.length > 2048) {
    errors.push("endpoint: required string up to 2048 chars");
    return "";
  }
  try {
    const url = new URL(v);
    if (url.protocol !== "https:") errors.push("endpoint: must be https URL");
    else if (policy) {
      const why = policy(url);
      if (why) errors.push(`endpoint: ${why}`);
    }
  } catch {
    errors.push("endpoint: must be a valid URL");
  }
  return v;
}
function checkKey(v: unknown, name: string, errors: string[], max: number): string {
  if (typeof v !== "string" || v.length < 8 || v.length > max || !b64url.test(v)) {
    errors.push(`${name}: required base64url string`);
    return "";
  }
  return v;
}

export interface SettingsInput {
  sleepStart: number | null;
  sleepEnd: number | null;
  tzOffsetMinutes: number;
}
function checkSettings(o: Record<string, unknown>, errors: string[], required: boolean) {
  const out: Partial<SettingsInput> = {};
  for (const k of ["sleepStart", "sleepEnd"] as const) {
    if (o[k] === undefined) {
      if (required) errors.push(`${k}: required (0..1439 or null)`);
      continue;
    }
    if (o[k] === null) out[k] = null;
    else if (isInt(o[k], 0, 1439)) out[k] = o[k] as number;
    else errors.push(`${k}: integer 0..1439 (local minutes since midnight) or null`);
  }
  if (o.tzOffsetMinutes === undefined) {
    if (required) errors.push("tzOffsetMinutes: required");
  } else if (isInt(o.tzOffsetMinutes, -840, 840)) out.tzOffsetMinutes = o.tzOffsetMinutes;
  else errors.push("tzOffsetMinutes: integer -840..840");
  return out;
}

export interface SubscribeInput extends SettingsInput {
  endpoint: string;
  p256dh: string;
  auth: string;
}
export function validateSubscribe(body: unknown, policy: EndpointPolicy = defaultEndpointPolicy): Result<SubscribeInput> {
  const errors: string[] = [];
  if (!isObj(body)) return { ok: false, errors: ["body: JSON object required"] };
  const endpoint = checkEndpoint(body.endpoint, errors, policy);
  const keys = isObj(body.keys) ? body.keys : (errors.push("keys: object {p256dh, auth} required"), {});
  const p256dh = checkKey(keys.p256dh, "keys.p256dh", errors, 256);
  const auth = checkKey(keys.auth, "keys.auth", errors, 64);
  const s = checkSettings(body, errors, true);
  if (errors.length) return { ok: false, errors };
  return { ok: true, value: { endpoint, p256dh, auth, ...(s as SettingsInput) } };
}

export interface ScheduleInput {
  endpoint: string;
  auth: string;
  settings: Partial<SettingsInput>;
  items: ScheduleItem[];
}
export function validateSchedule(body: unknown, nowMs: number): Result<ScheduleInput> {
  const errors: string[] = [];
  if (!isObj(body)) return { ok: false, errors: ["body: JSON object required"] };
  const endpoint = checkEndpoint(body.endpoint, errors);
  const auth = checkKey(body.auth, "auth", errors, 64);
  const settings = checkSettings(body, errors, false);
  const items: ScheduleItem[] = [];
  if (!Array.isArray(body.items)) errors.push("items: array required (may be empty)");
  else if (body.items.length > MAX_ITEMS) errors.push(`items: at most ${MAX_ITEMS}`);
  else {
    const seen = new Set<string>();
    const byKey = new Map<string, number>(); // type|dedupeKey -> index in items
    body.items.forEach((it, i) => {
      if (!isObj(it)) return void errors.push(`items[${i}]: object required`);
      const type = it.type;
      if (typeof type !== "string" || !(PUSH_TYPES as readonly string[]).includes(type)) {
        return void errors.push(`items[${i}].type: one of ${PUSH_TYPES.join("|")}`);
      }
      const t = typeof it.fireAt === "string" ? Date.parse(it.fireAt) : NaN;
      if (!Number.isFinite(t) || !/[zZ]|[+-]\d\d:?\d\d$/.test(it.fireAt as string)) {
        return void errors.push(`items[${i}].fireAt: ISO-8601 timestamp with timezone`);
      }
      if (t < nowMs - MAX_PAST_MS || t > nowMs + MAX_FUTURE_MS) {
        return void errors.push(`items[${i}].fireAt: must be within -24h..+14d of server time`);
      }
      let dedupeKey: string | null = null;
      if (it.dedupeKey !== undefined && it.dedupeKey !== null) {
        if (typeof it.dedupeKey !== "string" || !/^[A-Za-z0-9:_-]{1,32}$/.test(it.dedupeKey)) {
          return void errors.push(`items[${i}].dedupeKey: /^[A-Za-z0-9:_-]{1,32}$/`);
        }
        dedupeKey = it.dedupeKey;
      }
      if ((type === "sick" || type === "evolve") && dedupeKey === null) {
        return void errors.push(`items[${i}].dedupeKey: required for sick/evolve (e.g. "stage:2")`);
      }
      // Same key = same state/stage: keep one entry, the earliest time (API: "same key is sent once").
      const kk = dedupeKey !== null ? `${type}|${dedupeKey}` : null;
      const at = kk !== null ? byKey.get(kk) : undefined;
      if (at !== undefined) {
        if (t < items[at].fireAt) items[at] = { ...items[at], fireAt: t };
        return;
      }
      const k = `${type}|${t}`;
      if (seen.has(k)) return; // duplicate entries collapse (idempotent)
      seen.add(k);
      if (kk !== null) byKey.set(kk, items.length);
      items.push({ type: type as PushType, fireAt: t, dedupeKey });
    });
  }
  if (errors.length) return { ok: false, errors };
  return { ok: true, value: { endpoint, auth, settings, items } };
}

export function validateUnsubscribe(body: unknown): Result<{ endpoint: string; auth: string }> {
  const errors: string[] = [];
  if (!isObj(body)) return { ok: false, errors: ["body: JSON object required"] };
  const endpoint = checkEndpoint(body.endpoint, errors);
  const auth = checkKey(body.auth, "auth", errors, 64);
  if (errors.length) return { ok: false, errors };
  return { ok: true, value: { endpoint, auth } };
}
