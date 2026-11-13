// Shared abuse-protection config for the public Edge Functions.
import { MemoryRateLimiter } from "../../src/rate_limit.ts";
import { createEndpointPolicy } from "../../src/endpoint_policy.ts";

// 30 requests / minute per client IP and per endpoint, per function isolate.
// TODO: isolates do not share memory, so this only softens bursts. Back RateLimiter with a
// Postgres counter (RPC) or Redis for a real global limit.
export const rateLimiter = new MemoryRateLimiter(30, 60_000);

// Known push services (src/endpoint_policy.ts). Extra hosts via env, comma separated,
// e.g. EXTRA_PUSH_HOSTS="*.example-push.net".
export const endpointPolicy = createEndpointPolicy(
  undefined,
  (Deno.env.get("EXTRA_PUSH_HOSTS") ?? "").split(",").map((h) => h.trim()).filter(Boolean),
);
