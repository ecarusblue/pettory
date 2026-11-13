// Shared abuse-protection config for the public Edge Functions.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { MemoryRateLimiter, type RateLimiter } from "../../src/rate_limit.ts";
import { createEndpointPolicy } from "../../src/endpoint_policy.ts";

const LIMIT = 30;
const WINDOW_SECONDS = 60;

const sha256Hex = async (s: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");

/**
 * Global limiter backed by the Postgres RPC `hit_rate_limit` (migration 0003), shared by all isolates.
 * Keys are hashed so raw IPs / push endpoints never reach the table. If the RPC fails we fall back
 * to the per-isolate memory limiter (fail-soft) instead of rejecting every request.
 */
class PgRateLimiter implements RateLimiter {
  private db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  private fallback = new MemoryRateLimiter(LIMIT, WINDOW_SECONDS * 1000);
  async allow(key: string, nowMs: number): Promise<boolean> {
    try {
      const { data, error } = await this.db.rpc("hit_rate_limit", {
        p_key: await sha256Hex(key), p_limit: LIMIT, p_window_seconds: WINDOW_SECONDS,
      });
      if (error) throw error;
      return data === true;
    } catch {
      return this.fallback.allow(key, nowMs);
    }
  }
}

// 30 requests / minute per client IP and per endpoint, global.
export const rateLimiter: RateLimiter = new PgRateLimiter();

// Known push services (src/endpoint_policy.ts). Extra hosts via env, comma separated,
// e.g. EXTRA_PUSH_HOSTS="*.example-push.net".
export const endpointPolicy = createEndpointPolicy(
  undefined,
  (Deno.env.get("EXTRA_PUSH_HOSTS") ?? "").split(",").map((h) => h.trim()).filter(Boolean),
);
