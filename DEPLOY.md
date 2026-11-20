# 펫토리 스테이징 배포 체크리스트

구성: Flutter 웹(PWA) → **Firebase Hosting**, 푸시 서버 → **Supabase**(Postgres + Edge Functions + pg_cron). FCM은 쓰지 않고 VAPID Web Push를 직접 사용합니다. 스테이징과 운영은 프로젝트를 분리하세요.

## 0. 준비
```bash
npm i -g firebase-tools supabase   # 또는 brew
firebase login && supabase login
cp .firebaserc.example .firebaserc # <STAGING_PROJECT_ID> 채우기
```

## 1. Supabase (스테이징 프로젝트)
CLI는 `supabase/` 폴더 구조를 요구하므로 저장소 루트의 `supabase/`는 `server/`로 향하는 심볼릭 링크입니다
(`supabase/migrations/<타임스탬프>_*.sql` → `server/migrations/000N_*.sql`, `supabase/functions` → `server/functions`,
`supabase/src` → `server/src`; 함수의 `../../src` import가 링크 경로 기준으로 해석되므로 `src` 링크도 필요). 원본은 항상 `server/`.
```bash
supabase link --project-ref <STAGING_REF>   # 저장소 루트에서
supabase db push --remote           # 로컬 스택이 아니라 원격에 적용하려면 --remote 필수
# 이미 SQL을 수동 적용했다면: supabase migration repair --status applied <버전...> --remote
npx web-push generate-vapid-keys    # 결과는 저장소에 커밋하지 말 것
supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... \
  VAPID_SUBJECT=mailto:<연락처> DISPATCH_SECRET=$(openssl rand -hex 32) \
  ALLOWED_ORIGIN=https://<STAGING_PROJECT_ID>.web.app
supabase functions deploy subscribe schedule time dispatch --no-verify-jwt --use-api   # Docker 불필요
```
- 스케줄러(pg_cron + pg_net, 매분 `dispatch` 호출)와 rate limit 정리 작업은 `bash server/scripts/register-scheduler.sh` 한 번으로 등록합니다. 새 `DISPATCH_SECRET`을 만들어 함수 시크릿과 Vault에 함께 저장하며 화면에 출력하지 않습니다. 먼저 `DRY_RUN=1 bash server/scripts/register-scheduler.sh`로 실행할 SQL을 볼 수 있습니다.
- 추가로 rate limit 정리용: `select cron.schedule('petory-purge-rl','0 * * * *',$$select public.purge_rate_limit(now() - interval '1 hour')$$);`

## 2. 앱 빌드 + Firebase Hosting
```bash
cd app
flutter build web --release --no-web-resources-cdn --web-content-hash \
  --dart-define=PETORY_PUSH_BASE_URL=https://<STAGING_REF>.supabase.co/functions/v1 \
  --dart-define=PETORY_VAPID_PUBLIC_KEY=<VAPID_PUBLIC_KEY>
cd .. && firebase deploy --only hosting
```
(`--web-content-hash`가 없으면 `precache_manifest.json`이 만들어지지 않아 오프라인 캐시(`app_sw.js`)가 설치되지 않습니다. `firebase.json`은 index·서비스 워커·매니페스트를 no-cache로 서빙합니다.)

설치 안내 페이지: `https://<STAGING_PROJECT_ID>.web.app/install.html` (`app/web/install.html`, 아이폰·안드로이드 설치 방법 한 페이지).

## 3. 스테이징 검증 (실제 기기, HTTPS)
- [ ] 마이그레이션 3개가 오류 없이 적용됨
- [ ] 알림 허용 → `/subscribe` 200, DB에 구독 행 생성
- [ ] 케어 후 `/schedule` → `scheduled_push` 행 생성, 취침 시간 보정 확인
- [ ] 1분 내 `dispatch` 실행 → 실제 푸시 도착 (앱을 닫은 상태)
- [ ] `dispatch`를 동시에 2번 호출해도 중복 발송 없음
- [ ] 비밀값 없이 `dispatch` 호출 시 거부됨 / 분당 31번째 요청이 429
- [ ] 함수 로그에 endpoint가 남지 않음
- [ ] iOS Safari는 홈 화면 추가 후에만 푸시 가능 — 동작 확인

## 4. 공개 전 남은 결정 (코드로 해결 불가)
- 만 14세 미만 법정대리인 동의 절차와 개인정보 처리방침(PRD 7장)
- `qa-report.md`를 현재 상태로 갱신
