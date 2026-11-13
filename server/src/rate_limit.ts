/**
 * Abuse mitigation for the public endpoints (/subscribe, /schedule).
 * Handlers only see this interface. Keys are opaque strings such as "subscribe:ip:1.2.3.4"
 * or "schedule:ep:<endpoint>".
 *
 * TODO(supabase): MemoryRateLimiter is per Edge Function isolate, so it only softens bursts.
 * For a real limit back it with a table/RPC (e.g. `hit_rate_limit(key, window)` upserting a
 * counter row) or Upstash/Redis, behind this same interface.
 */
export interface RateLimiter {
  /** true = request allowed (and counted), false = over the limit. */
  allow(key: string, nowMs: number): Promise<boolean> | boolean;
}

/** Fixed-window counter in memory. */
export class MemoryRateLimiter implements RateLimiter {
  private hits = new Map<string, { windowStart: number; count: number }>();
  private limit: number;
  private windowMs: number;
  constructor(limit: number, windowMs: number) {
    this.limit = limit;
    this.windowMs = windowMs;
  }
  allow(key: string, nowMs: number): boolean {
    if (this.hits.size > 10_000) {
      for (const [k, v] of this.hits) if (nowMs - v.windowStart >= this.windowMs) this.hits.delete(k);
    }
    const h = this.hits.get(key);
    if (!h || nowMs - h.windowStart >= this.windowMs) {
      this.hits.set(key, { windowStart: nowMs, count: 1 });
      return true;
    }
    if (h.count >= this.limit) return false;
    h.count++;
    return true;
  }
}
