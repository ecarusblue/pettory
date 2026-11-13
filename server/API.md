# 펫토리 푸시 서버 API (클라이언트 계약)

Base URL: `https://<project>.supabase.co/functions/v1` (아래 경로는 함수 이름). 모든 요청/응답은 JSON. 로그인 없음(익명).
시각은 ISO-8601 UTC(`2026-11-14T01:00:00Z`) 또는 오프셋 포함 문자열만 허용합니다(오프셋 없는 문자열은 400).

서버가 저장하는 것: 푸시 구독(endpoint, 키), 알림 종류, 발송 시각, 취침 시간대, tz 오프셋, 일일 발송 횟수. **캐릭터 이름 등은 받지도 저장하지도 않습니다**(알 수 없는 필드는 무시).

## 공통
- 오류: `{ "error": "invalid_request", "details": ["..."] }` (400), `{"error":"subscription_not_found"}` (404), 405, 401.
- 추가 오류(이번 라운드 추가): `409 {"error":"subscription_conflict"}`(POST /subscribe, 아래), `413 {"error":"payload_too_large"}`(요청 본문 8KB 초과), `429 {"error":"rate_limited"}`(과다 호출; 잠시 후 재시도, 앱 실행 때마다 1회 수준이면 걸리지 않음). 이 값들은 기존 필드 변경이 아니라 새 상태 코드 추가입니다.
- 소유 증명: endpoint와 `auth` 키 쌍을 함께 보내야 PUT/DELETE가 동작합니다(endpoint만 알아서는 변경 불가).
- `tzOffsetMinutes`: 기기 로컬 = UTC + 값(분). KST = `540`. `sleepStart/sleepEnd`: 로컬 자정부터의 분(0..1439), 자정 걸침 가능(예: 22:00~07:00 = 1320, 420). 둘이 같거나 null이면 취침 시간 없음.

## (a) POST /subscribe
구독 등록/갱신(멱등, endpoint 기준 upsert). 앱 실행 때마다 호출해도 됩니다(만료로 삭제된 구독 재등록 겸용).
```json
{ "endpoint": "https://fcm.googleapis.com/...", "keys": { "p256dh": "...", "auth": "..." },
  "sleepStart": 1320, "sleepEnd": 420, "tzOffsetMinutes": 540 }
```
응답 200 `{ "ok": true }`. 검증 실패 400.
- **endpoint 허용 목록**: `https`(기본 포트, 자격 증명 없음)이며 호스트가 알려진 푸시 서비스여야 합니다: `fcm.googleapis.com`, `android.googleapis.com`, `updates.push.services.mozilla.com`(및 `*.push.services.mozilla.com`), `*.push.apple.com`, `*.notify.windows.com`. IP 주소, localhost, `.local`/`.internal` 등은 항상 400. 브라우저가 돌려주는 실제 `PushSubscription.endpoint`는 모두 해당됩니다(서버에서 `EXTRA_PUSH_HOSTS`로 추가 가능).
- **기존 endpoint 소유권**: 이미 등록된 endpoint는 **같은 `keys.auth`를 보낸 경우에만** 갱신됩니다(취침/tz/p256dh 갱신 포함, 앱 실행 때마다 호출하는 흐름 그대로). 다른 `auth`면 **409** `subscription_conflict`이고 아무것도 바뀌지 않습니다. 만료·재구독으로 브라우저가 **새 endpoint**를 주면 그대로 등록됩니다. 같은 endpoint에 새 키를 쓰고 싶으면 먼저 기존 `auth`로 `DELETE /subscribe` 한 뒤 다시 POST 하세요(409를 받으면 클라이언트는 `pushManager` 구독을 해제·재생성해 새 endpoint로 재시도).

