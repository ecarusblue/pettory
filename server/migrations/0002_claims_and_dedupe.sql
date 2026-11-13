-- 0002: dispatch claims (no double send on overlapping runs) + dedupe_key uniqueness.
-- Additive: 0001 is untouched. Re-defines replace_schedule (create or replace).

-- 1) claim columns -----------------------------------------------------------
alter table public.scheduled_push
  add column if not exists claimed_at  timestamptz,
  add column if not exists claim_token uuid;

-- 2) one row per (subscription, type, dedupe_key) -----------------------------
-- Clean up pre-existing duplicates first (keep a sent row if any, else the lowest id).
delete from public.scheduled_push a
 using public.scheduled_push b
 where a.dedupe_key is not null
   and a.subscription_id = b.subscription_id
   and a.type = b.type
   and a.dedupe_key = b.dedupe_key
   and a.id <> b.id
   and ( (b.sent_at is not null and a.sent_at is null)
      or ((b.sent_at is null) = (a.sent_at is null) and b.id < a.id) );

create unique index if not exists scheduled_push_dedupe_uq
  on public.scheduled_push (subscription_id, type, dedupe_key)
  where dedupe_key is not null;

-- 3) claim due rows ------------------------------------------------------------
-- Atomically marks up to p_limit due, unsent rows as claimed and returns them.
-- Rows locked by a concurrent claimer are skipped (FOR UPDATE SKIP LOCKED); rows whose
-- claim is older than p_stale_before (dead dispatcher) are claimable again.
create or replace function public.claim_due_pushes(
  p_now timestamptz, p_limit integer, p_token uuid, p_stale_before timestamptz)
returns setof public.scheduled_push
language sql
as $$
  with picked as materialized (
    select id
      from public.scheduled_push
     where sent_at is null
       and fire_at <= p_now
       and (claimed_at is null or claimed_at < p_stale_before)
     order by fire_at, id
     limit p_limit
     for update skip locked
  )
  update public.scheduled_push s
     set claimed_at = p_now, claim_token = p_token
    from picked
   where s.id = picked.id
  returning s.*;
$$;
revoke all on function public.claim_due_pushes(timestamptz, integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_due_pushes(timestamptz, integer, uuid, timestamptz) to service_role;

-- 4) replace_schedule: do not touch rows a dispatcher is sending right now ---------
-- (otherwise a PUT during a send could delete the row before it is marked sent, and the
-- re-submitted item would be sent again). Claims older than 5 minutes count as dead.
create or replace function public.replace_schedule(p_subscription_id uuid, p_items jsonb)
returns integer
language plpgsql
security invoker
as $$
declare stored integer;
begin
  delete from public.scheduled_push
   where subscription_id = p_subscription_id
     and sent_at is null
     and (claimed_at is null or claimed_at < now() - interval '5 minutes');

  insert into public.scheduled_push (subscription_id, type, fire_at, dedupe_key)
  select p_subscription_id, i.type, i.fire_at, i.dedupe_key
    from jsonb_to_recordset(p_items) as i(type text, fire_at timestamptz, dedupe_key text)
   where not exists (
     select 1 from public.scheduled_push s
      where s.subscription_id = p_subscription_id
        and (s.sent_at is not null or s.claimed_at is not null)
        and s.type = i.type
        and ( (i.dedupe_key is not null and s.dedupe_key = i.dedupe_key)
           or (i.dedupe_key is null and s.fire_at = i.fire_at) ))
   order by i.fire_at
  -- no conflict target: swallows both unique (sub,type,fire_at) and the dedupe_key index
  on conflict do nothing;

  get diagnostics stored = row_count;
  return stored;
end $$;
revoke all on function public.replace_schedule(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.replace_schedule(uuid, jsonb) to service_role;
