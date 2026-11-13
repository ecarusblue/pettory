# 펫토리 QA 보고서

작성일 2026-11-13 · 범위: `app/`(Flutter), `server/`(푸시 서버), 기준 문서 `petory-prd.md`, `petory-logic-design.md`, `server/API.md`

## 1. 요약

**판정: 출시 불가.** 게임 로직(도메인)은 설계서 20개 항목과 분할 불변성을 모두 통과해 견고하지만, P0 기능인 Web Push 경로가 프론트에서 서버까지 한 곳도 이어져 있지 않고(가짜 클라이언트, 서비스 워커 미등록, 요청 형식 3종 불일치), 오프라인 캐시가 없으며, FR-5 미니게임 UI·FR-7 도감/추억 화면·FR-9 복귀 화면이 없습니다. 서버에도 중복 발송(동시 실행), 구독 덮어쓰기, 임의 URL 전송 같은 수정이 필요한 문제가 있습니다.

핵심 수치
- 앱: `flutter analyze` 이슈 0건, `flutter test` 80개 중 73 통과 / 7 skip(알려진 버그) / 0 실패.
- 서버: `npm test` 50개 중 43 통과 / 7 skip(알려진 버그) / 0 실패, `npm run typecheck` 오류 0건.
- 발견한 버그: 14건(앱·계약 7, 서버 7). 이 중 출시 차단급(Critical) 5건 = BUG-1, 2, 3, 5, 6. 모두 재현 테스트가 있고 skip 처리돼 있습니다.
- 도메인 로직(`app/lib/domain`) 버그는 발견하지 못했습니다(400개 무작위 + 40개 경계 시나리오 분할 불변성 포함).

## 2. 실행 결과

| 명령 | 결과 |
| --- | --- |
| `cd app && flutter analyze` | No issues found |
| `cd app && flutter test` | 73 통과, 7 skip, 0 실패 (기존 10 + 신규 70) |
| `cd server && npm test` | tests 50, pass 43, skipped 7, fail 0 (기존 23 + 신규 27) |
| `cd server && npm run typecheck` | 오류 없음 |
| `cd app && flutter build web` | 성공. `build/web` 41MB(CanvasKit 사본 포함), `main.dart.js` 2.78MB(비압축) |
| 로컬 정적 서버 + curl (`python3 -m http.server`, 브라우저 조작 없음) | `index.html` 200 text/html, `manifest.json` 200 application/json, `flutter_service_worker.js` 200, `push_sw.js` 200 text/javascript, `flutter_bootstrap.js`/`main.dart.js`/아이콘 200 |

참고: skip된 테스트 14개는 `skip:` 을 제거하면 모두 실제로 실패하는 것을 임시 복사본으로 확인했습니다(앱 7개, 서버 7개).

### skip(알려진 버그) 테스트 표

| 번호 | 파일 | 테스트 이름 | 요지 |
| --- | --- | --- | --- |
| BUG-1 | app/test/prd_acceptance_test.dart | `[BUG-1] NotifyType 이름이 서버 type 과 일치` | `hungry` ≠ 서버 `hunger` |
| BUG-2 | 〃 | `[BUG-2] Scheduled.toJson 은 ISO-8601(오프셋) fireAt 문자열` | `fireAtMinute`(정수) ≠ `fireAt`(ISO) |
| BUG-3 | 〃 | `[BUG-3] sick/evolve 항목에 dedupeKey 포함` | dedupeKey 필드 없음 |
| BUG-4 | 〃 | `[BUG-4] push_sw.js 가 서버 type(hunger) 의 문구를 가진다` | SW 문구 키 불일치 |
| BUG-5 | 〃 | `[BUG-5] push_sw.js 를 등록하는 코드가 있다` | SW 미등록 |
| BUG-6 | 〃 | `[BUG-6] 실제 PushScheduleClient 구현(HTTP)과 구독 등록 코드가 있다` | Fake 클라이언트만 사용 |
| BUG-7 | 〃 | `[BUG-7] 시계를 미래로 돌리면 서버 시각 비교로 차단되어야 함` | `GET /time` 미사용 |
| BUG-8 | server/test/qa_edge.test.ts | `[BUG-8] 동시에 두 번 디스패치해도 같은 알림을 한 번만 보낸다` | 동시 실행 중복 발송 |
| BUG-9 | 〃 | `[BUG-9] 행마다 구독 사본을 주는 저장소(Supabase 방식)에서도 같은 배치의 hunger 상한(2)을 지킨다` | 같은 분 배치에서 상한 초과 |
| BUG-10 | 〃 | `[BUG-10] sick/evolve 는 같은 dedupeKey 가 서로 다른 fireAt 으로 ...` | 같은 키 중복 발송 |
| BUG-11 | 〃 | `[BUG-11] dispatch 중 저장소 제약 위반 예외가 나도 배치 전체가 중단되지 않는다` | unique 충돌 시 배치 중단 (SQL 미검증) |
| BUG-12 | 〃 | `[BUG-12] endpoint 만 아는 제3자는 /subscribe 로 기존 구독의 키(auth)를 바꿀 수 없다` | 구독 덮어쓰기 |
| BUG-13 | 〃 | `[BUG-13] endpoint 는 알려진 푸시 서비스 호스트만 허용` | 임의 https URL 허용 |
| BUG-14 | 〃 | `[BUG-14] 응답 없는 push endpoint 하나가 디스패치 배치 전체를 멈추지 않는다` | 전송 타임아웃 없음 |

