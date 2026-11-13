# 펫토리 게임 로직 설계 (순수 함수 모듈)

PRD 4장 "세부 수치 규칙"을 구현 가능한 형태로 풀어쓴 설계서입니다. 구현 전 검토용이며, 언어는 Dart를 가정하지만 로직 자체는 언어 중립입니다.

## 1. 원칙

- UI·저장소·시계에 의존하지 않는 순수 함수. 현재 시각은 항상 인자로 받는다 (`DateTime.now()` 직접 호출 금지).
- 시각은 UTC 분 단위 정수(`epochMinutes`)로 저장·계산한다. 시간대·서머타임은 취침 시간대 판정 시점에만 로컬 오프셋으로 변환한다.
- 상태는 불변 객체. `simulate`는 새 상태와 이벤트 목록을 반환한다.
- 같은 입력이면 항상 같은 출력(난수 없음). 테스트와 가속 디버그 모드가 쉬워진다.

## 2. 타입

```
Stage      : egg | baby | child | teen | adult
Species    : eggA | eggB | eggC                  // 알 종류
Form       : (species, stage, tier?)             // tier: excellent | normal | neglect (성체만)

PetState {
  stage, birthAt, lastUpdatedAt
  hunger 0..4, happiness 0..4, fatigue 0..4
  poop 0..3
  sick: bool, sickSince?: minutes
  sleeping: bool
  // 진행 중 누산기 (내부 상태, 저장 대상)
  hungerAcc, happyAcc, fatigueAcc: double      // 감소/증가 진행도
  poopQueue: List<minutes>                      // 예정된 똥 발생 시각
  hungerZeroSince?, poop3Since?: minutes        // 아픔 진입 타이머
  careSampleSum, careSampleCount                // careScore 누적
  lastSampleAt
  daily: { day, playCount, medicineCount }      // 일일 한도 (로컬 날짜 기준)
}

Settings { sleepStart, sleepEnd (로컬 시각, 분), tzOffsetMinutes }

SimEvent  : stageChanged | gotSick | poopSpawned | fellAsleep | woke
          | left(사망/떠남) | adultFormDecided | notifyDue
```

## 3. 핵심 함수

| 함수 | 시그니처 | 설명 |
| --- | --- | --- |
| `simulate` | `(PetState, Settings, toMinute) -> (PetState, List<SimEvent>)` | `lastUpdatedAt`부터 `toMinute`까지 1분 틱으로 진행 |
| `applyCare` | `(PetState, Settings, CareAction, now) -> Result<PetState, CareError>` | 호출 전에 `simulate(now)`를 먼저 수행. 한도·수면 중 제한 검사 |
| `checkClock` | `(lastSavedAt, deviceNow, serverNow?) -> effectiveNow` | 7장 시간 무결성 규칙 |
| `nextNotifications` | `(PetState, Settings, now) -> List<Scheduled>` | 6장 알림 예약 규칙. 상태를 미래로 투영해 종류별 발송 시각 계산 |
| `careScoreOf` | `(PetState) -> double` | 샘플 평균 |
| `decideAdultTier` | `(careScore) -> tier` | 70+ 우수 / 40~69 보통 / 40 미만 방치 |

`applyCare`는 항상 `simulate` 이후에 적용하므로, 호출부 규칙은 "행동 전 simulate, 행동, 저장" 한 가지로 고정한다.

## 4. 시뮬레이션 루프 (1분 틱)

7일 = 10,080틱, 30일 상한 = 43,200틱이라 성능 문제 없음. 구간별 수식 대신 틱 반복으로 경계 조건 버그를 줄인다.

장기 미접속 상한: 한 번의 `simulate`는 최대 30일까지만 진행하고 그 이상은 30일로 자른다(이미 떠났거나 하한에 멈춘 상태이므로 결과 동일).

각 틱(`t`)에서 순서대로:

