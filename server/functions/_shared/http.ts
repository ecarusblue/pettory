// Glue between Deno's Request/Response and the pure handlers in ../../src.
import type { HttpResponse } from "../../src/types.ts";
import { MAX_BODY_BYTES, parseJsonBody } from "../../src/body_limit.ts";

// The PWA origin should replace "*" in production (set ALLOWED_ORIGIN).
const cors = () => ({
  "access-control-allow-origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
  "access-control-allow-headers": "content-type,authorization,apikey",
});

export function toResponse(r: HttpResponse): Response {
  return new Response(JSON.stringify(r.body), {
    status: r.status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...cors() },
  });
}

/** First hop of x-forwarded-for (Supabase's proxy sets it); used only as a rate-limit key. */
const clientIp = (req: Request) =>
  req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? undefined;

export async function serve(
  req: Request,
  fn: (r: { method: string; body?: unknown; headers: Record<string, string | undefined>; ip?: string }) => Promise<HttpResponse>,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors() });
  let body: unknown = undefined;
  if (req.method !== "GET") {
    const declared = Number(req.headers.get("content-length") ?? "0");
    if (declared > MAX_BODY_BYTES) return toResponse({ status: 413, body: { error: "payload_too_large" } });
    const parsed = parseJsonBody(await req.text());
    if (!parsed.ok) {
      return toResponse({ status: parsed.status, body: { error: parsed.error, ...(parsed.details ? { details: parsed.details } : {}) } });
    }
    body = parsed.body;
  }
  return toResponse(await fn({ method: req.method, body, headers: Object.fromEntries(req.headers), ip: clientIp(req) }));
}