재현 방법: 해당 테스트의 `skip:` 인자를 제거하고 `flutter test test/prd_acceptance_test.dart` 또는 `cd server && node --test test/qa_edge.test.ts` 를 실행하면 실패합니다.

신규 파일
- `app/test/domain_spec_test.dart` (39개: 설계서 20개 + 분할 불변성 속성 기반 + 보조 경계)
- `app/test/prd_acceptance_test.dart` (31개: FR 수용 기준, 시간 무결성, 프론트-백엔드 계약)
- `server/test/qa_edge.test.ts` (27개)
- 기존 `domain_smoke_test.dart`, `widget_test.dart` 는 수정하지 않았습니다.

## 3. 설계서 9장 단위 테스트 20개 커버리지 대조

기존 = `domain_smoke_test.dart`, 신규 = `domain_spec_test.dart`. 기존은 항목별로 일부 경계만 확인하거나 아예 없었습니다.

| # | 항목 | 기존 | 신규 테스트 | 결과 |
| --- | --- | --- | --- | --- |
| 1 | 3시간 hunger 4→3, 6시간 →2 | 부분(180, 360만) | 1 (179/180/359/360, 행복 239/240) | 통과 |
| 2 | 취침 시간대 감소 절반 | 부분(소프트 확인) | 2 (180/359/360 분 경계, 낮과 대조) | 통과 |
| 3 | 22:00~02:00 경계 누산기 연속 | 없음 | 3 (손계산 299→4, 300→3, 경계 앞뒤 분할 7곳) | 통과 |
| 4 | 30일 미접속 0에서 멈춤 | 부분(떠남만) | 4 (스탯 0, 음수 없음, 45일/이후 호출 동일) | 통과 |
| 5 | 밥 후 120분 poop +1, 3개 이후 무시 | 부분(120분만) | 5 (큐 4건→poop 3, 4번째 소멸, 간식 180분) | 통과 |
| 6 | hunger 0 119분 정상/120분 아픔 | 없음 | 6 | 통과 |
| 7 | poop 3 120분 지속, 치우면 리셋 | 없음 | 7 (239/240, 치운 뒤 재누적 439/440) | 통과 |
| 8 | 약: 아플 때만, 일일 3번째 거부 | 부분(notSick만) | 8, 8b(KST 자정 경계), 8c·8d(놀아주기 5회, 미니게임 0/1/2) | 통과 |
| 9 | 깨어 4시간마다 fatigue +1 | 없음 | 9 (239/240/480/960, 상한 4) | 통과 |
| 10 | 수면 60분마다 -1, 0에서 자동 기상 | 없음 | 10, 10b, 10c(취침 중 수동 기상) | 통과 |
| 11 | 수면 중 밥 거부 | 없음 | 11 (밥·간식·놀기·똥·약·미니게임, 시간대 자동 수면 포함) | 통과 |
| 12 | 59분 baby, 60분 child, 1일 teen, 3일 adult | 부분(59/60) | 12 (1439/1440/4319/4320, 돌봄 도우미로 3일 생존) | 통과 |
| 13 | careScore 70/40 경계 | 부분(`decideAdultTier` 직접 호출만) | 13 (7일 시점 `adultFormDecided` 로 100/70/69.99/40/39.99/0), 13b, 13c(점수식·아픔 ×0.5) | 통과 |
| 14 | 방치 7일 낮은 점수, 취침 샘플 제외 | 없음 | 14 (샘플 수 = 취침 시간대 밖 시각 수), 14b | 통과 |
| 15 | 앱 종료 중 진화 이벤트 반환 | 없음 | 15 (child·teen·adult 이벤트와 시각) | 통과 |
| 16 | 아픔 1439 생존, 1440 left, 이후 중단 | 부분(30일 left만) | 16, 16b(약으로 타이머 리셋) | 통과 |
| 17 | `checkClock` | 있음 | 17 (60/61분 경계 등 보강) | 통과 |
| 18 | 취침에 걸린 알림 → 기상+30분 | 부분(창 밖 확인만) | 18 (17:00 부화 → 05:01 도달이 07:30 으로 이동, 창 없으면 02:00), 18b·18c·18d | 통과 |
| 19 | 결정성 | 있음 | 19 | 통과 |
| 20 | 분할 불변성 | 부분(1회 분할) | 아래 4개 테스트 | 통과 |

