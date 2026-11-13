import type { HttpRequest, HttpResponse, PushSender } from "./types.ts";
import { runDispatch, type DispatchOptions } from "./dispatch.ts";
import { SubscriptionConflictError, type Store } from "./store.ts";
import type { EndpointPolicy } from "./endpoint_policy.ts";
import type { RateLimiter } from "./rate_limit.ts";
import { validateSchedule, validateSubscribe, validateUnsubscribe } from "./validate.ts";
import { adjustForSleep } from "./sleep.ts";

export interface Deps {
  store: Store;
  now: () => number;
  /** Endpoint allow-list for /subscribe. Default: known push services only (endpoint_policy.ts). */
  endpointPolicy?: EndpointPolicy;
  /** Optional abuse limiter for /subscribe and /schedule (rate_limit.ts). */
  rateLimiter?: RateLimiter;
}

const bad = (errors: string[]): HttpResponse => ({ status: 400, body: { error: "invalid_request", details: errors } });
const methodNotAllowed = (): HttpResponse => ({ status: 405, body: { error: "method_not_allowed" } });

/** Length-independent-ish comparison of secrets (no early exit on the first differing char). */
function safeEqual(a: string, b: string): boolean {
  let diff = a.length ^ b.length;
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}

/** Unknown endpoint or wrong auth both look like 404. */
async function findOwned(store: Store, endpoint: string, auth: string) {
  const sub = await store.getByEndpoint(endpoint);
  return sub && safeEqual(sub.auth, auth) ? sub : null;
}

const tooMany = (): HttpResponse => ({ status: 429, body: { error: "rate_limited" } });
/** false = over the limit. Keys: per client IP (if known) and per endpoint. */
async function withinLimit(deps: Deps, route: string, ip: string | undefined, endpoint: string): Promise<boolean> {
  const rl = deps.rateLimiter;
  if (!rl) return true;
  const now = deps.now();
  if (ip && !(await rl.allow(`${route}:ip:${ip}`, now))) return false;
  return await rl.allow(`${route}:ep:${endpoint}`, now);
}

export async function handleSubscribe(req: HttpRequest, deps: Deps): Promise<HttpResponse> {
  if (req.method === "DELETE") return handleUnsubscribe(req, deps);
  if (req.method !== "POST") return methodNotAllowed();
  const v = validateSubscribe(req.body, deps.endpointPolicy);
  if (!v.ok) return bad(v.errors);
  if (!(await withinLimit(deps, "subscribe", req.ip, v.value.endpoint))) return tooMany();
  // An existing endpoint is only updated by whoever proves ownership with the same auth secret
  // (settings refresh on every app start). A different auth never overwrites the keys: 409.
  // A legitimately new subscription has a new endpoint; if the old one is dead the push service
  // answers 404/410 and the dispatcher deletes it.
  const conflict: HttpResponse = { status: 409, body: { error: "subscription_conflict" } };
  const ex = await deps.store.getByEndpoint(v.value.endpoint);
  if (ex && !safeEqual(ex.auth, v.value.auth)) return conflict;
  try {
    await deps.store.upsertSubscription(v.value);
  } catch (e) {
    if (e instanceof SubscriptionConflictError) return conflict;
    throw e;
  }
  return { status: 200, body: { ok: true } };
}

export async function handleSchedule(req: HttpRequest, deps: Deps): Promise<HttpResponse> {
  if (req.method !== "PUT") return methodNotAllowed();
  const now = deps.now();
  const v = validateSchedule(req.body, now);
  if (!v.ok) return bad(v.errors);
  if (!(await withinLimit(deps, "schedule", req.ip, v.value.endpoint))) return tooMany();
  const sub = await findOwned(deps.store, v.value.endpoint, v.value.auth);
  if (!sub) return { status: 404, body: { error: "subscription_not_found" } };

  const s = v.value.settings;
  if (Object.keys(s).length) await deps.store.updateSettings(sub.id, s);
  const win = {
    start: s.sleepStart !== undefined ? s.sleepStart : sub.sleepStart,
    end: s.sleepEnd !== undefined ? s.sleepEnd : sub.sleepEnd,
  };
  const tz = s.tzOffsetMinutes ?? sub.tzOffsetMinutes;

  // Server-side sleep correction (client may or may not have applied it; it is idempotent
  // in effect because the corrected time is outside the window).
  const items = v.value.items.map((it) => ({ ...it, fireAt: adjustForSleep(it.fireAt, win, tz) }));
  const stored = await deps.store.replaceSchedule(sub.id, items);
  return { status: 200, body: { ok: true, stored } };
}

async function handleUnsubscribe(req: HttpRequest, deps: Deps): Promise<HttpResponse> {
  const v = validateUnsubscribe(req.body);
  if (!v.ok) return bad(v.errors);
  const sub = await findOwned(deps.store, v.value.endpoint, v.value.auth);
  if (sub) await deps.store.deleteSubscription(sub.id);
  return { status: 200, body: { ok: true } }; // idempotent: same answer if already gone
}

export async function handleTime(req: HttpRequest, deps: Deps): Promise<HttpResponse> {
  if (req.method !== "GET") return methodNotAllowed();
  const now = deps.now();
  return { status: 200, body: { now: new Date(now).toISOString(), epochMs: now } };
}

/** Internal: called by the scheduler every minute. Requires the shared secret. */
export async function handleDispatch(
  req: HttpRequest,
  deps: Deps & { sender: PushSender; secret: string | undefined; dispatchOptions?: DispatchOptions },
): Promise<HttpResponse> {
  if (req.method !== "POST") return methodNotAllowed();
  const given = req.headers?.["x-dispatch-secret"];
  if (!deps.secret || typeof given !== "string" || !safeEqual(given, deps.secret)) return { status: 401, body: { error: "unauthorized" } };
  return { status: 200, body: await runDispatch(deps, deps.dispatchOptions) };
}