1. **수면 판정**: `inSleepWindow(t)` 이거나 `sleeping == true`이면 수면 상태. 수면 시작은 `fellAsleep` 이벤트.
2. **감소율**: 수면 시간대면 배율 0.5, 아니면 1.0.
3. **배고픔**: `hungerAcc += rate`; 180 도달 시 `hunger -= 1`, 누산기에서 180 차감(하한 0).
4. **행복**: 같은 방식, 240분당 -1.
5. **피로**: 깨어 있으면 `fatigueAcc += 1`, 240 도달 시 `fatigue += 1`(상한 4). 수면 중이면 60분마다 `fatigue -= 1`, 0이 되면 수동 수면은 자동 기상. 수면 시간대에 의한 자동 수면은 기상 시각까지 유지.
6. **똥**: `poopQueue`에 `t`가 도래한 항목마다 `poop += 1`(상한 3).
7. **아픔 진입**: `hunger == 0`이 120분 지속, 또는 `poop == 3`이 120분 지속이면 `sick = true`, `sickSince = t`. 조건이 풀리면 타이머 리셋.
8. **떠남**: `sick`이고 `t - sickSince >= 1440`이면 `left` 이벤트, 시뮬레이션 종료(이후 틱은 진행하지 않음).
9. **성장**: `t - birthAt`이 60분 / 1일 / 3일에 도달하면 stage 전환 이벤트. 7일 도달 시 `decideAdultTier`로 성체 형태 확정.
10. **케어 점수 샘플**: 매 60분(`t - lastSampleAt >= 60`)마다, 부화 후 7일 이내이고 취침 시간대가 아닐 때만 점수를 계산해 누적.

세부 결정(PRD에서 모호했던 부분, 이 설계의 가정):

- 청결 항목은 `(1 - poop/3)`으로 계산하고 PRD의 "청결" 스탯은 별도 값으로 두지 않는다. 데이터 모델 `PetStats.hygiene`은 `poop`에서 파생한다.
- 똥 발생 예약: 밥 `+120분`, 간식 `+180분`에 `poopQueue`에 추가. 3개가 이미 쌓여 있으면 발생 시점에 무시한다.
- 아픔은 약(`applyCare(medicine)`)으로만 풀린다. 약을 주면 `sickSince`와 타이머를 리셋한다.
- 알 단계(`egg`)는 스탯 감소를 하지 않는다. 부화 후 `birthAt`을 기준으로 시작한다.
- 부화는 자동 3분 또는 10회 탭 후 클라이언트가 `birthAt = now`로 호출한다. 로직 모듈은 부화 이후만 다룬다.

## 5. 케어 행동 규칙

| 행동 | 효과 | 제한 |
| --- | --- | --- |
| 밥 | `hunger += 2`(상한 4), 똥 예약 +120분 | 수면 중이면 먼저 기상 필요 |
| 간식 | `hunger += 1`, 똥 예약 +180분 | 동일 |
| 놀아주기 | `happiness += 1`, `fatigue += 1` | 일일 5회(미니게임 합산) |
| 미니게임 | 점수 구간별 `happiness += 0/1/2`, `fatigue += 1` | 일일 5회 합산 |
| 똥 치우기 | `poop = 0` | - |
| 재우기 | `sleeping = true` | 피로 0이면 즉시 기상하므로 거부(`alreadyRested`) |
| 약 주기 | `sick = false` | 일일 2회, 아프지 않으면 거부 |
| 깨우기 | `sleeping = false` | 취침 시간대에 수동 기상하면 시간대 종료까지 감소율 배율 1.0 적용 |

일일 카운터는 로컬 날짜(`tzOffset` 적용) 기준으로 리셋한다.

## 6. 시간 무결성 (`checkClock`)

```
if deviceNow < lastSavedAt:            return lastSavedAt          // 과거로 돌림 → 경과 0
if serverNow != null and
   deviceNow - serverNow > 60분:       return serverNow            // 미래로 돌림
return deviceNow
```

- 서버 시각 비교는 푸시 서버에 접근 가능할 때만. 오프라인에서는 위 첫 규칙만 적용된다.
- 편차 허용치 60분은 제안값이다.

## 7. 알림 예약 (`nextNotifications`)

현재 상태를 복사한 뒤 `simulate`를 최대 72시간 앞으로 돌려 이벤트 발생 시각을 찾는 방식으로 구현한다(별도 예측 수식을 만들지 않아 규칙이 이중화되지 않는다).

| 종류 | 조건 |
| --- | --- |
| 배고픔 | 투영 중 `hunger <= 1`이 되는 첫 시각 |
| 똥 | 투영 중 `poop >= 2`가 되는 첫 시각 |
| 아픔 경고 | `gotSick` 이벤트 시각 |
| 진화 임박 | 다음 `stageChanged` 시각 - 10분 |