분할 불변성(20번) 검증 내용
1. 무작위 400 시나리오: 취침 설정 8종(자정 걸침, 비걸침 낮잠창, 창 없음, start==end, 분 단위 경계 `23:17~06:43`, tz -840/-300/+330/+345/+540/+840 등), 부화 시각 무작위, 절반은 무작위 선행 케어(밥·간식·놀기·치우기·재우기·깨우기·약·미니게임)를 적용한 상태에서 시작. 한 번 분할, 1~2000분 간격 다중 분할, JSON 저장/복원 삽입 후 상태와 이벤트 목록이 직접 실행과 일치.
2. 경계 집중 40 시나리오: 직접 실행에서 나온 모든 이벤트 시각의 ±1분과 취침 시간대 진입/이탈 ±1분에서 분할(좋은 돌봄 7일 경로, 최소 돌봄 경로, 방치 → 떠남 경로).
3. 떠남 직전/직후(-2~+500분), 7일 경계(-1/0/+1), 30일 상한 경로(10일→45일).
4. `applyCare` 가 사전 `simulate` 여부와 무관하게 같은 결과(150 시나리오 × 6 행동).

로직 관찰(버그 아님)
- 30일 상한 분기(`simulate` 의 `kMaxSimMinutes` 절단)는 규칙상 도달 불가입니다. 어떤 상태에서도 배고픔이 0이 되고 아픔→떠남까지 2일 안에 끝나므로, 그 분기가 실제로 영향을 주는 경우는 이미 떠난 펫뿐입니다. 이 경로는 떠난 펫을 대상으로만 테스트했습니다.
- 설계서 10장의 열린 질문 4건(수면 중 수동 기상 감소율, 케어 → careScore 직접 반영, 자동 부화 소급, daily 리셋 기준)은 현재 구현 가정(정상 속도, 상태 샘플만, 소급, 자정)대로 동작하며 테스트로 고정했습니다.

## 4. PRD 대비 점검 (FR-1 ~ FR-9)

| ID | 요구사항 | 구현 | 수용 기준 확인 |
| --- | --- | --- | --- |
| FR-1 온보딩 | 알 3종 선택 + 이름 | 구현 | 알 선택 → 시작하기 → 자동 부화 → "만나러 가기" = 탭 3회로 홈 진입(위젯 테스트 통과). 이름 기본값 "몽이", 최대 8자. 만 14세 미만 연령 확인은 없음(PRD 후속 과제) |
| FR-2 부화 | 10회 탭 또는 3분 자동 | 구현 | 컨트롤러 테스트: 2분 59초는 부화 전, 3분에 부화, 10탭 즉시 부화, 앱 종료 중 3분 경과 시 3분 시점으로 소급. 연출은 3초 뒤 자동 종료(5초 이내), 버튼으로 건너뛰기 가능. 단 앱이 닫힌 채 부화하면 부화 연출을 건너뜀(경미) |
| FR-3 홈 | 게이지 3, 상태 2, 케어 버튼 | 구현 | 위젯 테스트로 확인. 스탯 변화는 컨트롤러 1초 타이머 + 알림 갱신으로 반영 |
| FR-4 케어 | 밥·간식·놀기·똥·재우기·약 | 구현(+깨우기) | 컨트롤러·도메인 테스트 통과 |
| FR-5 미니게임 | 반응속도 미니게임, 일일 5회 한도, 안내 문구 | **부분** | 일일 5회 한도(기본 놀아주기와 합산)와 한도 안내 스낵바는 통과. **미니게임 화면 자체가 없음**(도메인의 `CareAction.minigame` 만 존재, UI 어디에도 호출 없음). 안내 문구는 "오늘은 더 할 수 없어요." 한 줄을 약·놀기가 공유 |
| FR-6 성장 | 진화 연출, 앱 종료 중 진화는 다음 실행에서 연출 | 구현 | 25시간 뒤 재실행 시 child→teen 순서로 대기열 생성, 홈 진입 시 다이얼로그가 순서대로 표시됨(위젯 테스트). 한계: 대기열이 메모리에만 있어 다이얼로그를 보기 전에 앱을 닫으면 연출이 사라짐(도감 해금은 이미 저장됨) |
| FR-7 도감 | 진화 도감 + 추억 탭 | **데이터만** | 도감 키·해금 시각, 추억 항목(이름·종·도달 단계·태어남/떠남 시각)은 저장됨. **도감 화면과 추억 탭 UI 없음** |
| FR-8 설정 | 취침 시간·알림·사운드·초기화 | 부분 | 변경 즉시 저장(테스트 통과), 초기화는 확인 팝업 필수(취소 시 유지, 확인 시 삭제 — 위젯 테스트 통과). 사운드 토글은 있으나 재생되는 소리가 없음. 알림 토글은 로컬 설정만 바꾸고 서버 구독 해제/권한과 연결되지 않음. 릴리스 빌드에도 "개발자 옵션"(시간 가속 ×2016)이 노출됨 |
| FR-9 복귀 | 복귀 안내 화면 | **미구현** | 경과 시간·변화 요약 화면 없음. 떠난 경우에만 `LeftScreen` 으로 이동 |

