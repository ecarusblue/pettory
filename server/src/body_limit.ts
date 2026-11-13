/** Largest accepted request body. A full schedule (16 items) is well under 2 KB. */
export const MAX_BODY_BYTES = 8 * 1024;

export type BodyResult =
  | { ok: true; body: unknown }
  | { ok: false; status: 400 | 413; error: string; details?: string[] };

/** Size-check then JSON-parse a raw body string (UTF-8 byte length). */
export function parseJsonBody(raw: string, maxBytes: number = MAX_BODY_BYTES): BodyResult {
  if (new TextEncoder().encode(raw).length > maxBytes) return { ok: false, status: 413, error: "payload_too_large" };
  try {
    return { ok: true, body: JSON.parse(raw) };
  } catch {
    return { ok: false, status: 400, error: "invalid_request", details: ["body: invalid JSON"] };
  }
}
