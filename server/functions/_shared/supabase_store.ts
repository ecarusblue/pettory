// Supabase (PostgREST) implementation of Store. Uses the SERVICE ROLE key; never expose it.
// NOT exercised by the local tests (needs a real Supabase project).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { SubscriptionConflictError, type Store } from "../../src/store.ts";
import type { PushType, ScheduleItem, ScheduledPush, Subscription } from "../../src/types.ts";

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
const subFrom = (r: Row): Subscription => ({
  id: r.id, endpoint: r.endpoint, p256dh: r.p256dh, auth: r.auth,
  sleepStart: r.sleep_start, sleepEnd: r.sleep_end, tzOffsetMinutes: r.tz_offset_minutes,
  sentToday: r.sent_today ?? {}, sentDay: r.sent_day,
});
const pushFrom = (r: Row): ScheduledPush => ({
  id: r.id, subscriptionId: r.subscription_id, type: r.type, fireAt: Date.parse(r.fire_at),
  dedupeKey: r.dedupe_key, sentAt: r.sent_at ? Date.parse(r.sent_at) : null,
});

export function createSupabaseStore(): Store {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const ok = <T>(res: { data: T; error: { message: string; code?: string } | null }): T => {
    // keep the Postgres error code (e.g. 23505) so callers can tell unique violations apart
    if (res.error) throw Object.assign(new Error(res.error.message), { code: (res.error as { code?: string }).code });
    return res.data;
  };
  return {
    async getByEndpoint(endpoint) {
      const d = ok(await db.from("push_subscription").select("*").eq("endpoint", endpoint).maybeSingle());
      return d ? subFrom(d) : null;
    },
    async upsertSubscription(s) {
      // 1) insert if absent (never touches an existing row), 2) compare-and-set update guarded by auth.
      ok(await db.from("push_subscription").upsert({
        endpoint: s.endpoint, p256dh: s.p256dh, auth: s.auth,
        sleep_start: s.sleepStart, sleep_end: s.sleepEnd, tz_offset_minutes: s.tzOffsetMinutes,
      }, { onConflict: "endpoint", ignoreDuplicates: true }));
      const d = ok(await db.from("push_subscription").update({
        p256dh: s.p256dh,
        sleep_start: s.sleepStart, sleep_end: s.sleepEnd, tz_offset_minutes: s.tzOffsetMinutes,
      }).eq("endpoint", s.endpoint).eq("auth", s.auth).select("*").maybeSingle());
      if (!d) throw new SubscriptionConflictError(); // exists with a different auth
      return subFrom(d);
    },
    async updateSettings(id, s) {
      const patch: Row = {};
      if (s.sleepStart !== undefined) patch.sleep_start = s.sleepStart;
      if (s.sleepEnd !== undefined) patch.sleep_end = s.sleepEnd;
      if (s.tzOffsetMinutes !== undefined) patch.tz_offset_minutes = s.tzOffsetMinutes;
      ok(await db.from("push_subscription").update(patch).eq("id", id));
    },
    async deleteSubscription(id) {
      ok(await db.from("push_subscription").delete().eq("id", id)); // cascades to scheduled_push
    },
    async replaceSchedule(subId, items: ScheduleItem[]) {
      const p_items = items.map((i) => ({ type: i.type, fire_at: new Date(i.fireAt).toISOString(), dedupe_key: i.dedupeKey }));
      return ok(await db.rpc("replace_schedule", { p_subscription_id: subId, p_items })) as number;
    },
    async claimDue(nowMs, limit, token, staleClaimMs) {
      const rows = ok(await db.rpc("claim_due_pushes", {
        p_now: new Date(nowMs).toISOString(), p_limit: limit, p_token: token,
        p_stale_before: new Date(nowMs - staleClaimMs).toISOString(),
      })) as Row[];
      if (!rows || rows.length === 0) return [];
      // One subscription object per id (chunked to keep the URL short).
      const ids = [...new Set(rows.map((r) => r.subscription_id as string))];
      const byId = new Map<string, Subscription>();
      for (let i = 0; i < ids.length; i += 100) {
        const subs = ok(await db.from("push_subscription").select("*").in("id", ids.slice(i, i + 100))) as Row[];
        for (const r of subs) byId.set(r.id, subFrom(r));
      }
      return rows
        .filter((r) => byId.has(r.subscription_id))
        .map((r) => ({ push: pushFrom(r), sub: byId.get(r.subscription_id)! }))
        .sort((a, b) => a.push.fireAt - b.push.fireAt || a.push.id - b.push.id);
    },
    async releaseClaim(id, token) {
      ok(await db.from("scheduled_push").update({ claimed_at: null, claim_token: null }).eq("id", id).eq("claim_token", token));
    },
    async reschedule(id, fireAt) {
      ok(await db.from("scheduled_push").update({ fire_at: new Date(fireAt).toISOString(), claimed_at: null, claim_token: null }).eq("id", id));
    },
    async deletePush(id) {
      ok(await db.from("scheduled_push").delete().eq("id", id));
    },
    async markSent(id, nowMs, subId, day, counts: Partial<Record<PushType, number>>, token) {
      // sent_at IS NULL (+ claim token) guard: only the run that owns the claim records the send.
      let q = db.from("scheduled_push")
        .update({ sent_at: new Date(nowMs).toISOString(), claimed_at: null, claim_token: null })
        .eq("id", id).is("sent_at", null);
      if (token) q = q.eq("claim_token", token);
      ok(await q);
      ok(await db.from("push_subscription").update({ sent_day: day, sent_today: counts }).eq("id", subId));
    },
    async purgeSent(nowMs) {
      ok(await db.rpc("purge_sent_pushes", { p_now: new Date(nowMs).toISOString() }));
    },
  };
}