기타 P0·비기능 요구 (PRD 3장, 6장, 7장)

| 항목 | 상태 |
| --- | --- |
| Web Push 알림(클라이언트) | **미연결** (BUG-1~6). 알림 시각 계산(`nextNotifications`)과 서버 로직은 각각 동작하지만 이어져 있지 않음 |
| 알림 권한 요청(부화 직후), iOS 설치 안내 | 미구현 |
| PWA 설치 유도 | 미구현 (manifest 는 정상) |
| 오프라인 캐시 | **미구현.** 빌드 산출물의 `flutter_service_worker.js` 는 스스로 등록 해제하는 스텁이고 `flutter_bootstrap.js` 에 "Flutter's service worker is deprecated" 주석이 있음 |
| 외부 CDN 의존 | 빌드 설정상 CanvasKit 을 `www.gstatic.com/flutter-canvaskit/...` 에서, 한글 글리프 대체 글꼴을 `fonts.gstatic.com` 에서 받도록 되어 있음(번들에 한글 글꼴 없음). 오프라인에서 시작 불가, 14세 미만 이용자 IP 가 Google 로 전달. 브라우저 실행으로 확인하지는 못했고 `flutter_bootstrap.js`·`main.dart.js` 판독 근거 |
| 시간 무결성 | 과거 시계는 차단(테스트 통과). 미래 시계는 서버 시각 비교 없음(BUG-7) |
| 도감(P1), 사망·환생(P1) | 환생(새 알) 흐름은 동작, 도감 UI 없음 |
| 분석(Firebase)·개인정보처리방침·이용약관 페이지 | 미구현 |
| 접근성 | 코드상 Semantics 레이블, 모양 병기, 숫자 표기가 있음. 스크린 리더·색각 이상 실기 검증은 하지 못함 |
| 성능 목표(60fps, 콜드 스타트 3초) | 측정하지 못함 |

## 5. 발견한 버그 목록

심각도 기준: Critical(출시 차단), High(출시 전 수정), Medium(수정 권장), Low.

### 앱·프론트-백엔드 계약

**BUG-1 Critical · NotifyType 이름이 서버 type 과 다름**
- 재현: `NotifyType.values.map((e) => e.name)` = `hungry, poop, sick, evolve`. 서버는 `hunger | poop | sick | evolve` 만 허용합니다.
- 원인: `app/lib/domain/types.dart` 의 `enum NotifyType { hungry, ... }`.
- 영향: 서버의 PUT 검증이 항목 하나라도 틀리면 400 으로 전체 거부합니다. `hungry` 가 포함된 요청은 통째로 실패.
- 권장: 이름을 `hunger` 로 바꾸거나 직렬화 시 매핑. `push_sw.js` 와 `Ko` 의 참조도 함께 수정.

