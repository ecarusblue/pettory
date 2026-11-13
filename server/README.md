# 펫토리 푸시 서버 (MVP)

Supabase(Postgres + Edge Functions + pg_cron) 기준의 최소 Web Push 서버. 클라이언트 계약은 [API.md](API.md).

## 구조
- `migrations/0001_push_server.sql`: 테이블, RLS(정책 없음 = anon 접근 불가), 원자적 교체 함수
- `migrations/0003_rate_limit.sql`: 전역 rate limit 테이블/RPC
- `migrations/0002_claims_and_dedupe.sql`: 디스패치 선점(`claimed_at`/`claim_token`, `claim_due_pushes()` = `FOR UPDATE SKIP LOCKED`), `dedupe_key` 부분 unique 인덱스, `replace_schedule` 재정의(전송 중 행 보존). 0001 다음에 `supabase db push`로 순서대로 적용
- `src/`: 런타임 비종속 순수 TypeScript (검증, 취침 보정, 상한, 디스패치, 핸들러, MemoryStore, FakeSender, `endpoint_policy.ts` 푸시 호스트 허용 목록, `rate_limit.ts` RateLimiter 인터페이스+메모리 구현, `body_limit.ts` 본문 8KB 제한)
- `functions/`: Edge Function 얇은 엔트리(subscribe, schedule, time, dispatch)와 `_shared/`(Supabase 저장소, web-push 전송, HTTP 글루)
- `test/`: node:test 단위 테스트

## 로컬 테스트
Node 22.18+ (이 Mac은 v26)는 `.ts`를 그대로 실행합니다(타입 제거 방식, `enum` 등 비-erasable 문법 금지).
```
cd server
npm install        # devDependencies(typescript, @types/node)만, 타입체크용. 테스트 실행 자체에는 불필요
npm test           # node --test test/
npm run typecheck  # tsc --noEmit
```
Supabase/Deno 없이 실행됩니다. `functions/`는 Deno 전용 import(`npm:`)를 쓰므로 로컬 테스트·타입체크 대상이 아닙니다.

## 배포 시 필요한 것 (아직 배포하지 않음)
환경변수/시크릿 (`supabase secrets set ...`; 파일·저장소에 커밋 금지):

| 이름 | 용도 |
| --- | --- |
| `VAPID_PUBLIC_KEY` | 공개키. 클라이언트의 `pushManager.subscribe({applicationServerKey})`에도 동일 값 사용 |
| `VAPID_PRIVATE_KEY` | 비공개키. 서버 전용 |
| `VAPID_SUBJECT` | `mailto:` 또는 https URL(운영 연락처) |
| `SUPABASE_SERVICE_ROLE_KEY` | DB 접근(Edge Function 런타임에 자동 주입됨). 클라이언트/앱에 절대 넣지 말 것 |
| `SUPABASE_URL` | 자동 주입 |
| `DISPATCH_SECRET` | 긴 랜덤 문자열. 스케줄러만 알고 있는 디스패처 호출 비밀값 |
| `ALLOWED_ORIGIN` | (권장) PWA 도메인으로 CORS 제한 |
| `EXTRA_PUSH_HOSTS` | (선택) 허용 푸시 호스트 추가, 쉼표 구분(`*.example.net` 가능). 기본 목록은 `src/endpoint_policy.ts` |

VAPID 키 생성: `npx web-push generate-vapid-keys` (한 번만, 결과를 시크릿으로만 저장).

절차 개요: `supabase db push`(마이그레이션) → `supabase functions deploy subscribe schedule time dispatch --no-verify-jwt` → 시크릿 설정 → 스케줄러 등록.
`--no-verify-jwt`는 익명 PWA가 호출하기 위함이며, `dispatch`는 `x-dispatch-secret`으로 보호됩니다.