- 취침 시간대에 걸리면 기상 시각 + 30분으로 이동.
- `dedupeKey`(server/API.md): sick/evolve 항목에 필수. 서버가 같은 키를 한 번만 발송하므로 같은 상태에서 다시 계산해도 같은 값이어야 한다. 아픔은 `sick:<gotSick 이벤트 분(epoch)>`(= 그때의 `sickSince`), 진화는 `stage:<다음 단계 index>:<태어난 분 36진수>`. 형식 `[A-Za-z0-9:_-]{1,32}`, 이름 등 개인 정보 금지. 태어난 분을 넣는 이유는 환생한 새 펫의 같은 단계 알림이 이전 펫의 발송 기록에 막히지 않게 하기 위함. hunger/poop 은 키 없음.
- 직렬화: type 은 `hunger|poop|sick|evolve`, fireAt 은 UTC ISO-8601(`...Z`).
- 일일 상한은 서버가 집행. 클라이언트는 목록 전체를 교체 전송.
- 앱이 열려 있는 동안의 표시 생략은 Service Worker 쪽 책임이라 이 모듈 범위 밖.

## 8. 가속 디버그 모드

`simulate`가 시각을 인자로 받으므로, 디버그 모드는 `speed` 배율을 곱해 `now`를 계산해 넘기기만 하면 된다. 로직 변경 없음. 알→성체 한 바퀴(7일)를 `speed = 2016`(약 5분)으로 확인한다.

## 9. 단위 테스트 목록

시간 경과 계산
1. 3시간 경과 시 hunger 4 → 3, 6시간 경과 시 → 2
2. 취침 시간대에는 감소가 절반 (같은 3시간에 hunger 변화 없음)
3. 시간대 경계 걸침(22:00~02:00 구간)에서 누산기가 연속
4. 장기 미접속(30일)에서 스탯이 0에서 멈춤

똥·건강
5. 밥 후 120분에 poop +1, 3개 이후 무시
6. hunger 0이 119분 → 정상, 120분 → 아픔
7. poop 3이 120분 지속 → 아픔, 도중에 치우면 타이머 리셋
8. 약 주기: 아플 때만 성공, 일일 3번째는 거부

피로·수면
9. 깨어 4시간마다 fatigue +1
10. 수면 중 60분마다 -1, 0에서 자동 기상(수동 수면)
11. 수면 중 밥 주기는 거부

성장·분기
12. 부화 후 59분 baby, 60분 child, 1일 teen, 3일 adult
13. 7일에 careScore 70/40 경계값 (69.99, 70, 39.99, 40)
14. 방치 7일 시 careScore가 낮고 취침 시간대 샘플은 제외
15. 앱 종료 중 진화가 `simulate` 이벤트로 반환됨 (FR-6)

떠남
16. 아픔 1439분 → 생존, 1440분 → `left`, 이후 틱 중단

무결성·알림
17. `checkClock`: 과거 시각 → 경과 0, 미래 편차 61분 + 서버 시각 → 서버 기준
18. 알림: 취침 시간대에 걸린 발송이 기상 + 30분으로 이동
19. 동일 입력 `simulate` 두 번 호출 결과가 같음 (결정성)
20. `simulate(t1)` 후 `simulate(t2)`와 한 번에 `simulate(t2)`의 결과가 같음 (분할 불변성)

20번이 가장 중요하다. 앱을 자주 열고 닫아도 결과가 달라지면 안 되기 때문이다.

## 10. 열린 질문 (PRD에서 확정 필요)

- 수면 시간대 중에 사용자가 직접 깨웠을 때의 감소율 처리 (현재 가정: 시간대가 끝날 때까지 정상 속도).
- 놀아주기·밥 등 케어 행동이 careScore에 직접 영향을 주지 않는 것이 의도인지 (현재: 상태 샘플로만 반영).
- 알 단계에서 자동 부화 3분 이후 앱을 닫았을 때 `birthAt`을 3분 시점으로 소급할지, 다음 실행 시각으로 할지 (권장: 3분 시점 소급).
- `daily` 리셋 기준 시각을 자정으로 할지, 취침 종료 시각으로 할지 (권장: 자정).