**BUG-2 Critical · fireAt 형식 불일치**
- 재현: `Scheduled(NotifyType.poop, 29000000).toJson()` = `{type: poop, fireAtMinute: 29000000}`.
- 서버: `fireAt` 에 오프셋 포함 ISO-8601 문자열만 허용(숫자·오프셋 없는 문자열은 400, 서버 테스트로 확인).
- 권장: `toJson` 에서 `DateTime.fromMillisecondsSinceEpoch(fireAt * 60000, isUtc: true).toIso8601String()` 으로 변환.

**BUG-3 Critical · dedupeKey 없음**
- 재현: `Scheduled` 에 필드 자체가 없음. 서버는 sick/evolve 에 dedupeKey 필수(없으면 400).
- 권장: 아픔은 `sick:<sickSince 로부터 만든 안정적 값>`, 진화는 `stage:<다음 단계 index>` 로 생성. 규칙은 `/^[A-Za-z0-9:_-]{1,32}$/`, 이름 등 개인 정보 금지. 단계당·상태당 1회 보장이 키 안정성에 달려 있으므로(같은 아픔에서 재계산해도 같은 키) 키는 상태에서 결정적으로 만들어야 함.

**BUG-4 High · push_sw.js 문구 키와 페이로드 가정이 서버와 다름**
- 재현: `MESSAGES` 키가 `hungry` 라 서버가 보내는 type `hunger` 는 `FALLBACK`("친구가 기다리고 있어요.")이 됨. SW 는 페이로드의 `title/body/tag/v` 를 쓰지 않고 `{type}` 만 가정하며, 문구가 서버 템플릿(`server/src/templates.ts`)과 다름(문구가 두 곳에 이중 관리됨).
- 권장: 서버 페이로드 `{v,type,title,body,tag}` 의 `title/body` 를 우선 사용하고 `MESSAGES` 는 폴백으로만. `tag` 는 페이로드의 값을 사용.

**BUG-5 Critical · push_sw.js 가 어디에서도 등록되지 않음**
- 재현: `web/index.html`, `lib/`, 빌드된 `flutter_bootstrap.js` 모두 `push_sw` 참조 없음. 파일 자체는 `build/web/push_sw.js` 로 서빙됨(curl 200).
- 보강: Flutter 의 `flutter_service_worker.js`(스텁)와 스코프가 겹치므로 별도 스코프에 등록하거나 `importScripts` 로 합치는 설계 결정이 필요(파일 주석도 같은 내용을 언급).

**BUG-6 Critical · 푸시 클라이언트가 가짜**
- 재현: `lib/main.dart` 가 `FakePushScheduleClient` 와 구독 정보 `fake://local` 을 사용. `/subscribe`, `/schedule`, `/time` 을 호출하는 코드와 `Notification.requestPermission`/`pushManager.subscribe`(VAPID 공개키) 호출이 없음. 알림 권한 요청 UI, iOS 설치 안내도 없음.
- 영향: 서버를 배포해도 실제 알림은 한 건도 가지 않음.
- 권장: HTTP 구현(`replaceSchedule` → PUT, 앱 실행 시 POST /subscribe 로 재등록, 알림 끄기·초기화 시 DELETE /subscribe), 실패 시 다음 재계산 때 재시도(현재 컨트롤러가 예외를 삼킴).

**BUG-7 Medium · 미래 시계 조작 방어 없음**
- 재현: 기기 시각을 10일 앞으로 돌리면 펫이 그대로 떠남. `checkClock` 의 `serverNow` 가 항상 null 이고 `GET /time` 호출이 없음.
- 관련: 설정 > 개발자 옵션의 시간 가속(×60/×720/×2016)이 릴리스 빌드에도 노출돼 사실상 치트로 쓸 수 있음. 빌드 플래그(`kDebugMode`/`--dart-define`)로 숨기기 권장.

### 서버

**BUG-8 High · 겹친 디스패치 실행에서 중복 발송**
- 재현: `Promise.all([runDispatch, runDispatch])` 로 같은 due 행 1건에 대해 발송 2회. `listDue` 가 행을 선점(claim)하지 않고, `send` 후에 `markSent` 를 하기 때문. Supabase 저장소의 `.is("sent_at", null)` 조건은 이미 발송된 뒤의 중복 기록만 막고 중복 전송은 막지 못함.
- 발생 조건: pg_cron 매분 호출이 이전 실행이 끝나기 전에 시작될 때(지연·재시도·수동 호출).
- 권장: `UPDATE ... SET claimed_at=now() WHERE sent_at IS NULL AND claimed_at IS NULL ... RETURNING`(또는 `FOR UPDATE SKIP LOCKED`) 로 선점 후 발송, 실패 시 선점 해제.

