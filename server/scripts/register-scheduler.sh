#!/usr/bin/env bash
# 매분 dispatch 를 호출하는 스케줄러(pg_cron + pg_net)를 연결된 Supabase 프로젝트에 등록한다.
#
#   bash server/scripts/register-scheduler.sh            # 새 DISPATCH_SECRET 을 만들어 함수 시크릿과 Vault 에 함께 저장
#   DISPATCH_SECRET=... bash server/scripts/register-scheduler.sh   # 이미 알고 있는 값을 그대로 사용
#   DRY_RUN=1 bash server/scripts/register-scheduler.sh  # 아무것도 바꾸지 않고 실행할 SQL(비밀값은 가림)만 출력
#
# 비밀값은 화면에 출력하지 않고, 임시 파일(권한 600)은 끝나면 지운다. 저장소에는 아무것도 남기지 않는다.
set -euo pipefail

cd "$(dirname "$0")/../.."   # 저장소 루트 (supabase/ 폴더가 있는 곳)
REF="$(cat supabase/.temp/project-ref)"
[ -n "$REF" ] || { echo "supabase link 가 안 되어 있어요" >&2; exit 1; }

GENERATED=0
if [ -z "${DISPATCH_SECRET:-}" ]; then
  DISPATCH_SECRET="$(openssl rand -hex 32)"
  GENERATED=1
fi
case "$DISPATCH_SECRET" in *[!A-Za-z0-9_-]*) echo "DISPATCH_SECRET 은 영문·숫자·_- 만 쓸 수 있어요" >&2; exit 1 ;; esac

render_sql() {  # $1 = 비밀값(또는 가림 문자열)
  cat <<SQL
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 비밀값은 Vault 에만 두고, cron 작업은 실행 때 읽어 쓴다 (cron.job 에 평문이 남지 않는다).
delete from vault.secrets where name = 'petory_dispatch_secret';
select vault.create_secret('$1', 'petory_dispatch_secret', 'Petory dispatch cron secret');

select cron.unschedule(jobid) from cron.job where jobname in ('petory-dispatch', 'petory-purge-rate-limit');

select cron.schedule('petory-dispatch', '* * * * *', \$job\$
  select net.http_post(
    url := 'https://${REF}.supabase.co/functions/v1/dispatch',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-dispatch-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'petory_dispatch_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
\$job\$);

select cron.schedule('petory-purge-rate-limit', '7 * * * *', \$job\$
  select public.purge_rate_limit(now() - interval '1 hour')
\$job\$);
SQL
}

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "-- 프로젝트: $REF (DRY_RUN: 아무것도 바꾸지 않음, 비밀값은 가림)"
  render_sql '********'
  exit 0
fi

if [ "$GENERATED" = "1" ]; then
  echo "새 DISPATCH_SECRET 을 만들어 Edge Function 시크릿으로 저장합니다…"
  supabase secrets set --remote "DISPATCH_SECRET=$DISPATCH_SECRET" >/dev/null
fi

SQL_FILE="$(mktemp)"; chmod 600 "$SQL_FILE"; trap 'rm -f "$SQL_FILE"' EXIT
render_sql "$DISPATCH_SECRET" > "$SQL_FILE"

echo "pg_cron 작업 2개를 등록합니다 (petory-dispatch 매분, petory-purge-rate-limit 매시)…"
supabase db query --remote -f "$SQL_FILE"
echo "완료. 1~2분 뒤 확인: supabase db query --remote --read-only \"select status, return_message, start_time from cron.job_run_details order by start_time desc limit 3\""
