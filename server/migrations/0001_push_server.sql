-- Petory minimal push server schema.
-- PRIVACY: store ONLY subscription info, notification type/time, and sleep window.
-- Never add character name, species, stats, or any user-identifying column
-- (service includes children under 14).

create table public.push_subscription (
  id                 uuid primary key default gen_random_uuid(),
  endpoint           text not null unique check (char_length(endpoint) <= 2048),
  p256dh             text not null,
  auth               text not null,
  -- local minutes since midnight (0..1439); both null or equal = no sleep window
  sleep_start        smallint check (sleep_start between 0 and 1439),
  sleep_end          smallint check (sleep_end between 0 and 1439),
  -- local = UTC + offset (KST = 540)
  tz_offset_minutes  smallint not null default 540 check (tz_offset_minutes between -840 and 840),
  -- per-type send counts for sent_day, e.g. {"hunger":1,"poop":0}.
  -- (jsonb rather than a single int because caps are per notification type)
  sent_today         jsonb not null default '{}'::jsonb,
  -- local calendar day number (floor((epoch_ms + tz offset) / 86400000)) the counts belong to
  sent_day           integer,
  created_at         timestamptz not null default now()
);

create table public.scheduled_push (
  id               bigint generated always as identity primary key,
  subscription_id  uuid not null references public.push_subscription(id) on delete cascade,
  type             text not null check (type in ('hunger','poop','sick','evolve')),
  fire_at          timestamptz not null,
  -- opaque client key for once-per-state/stage types (sick, evolve), e.g. "stage:2". No names.
  dedupe_key       text check (dedupe_key is null or char_length(dedupe_key) <= 32),
  sent_at          timestamptz,
  unique (subscription_id, type, fire_at)
);

create index scheduled_push_due_idx on public.scheduled_push (fire_at) where sent_at is null;
create index scheduled_push_sub_idx on public.scheduled_push (subscription_id);

-- RLS on, and NO policies: anon/authenticated get nothing. Only the service role
-- (Edge Functions) bypasses RLS. Also revoke table privileges explicitly.
alter table public.push_subscription enable row level security;
alter table public.scheduled_push    enable row level security;
revoke all on public.push_subscription from anon, authenticated;
revoke all on public.scheduled_push    from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Atomic, idempotent replacement of one subscription's unsent schedule.
-- p_items: [{"type":"hunger","fire_at":"2026-11-14T01:00:00Z","dedupe_key":null}, ...]
-- Items already sent (same type + dedupe_key, or same type + fire_at when no key) are skipped,
-- so re-sending the same list after a push went out does not cause a re-send.
create or replace function public.replace_schedule(p_subscription_id uuid, p_items jsonb)
returns integer
language plpgsql
security invoker
as $$
declare stored integer;
begin
  delete from public.scheduled_push
   where subscription_id = p_subscription_id and sent_at is null;

  insert into public.scheduled_push (subscription_id, type, fire_at, dedupe_key)
  select distinct on (i.type, i.fire_at) p_subscription_id, i.type, i.fire_at, i.dedupe_key
    from jsonb_to_recordset(p_items) as i(type text, fire_at timestamptz, dedupe_key text)
   where not exists (
     select 1 from public.scheduled_push s
      where s.subscription_id = p_subscription_id
        and s.sent_at is not null
        and s.type = i.type
        and ( (i.dedupe_key is not null and s.dedupe_key = i.dedupe_key)
           or (i.dedupe_key is null and s.fire_at = i.fire_at) ))
  on conflict (subscription_id, type, fire_at) do nothing;

  get diagnostics stored = row_count;
  return stored;
end $$;
revoke all on function public.replace_schedule(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.replace_schedule(uuid, jsonb) to service_role;

-- Housekeeping, called by the dispatcher: drop old sent rows.
create or replace function public.purge_sent_pushes(p_now timestamptz)
returns void language sql as $$
  delete from public.scheduled_push
   where sent_at is not null
     and ((dedupe_key is null and sent_at < p_now - interval '2 days')
       or (dedupe_key is not null and sent_at < p_now - interval '60 days'));
$$;
revoke all on function public.purge_sent_pushes(timestamptz) from public, anon, authenticated;
grant execute on function public.purge_sent_pushes(timestamptz) to service_role;