**BUG-9 Medium · 같은 분에 due 인 같은 종류가 상한 초과 가능**
- 재현: 구독 객체를 행마다 복제해 주는 저장소(PostgREST 임베드 select 와 동일한 형태)에서 hunger 3건이 동시에 due 이면 3건 모두 발송, `sent_today` 는 1로 기록. `MemoryStore` 는 같은 객체를 공유해서 기존 테스트로는 가려짐.
- 권장: 디스패치 루프에서 구독 id 별 카운터 맵을 따로 유지하거나, 구독을 id 로 한 번만 조회.

**BUG-10 Low · 같은 dedupeKey 가 다른 fireAt 으로 두 번 들어오면 둘 다 발송**
- 재현: 한 PUT 에 `sick:1` 두 건(시각 다름) → 발송 2회. API.md 는 "같은 키는 한 번만 발송".
- 권장: 검증 단계에서 `type|dedupeKey` 중복을 접기(가장 이른 시각 유지), DB 에 `unique(subscription_id, type, dedupe_key) where dedupe_key is not null`.

**BUG-11 Medium · DB unique 충돌 시 배치 중단 (SQL 미실행, 코드 판독 근거)**
- 근거: 마이그레이션의 `unique (subscription_id, type, fire_at)` 와 `reschedule`(상한·취침 연기)이 충돌할 수 있음. 같은 종류 행 여러 건이 같은 시각으로 연기되면 UPDATE 가 예외를 던지고, 디스패치 루프에 try/catch 가 없어 그 분의 나머지 행이 처리되지 않음. 문제 행은 갱신되지 않아 만료(2시간)까지 매분 반복. 재현 테스트는 unique 를 흉내 낸 저장소로 작성(`UniqueStore`).
- 권장: 행 단위 try/catch 와 오류 로그(endpoint 제외), 충돌 시 한 건 삭제 또는 +1분 오프셋.

**BUG-12 High(보안) · POST /subscribe 로 기존 구독의 키를 덮어쓸 수 있음**
- 재현: 같은 endpoint 에 다른 `keys.auth/p256dh` 로 POST 하면 200 이고 기존 키가 교체됨. 이후 정상 기기의 PUT/DELETE 는 404, 서버가 새 키로 암호화한 푸시는 정상 기기가 복호화하지 못함.
- API.md 의 "endpoint만 알아서는 변경 불가"와 모순. endpoint 는 비밀 URL 이라 위험도가 다소 낮지만, 소유 증명이 우회됨.
- 권장: 이미 존재하는 endpoint 의 키 변경은 기존 `auth` 를 요구하거나, 키가 다르면 거부하고 기기가 DELETE 후 재등록하도록.

**BUG-13 Medium(보안) · endpoint 가 https 이기만 하면 임의 주소 허용**
- 재현: `https://169.254.169.254/...`, `https://localhost/...`, 임의 호스트가 모두 200 으로 등록됨. 디스패처(Edge Function)가 그 주소로 암호화된 POST 를 보냄(SSRF 성격, 응답 본문은 노출되지 않지만 내부 서비스 호출·포트 스캔에 악용 가능).
- 권장: 알려진 푸시 서비스 호스트 허용 목록(`fcm.googleapis.com`, `updates.push.services.mozilla.com`, `*.push.apple.com`, `*.notify.windows.com` 등)으로 제한.

**BUG-14 Medium · 전송 타임아웃/병렬성 없음**
- 재현: 응답하지 않는 endpoint 하나가 있으면 `runDispatch` 가 영원히 끝나지 않아 같은 분의 다른 구독 발송도 멈춤. `web_push_sender.ts` 가 `timeout` 옵션을 쓰지 않고 루프가 순차 await.
- 권장: 전송당 타임아웃(예 5초)과 제한된 병렬 처리.

### 기타 관찰 (테스트 없이 판독으로 확인)
- 저장소에 `.gitignore` 가 `server/` 에 없음(git 저장소가 아니라 현재는 무해, 도입 시 `.env`/`node_modules` 제외 필요).
- `x-dispatch-secret` 비교가 상수 시간이 아니고 호출 제한이 없음(낮음). `/subscribe` 에도 호출 제한이 없어 무제한 구독 생성 가능.
- 초기화·알림 끄기 시 서버 구독·예약 정리(DELETE) 호출이 없음(클라이언트 연결 시 필요).
- 앱 종료 중 부화되면 부화 연출을 건너뜀, 진화 대기열이 메모리에만 있음(FR-2, FR-6 경미).
- `push_sw.js` 의 `badge` 아이콘이 컬러 아이콘이라 안드로이드 상태 표시줄에서 흰 사각형으로 보일 수 있음(실기 미확인).