## (b) PUT /schedule
해당 구독의 **미발송 예약 목록 전체 교체**. 같은 본문을 몇 번 보내도 결과 동일. `items: []`는 전체 삭제.
```json
{ "endpoint": "...", "auth": "...",
  "sleepStart": 1320, "sleepEnd": 420, "tzOffsetMinutes": 540,
  "items": [
    { "type": "hunger", "fireAt": "2026-11-14T01:00:00Z" },
    { "type": "poop",   "fireAt": "2026-11-14T03:00:00Z" },
    { "type": "sick",   "fireAt": "2026-11-14T05:00:00Z", "dedupeKey": "sick:3" },
    { "type": "evolve", "fireAt": "2026-11-14T06:00:00Z", "dedupeKey": "stage:2" }
  ] }
```
- `sleepStart/sleepEnd/tzOffsetMinutes`는 선택(설정 변경 시 함께 보내면 서버 값도 갱신).
- `type`: `hunger | poop | sick | evolve`. 최대 16개. `fireAt`은 서버 시각 기준 -24시간 ~ +14일.
- `dedupeKey`: **sick/evolve는 필수**(1~32자 `[A-Za-z0-9:_-]`, 이름 등 개인 정보 금지). 같은 키는 한 번만 발송(상태당/단계당 1회; 한 요청에 같은 `type`+`dedupeKey`가 여러 개면 서버가 가장 이른 시각 1건만 남김). 이미 발송된 키/시각이 다시 오면 저장하지 않으므로 목록 전체를 다시 보내도 중복 발송되지 않습니다. hunger/poop은 생략 가능(같은 시각 재전송은 무시).
- 서버가 취침 시간대에 걸린 시각을 기상 +30분으로 옮깁니다(클라이언트가 이미 옮겨 보내도 결과 동일).
- 응답 200 `{ "ok": true, "stored": 3 }`. 구독이 없으면 404 → `POST /subscribe` 후 재시도.

## (c) DELETE /subscribe
본문 `{ "endpoint": "...", "auth": "..." }`. 구독과 예약을 삭제. 이미 없어도 200(멱등). 알림을 끌 때 호출.

## (d) GET /time
```json
{ "now": "2026-11-13T12:34:56.789Z", "epochMs": 1794573296789 }
```
시간 무결성 비교용(`checkClock`의 serverNow). 데이터 접근 없음, 캐시 금지(`no-store`).

## (e) 내부 디스패처: POST /dispatch (클라이언트 호출 금지)
스케줄러(pg_cron)가 매분 호출. 헤더 `x-dispatch-secret: <DISPATCH_SECRET>` 필수(없거나 다르면 401). 동작:
1. `fire_at <= now`이고 미발송인 항목을 **선점(claim)**(최대 500건/회). 겹쳐 실행돼도 같은 항목은 한 실행만 가져가며(SQL `FOR UPDATE SKIP LOCKED`), 5분 넘은 claim은 죽은 실행으로 보고 회수합니다. 전송은 건당 10초 타임아웃, 실행 전체 40초 예산(초과분은 다음 분으로)이며 타임아웃은 일시 오류입니다.
2. 2시간 넘게 늦은 항목은 폐기(오래된 알림 방지).
3. 현재 취침 시간대면 기상+30분으로 연기.
4. 구독 로컬 날짜(tz 적용) 기준 일일 상한: 배고픔 2회, 똥 1회. 초과분은 다음 로컬 날 0시(취침 보정)로 연기. 아픔/진화는 `dedupeKey`당 1회.
5. 전송. HTTP 404/410이면 구독 삭제(기기는 다음 실행 때 재등록), 그 외 오류(타임아웃 포함)는 claim을 풀고 다음 분에 재시도. 한 행의 저장소 오류가 나머지 행 처리를 막지 않습니다.
응답: `{ sent, deferredSleep, deferredCap, droppedStale, droppedDuplicate, subscriptionsDeleted, failedTransient, releasedBudget, errors }` (내부용, 클라이언트 계약 아님).

### 푸시 페이로드 (Service Worker가 받는 JSON)
```json
{ "v": 1, "type": "hunger", "title": "펫토리", "body": "친구가 출출해할 때가 됐어요. 편할 때 한번 살펴봐 주세요.", "tag": "petory-hunger" }
```
고정 문구, 캐릭터 이름 없음. 앱이 열려 있으면 Service Worker가 표시를 생략(클라이언트 책임).