## 스케줄러 (pg_cron + pg_net)
Supabase 대시보드에서 `pg_cron`, `pg_net` 확장을 켠 뒤 (비밀값은 Vault 등에 두고 SQL에 직접 쓰지 않는 것을 권장):
```sql
select cron.schedule('petory-dispatch', '* * * * *', $$
  select net.http_post(
    url     := 'https://<project>.supabase.co/functions/v1/dispatch',
    headers := jsonb_build_object('content-type','application/json',
                                  'x-dispatch-secret', '<DISPATCH_SECRET>'),
    body    := '{}'::jsonb);
$$);
```
다른 스케줄러(GitHub Actions cron은 최소 5분 간격이라 부적합, 외부 cron 서비스 등)를 써도 동일하게 매분 POST하면 됩니다.

## 동시 실행·남용 방어 요약
- 디스패치: 행을 먼저 claim → 전송 → `sent_at` 기록. 일시 오류/타임아웃은 claim 해제 후 재시도, 5분 넘은 claim은 회수. pg_cron이 겹쳐 호출돼도 중복 발송하지 않습니다(한계: 아래 "알려진 한계").
- 테스트에서 엔드포인트 정책은 `Deps.endpointPolicy`로 주입(`test/helpers.ts`의 `testEndpointPolicy`). 전송 타임아웃/예산은 `runDispatch(deps, { sendTimeoutMs, budgetMs, clock })`.
- rate limit: `RateLimiter` 인터페이스(`allow(key, now)`). Edge Function은 isolate별 메모리 구현(30회/분, IP·endpoint 키)이라 폭주를 누그러뜨리는 정도이며, 운영에서는 `functions/_shared/limits.ts`의 Postgres 카운터(`migrations/0003_rate_limit.sql`의 `hit_rate_limit`, 키는 SHA-256 해시)가 전역으로 제한하고, RPC 실패 시 메모리 구현으로 폴백합니다. 만료 행은 `purge_rate_limit`로 주기 삭제(pg_cron 권장).
- 본문은 8KB 초과 시 413.

### 알려진 한계
- 겹친 두 실행이 같은 구독의 서로 다른 행을 동시에 보내면 일일 상한(카운터는 claim 시점의 값 기준)이 한 번 초과될 수 있습니다(중복 발송은 아님).
- 전송은 성공했는데 `sent_at` 기록이 두 번 모두 실패하면 claim이 5분 뒤 풀려 한 번 더 발송될 수 있습니다. 타임아웃된 전송이 실제로는 도착한 경우도 재시도로 중복될 수 있습니다(at-least-once).
- 전송은 순차입니다(느린 endpoint는 실행 예산을 소모). 병렬화는 필요해질 때 추가.

## 개인정보 주의 (만 14세 미만 포함)
- 저장 항목은 구독 endpoint/키, 알림 종류, 발송 시각, 취침 시간대, tz 오프셋, 일일 발송 횟수뿐. 캐릭터 이름·종·스탯 등 컬럼을 추가하지 마세요. 알림 문구는 고정 템플릿(`src/templates.ts`).
- 푸시 endpoint와 키는 기기를 식별할 수 있는 정보라 개인정보 처리방침에 "푸시 구독 정보"로 명시하고, 법정대리인 동의 절차는 PRD 7장 후속 과제에서 확정해야 합니다.
- 구독 해제(DELETE)와 만료 시 삭제가 구현되어 있으며, 발송 완료 행은 2일(키 있는 sick/evolve는 60일) 뒤 삭제됩니다. 별도 로그에 endpoint를 남기지 마세요(Supabase 함수 로그 포함).
- 문구는 부드러운 톤을 유지하세요(과몰입 유도 금지). 문구 변경은 `src/templates.ts`에서만.
- 이 문서는 법률 자문이 아닙니다.

## 검증 범위
검증됨: 순수 로직·핸들러·인메모리 저장소 단위 테스트(71개), 타입체크. **미검증**: SQL 마이그레이션(0001·0002) 실행과 `claim_due_pushes` 동시성, Supabase 저장소 구현, Deno 엔트리, 실제 web-push 전송, pg_cron 동작(Supabase/Deno/푸시 서비스 없이 작성됨).