## 6. 프론트-백엔드 계약 불일치 목록

| 항목 | 프론트 (현재) | 서버 (API.md / 코드) | 상태 |
| --- | --- | --- | --- |
| 알림 종류 이름 | `hungry` | `hunger` | 불일치 (BUG-1) |
| 발송 시각 필드 | `fireAtMinute`: epoch 분 정수 | `fireAt`: 오프셋 포함 ISO-8601 문자열 | 불일치 (BUG-2) |
| dedupeKey | 없음 | sick/evolve 필수, 1~32자 `[A-Za-z0-9:_-]` | 누락 (BUG-3) |
| 푸시 페이로드 | SW 는 `{type}` 만 가정, 자체 문구 | `{v,type,title,body,tag}` 고정 문구 | 불일치 (BUG-4) |
| SW 문구 키 | `hungry` | `hunger` | 불일치 (BUG-4) |
| SW 등록 | 어디에도 없음 | 푸시 수신에 필요 | 누락 (BUG-5) |
| HTTP 클라이언트 | `FakePushScheduleClient` | `POST /subscribe`, `PUT /schedule`, `DELETE /subscribe`, `GET /time` | 미구현 (BUG-6) |
| 구독 정보 | `fake://local`, 빈 키 | 실제 endpoint, `keys.p256dh/auth` 8자 이상 base64url | 미구현 (BUG-6) |
| 취침/tz 필드 | `sleepStart`, `sleepEnd`, `tzOffsetMinutes`(UTC+분, KST=540, 로컬 자정부터의 분) | 동일 이름·의미 | 일치 |
| 소유 증명 | `PushSubscriptionInfo.auth` 보유 | PUT/DELETE 에 endpoint+auth 필요 | 일치(전송 코드 없음) |
| 캐릭터 이름 | `Scheduled`/구독 정보에 이름 없음(테스트 확인) | 받지도 저장하지도 않음(알 수 없는 필드 무시, 테스트 확인) | 일치 |
| 앱 열림 시 알림 생략 | SW 가 보이는 창이 있으면 생략 | 클라이언트 책임으로 명시 | 일치 |
| 시간 비교 | `checkClock(serverNow)` 지원, 호출 없음 | `GET /time` 제공 | 미연결 (BUG-7) |
| 알림 목록 크기 | 최대 4건 | 최대 16건 | 일치 |

위 3개(BUG-1~3)는 각각 단독으로도 PUT 전체를 400 으로 만듭니다. 현재 `nextNotifications` 가 `hungry` 를 항상 포함하므로 한 가지만 고쳐서는 통과하지 못합니다. 위에서 재현한 계약 테스트의 `skip:` 을 제거하면 3개 모두 실패하는 것으로 확인했습니다.

## 7. 서버 추가 테스트 결과 (통과한 것 포함)

`server/test/qa_edge.test.ts` 에서 통과한 주요 항목: 순차 반복 디스패치는 중복 없음 / 취침 22~07 + 상한 초과가 자정(취침 중)에 걸리면 다음 날 07:30 으로 연기 후 정상 발송 / 취침 01~05(자정 비포함)이면 정확히 다음 로컬 0시 / poop 상한 연기와 취침 중 도래한 sick 보류(07:30) / 밤새 보류된 알림이 stale 로 폐기되지 않음(보정 시각 기준) / stale 경계(정확히 2시간은 발송, +1ms 는 폐기) / 500건 배치 한도와 다음 실행 이어서 처리 / 한 구독 410 이 다른 구독 발송을 막지 않음 / tz -300 에서 로컬 날짜 경계(05:00Z)에서 상한 리셋 / `localDay` 음수·에폭 이전 값 / tz -840, 840, 345(+05:45) 허용·841, 5.5, "540", NaN 거부 / 극단 tz 에서 취침 보정과 멱등성 / PUT 부분 설정(tz 만 변경, sleepStart null 로 창 해제) / fireAt -24h, +14d 경계 / fireAt 형식(Z, +00:00, +09:00 허용, 숫자·오프셋 없음·빈 값 거부) / dedupeKey 검증 / 임의 필드(이름) 비저장 / 잘못된 auth 의 DELETE 는 200 이지만 삭제하지 않음 / 구독 입력 검증 / 재구독 시 카운터 유지.

