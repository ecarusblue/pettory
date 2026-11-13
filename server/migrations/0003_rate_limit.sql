-- 0003: global fixed-window rate limit shared by all Edge Function isolates.
-- Keys are hashed by the caller (no raw IP / push endpoint is stored). Additive.

create table if not exists public.rate_limit (
  key          text primary key,
  window_start timestamptz not null,
  count        integer     not null
);
alter table public.rate_limit enable row level security;
revoke all on public.rate_limit from anon, authenticated;

-- Atomically counts one hit. Returns true if the request is allowed.
create or replace function public.hit_rate_limit(p_key text, p_limit integer, p_window_seconds integer)
returns boolean
language plpgsql
as $$
declare
  v_count integer;
begin
  insert into public.rate_limit as r (key, window_start, count)
  values (p_key, now(), 1)
  on conflict (key) do update
    set window_start = case when r.window_start <= now() - make_interval(secs => p_window_seconds)
                            then now() else r.window_start end,
        count        = case when r.window_start <= now() - make_interval(secs => p_window_seconds)
                            then 1 else r.count + 1 end
  returning count into v_count;
  return v_count <= p_limit;
end;
$$;
revoke all on function public.hit_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.hit_rate_limit(text, integer, integer) to service_role;

-- Housekeeping: drop windows that expired long ago (call from pg_cron, e.g. hourly).
create or replace function public.purge_rate_limit(p_before timestamptz)
returns integer
language sql
as $$
  with d as (delete from public.rate_limit where window_start < p_before returning 1)
  select count(*)::integer from d;
$$;
revoke all on function public.purge_rate_limit(timestamptz) from public, anon, authenticated;
grant execute on function public.purge_rate_limit(timestamptz) to service_role;