## 8. 보안·개인정보 점검

- 하드코딩된 키: `app/lib`, `app/web`, `server/src`, `server/functions`, `server/migrations`, README 를 패턴(service_role, PRIVATE, secret, apikey, JWT, `sk-`, PEM 헤더) 검색한 결과 실제 키/시크릿 값은 없음. VAPID 키·`DISPATCH_SECRET`·service role 키는 모두 환경변수에서만 읽음. `DISPATCH_SECRET` 미설정 시 디스패처는 항상 401(안전한 기본값).
- 캐릭터 이름 전송 경로: 없음. 이름은 기기 localStorage(`petory.save.v1`)에만 저장되고, `Scheduled`·`PushSubscriptionInfo`·서버 스키마 어디에도 이름 필드가 없음(테스트로 확인). 서버는 알 수 없는 필드를 무시.
- 서버 저장 항목: endpoint, 키(p256dh, auth), 알림 종류·시각, 취침 시간대, tz, 일일 횟수. endpoint·키는 기기 식별 정보이므로 개인정보 처리방침과 14세 미만 동의 절차가 필요(문서에도 명시됨, 미구현).
- 클라이언트 외부 요청: 코드상 서버 호출은 없음(Fake). 다만 빌드 설정상 CanvasKit·한글 글꼴을 Google CDN(gstatic)에서 받음 — 14세 미만 개인정보 점검 대상. 분석 SDK 는 없음.
- **RLS(읽기 판독, 미검증):** 두 테이블 모두 `enable row level security` + 정책 없음 + `anon/authenticated` 에서 `revoke all` + 시퀀스 revoke. `replace_schedule`/`purge_sent_pushes` 는 `service_role` 에게만 execute 허용. 설계 의도(익명 클라이언트의 직접 DB 접근 차단, Edge Function 만 service role 로 접근)는 올바르게 보입니다. 단 SQL 을 실제로 실행하지 못했으므로 **미검증**입니다(문법 오류, 확장 `gen_random_uuid` 가용성, 실제 권한 상태, `distinct on` + `on conflict` 조합의 동작, PostgREST 임베드 select 의 형태).
- 위에서 다룬 서버 보안 이슈: BUG-12(구독 덮어쓰기), BUG-13(임의 URL 전송), 호출 제한 없음, CORS 기본값 `*`(`ALLOWED_ORIGIN` 설정 필요), 디스패치 시크릿 비교가 상수 시간이 아님.

## 9. 검증하지 못한 것

- 실제 브라우저 동작 일체(요청에 따라 브라우저 조작을 하지 않음): PWA 설치, 서비스 워커 등록 결과, CanvasKit/글꼴 CDN 요청 여부, 한글 렌더링, 모바일 뷰포트·레이아웃, 접근성(스크린 리더), 60fps·콜드 스타트 3초·번들 크기 목표.
- 실제 Web Push 전송, iOS 16.4+ 설치형 PWA 푸시, 안드로이드 Chrome 푸시.
- Supabase 전체: SQL 마이그레이션 실행, `createSupabaseStore`, Deno 엔트리(`functions/`), `npm:web-push` 호환, pg_cron/pg_net 스케줄, RLS 실제 효과. 서버 테스트는 `MemoryStore`/`FakeSender` 기반이며 BUG-9·11 은 실제 저장소의 동작을 모사한 테스트 더블로 재현했습니다.
- 실기기 시간대·서머타임 변경, 장시간(실시간 7일) 플레이, 다중 탭 동시 실행(localStorage 경합).
- 법적 항목(상표, 아동 개인정보 동의), 분석/크래시 리포트, 사운드.
- 플레이 밸런스(수치 적절성): 설계서/PRD 수치를 그대로 구현했는지만 확인했고 재미·난이도는 평가하지 않았습니다.

## 10. 권장 수정 순서

1. BUG-1/2/3/5/6: 푸시 클라이언트 실제 구현(직렬화 3종 수정 + HTTP + 구독 + SW 등록 + 권한 요청). 이후 계약 테스트 4종의 `skip` 제거.
2. 오프라인 캐시/외부 CDN 의존 해소(자체 서비스 워커 또는 CanvasKit·한글 글꼴 로컬 번들), 개발자 옵션 숨기기.
3. FR-5 미니게임 UI, FR-7 도감·추억 화면, FR-9 복귀 화면.
4. 서버 BUG-8, 12, 13, 14 후 BUG-9, 10, 11.
5. 개인정보 처리방침·14세 미만 동의·연령 확인 결정.
