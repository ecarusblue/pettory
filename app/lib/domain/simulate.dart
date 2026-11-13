import 'time_util.dart';
import 'types.dart';

// 설계서 4장 상수 (분 단위).
const int kHungerThreshold = 360; // 180분 × 2 (스케일 2)
const int kHappyThreshold = 480; // 240분 × 2
const int kFatigueGainMinutes = 240;
const int kSleepRecoverMinutes = 60;
const int kSickAfterMinutes = 120;
const int kLeaveAfterSickMinutes = 1440;
const int kChildAt = 60;
const int kTeenAt = 1440;
const int kAdultAt = 3 * 1440;
const int kTierDecideAt = 7 * 1440;
const int kSampleEvery = 60;
const int kMaxSimMinutes = 30 * 1440;
const int kMaxPoop = 3;

/// 성체 분기: 70+ 우수 / 40~69 보통 / 40 미만 방치.
Tier decideAdultTier(double careScore) {
  if (careScore >= 70) return Tier.excellent;
  if (careScore >= 40) return Tier.normal;
  return Tier.neglect;
}

/// 샘플 평균 점수(0..100). 샘플이 없으면 0.
double careScoreOf(PetState s) =>
    s.careSampleCount == 0 ? 0 : s.careSampleSum8 / (8 * s.careSampleCount);

/// 한 시점의 상태 점수 ×8 (정수). PRD 식을 4배 하면 정수가 되고,
/// 아픔(×0.5)을 위해 한 번 더 2배 스케일한다.
int _sampleScore8(int hunger, int happiness, int poop, int fatigue, bool sick) {
  final base4 = 35 * hunger + 35 * happiness + 120 - 20 * poop - 15 * fatigue;
  return sick ? base4 : base4 * 2;
}

Stage _stageForAge(int age) {
  if (age >= kAdultAt) return Stage.adult;
  if (age >= kTeenAt) return Stage.teen;
  if (age >= kChildAt) return Stage.child;
  return Stage.baby;
}

/// `lastUpdatedAt`부터 [toMinute]까지 1분 틱으로 진행한다.
///
/// 순수 함수: 같은 입력이면 같은 출력, `simulate(t1)` 후 `simulate(t2)`는
/// 바로 `simulate(t2)`와 같다(분할 불변성). 한 번에 최대 30일까지만 진행하고
/// 초과분은 건너뛴다(그 전에 반드시 떠나므로 결과 동일).
(PetState, List<SimEvent>) simulate(PetState s, Settings cfg, int toMinute) {
  if (s.left || s.stage == Stage.egg || toMinute <= s.lastUpdatedAt) {
    return (s, const []);
  }
  final events = <SimEvent>[];
  final start = s.lastUpdatedAt;
  final end = toMinute - start > kMaxSimMinutes
      ? start + kMaxSimMinutes
      : toMinute;

  var stage = s.stage;
  var tier = s.adultTier;
  var hunger = s.hunger, happiness = s.happiness, fatigue = s.fatigue;
  var poop = s.poop;
  var sick = s.sick;
  var sickSince = s.sickSince;
  var sleeping = s.sleeping, asleep = s.asleep;
  var awakeUntil = s.awakeUntil;
  var hungerAcc = s.hungerAcc, happyAcc = s.happyAcc;
  var fatigueAcc = s.fatigueAcc, sleepAcc = s.sleepAcc;
  final queue = List<int>.of(s.poopQueue);
  var queueHead = 0;
  var hungerZeroSince = s.hungerZeroSince, poop3Since = s.poop3Since;
  var sum8 = s.careSampleSum8, count = s.careSampleCount;
  var lastSampleAt = s.lastSampleAt;
  var left = false;
  int? leftAt;
  var last = start;

  for (var t = start + 1; t <= end; t++) {
    last = t;
    // 1. 수면 판정
    if (awakeUntil != null && t >= awakeUntil) awakeUntil = null;
    final rawWindow = inSleepWindow(cfg, t);
    final inWin = rawWindow && awakeUntil == null;
    final asleepNow = inWin || sleeping;
    if (asleepNow != asleep) {
      events.add(
        SimEvent(asleepNow ? SimEventKind.fellAsleep : SimEventKind.woke, t),
      );
      asleep = asleepNow;
    }
    final prevHunger = hunger, prevPoop = poop;

    // 2~4. 배고픔/행복 감소 (스케일 2: 깨어 있으면 +2, 취침 시간대 +1)
    final inc = inWin ? 1 : 2;
    hungerAcc += inc;
    while (hungerAcc >= kHungerThreshold) {
      hungerAcc -= kHungerThreshold;
      if (hunger > 0) hunger--;
    }
    if (hunger == 0) hungerAcc = 0;
    happyAcc += inc;
    while (happyAcc >= kHappyThreshold) {
      happyAcc -= kHappyThreshold;
      if (happiness > 0) happiness--;
    }
    if (happiness == 0) happyAcc = 0;

    // 5. 피로
    if (asleepNow) {
      sleepAcc++;
      if (sleepAcc >= kSleepRecoverMinutes) {
        sleepAcc = 0;
        if (fatigue > 0) fatigue--;
        if (fatigue == 0 && sleeping) {
          sleeping = false; // 수동 수면은 피로 0에서 자동 기상
          if (!inWin) {
            events.add(SimEvent(SimEventKind.woke, t));
            asleep = false;
          }
        }
      }
    } else {
      sleepAcc = 0;
      fatigueAcc++;
      if (fatigueAcc >= kFatigueGainMinutes) {
        fatigueAcc = 0;
        if (fatigue < 4) fatigue++;
      }
    }

    // 6. 똥 발생
    while (queueHead < queue.length && queue[queueHead] <= t) {
      queueHead++;
      if (poop < kMaxPoop) {
        poop++;
        events.add(SimEvent(SimEventKind.poopSpawned, t));
      }
    }

    // 알림 투영용 임계 통과 이벤트
    if (prevHunger > 1 && hunger <= 1) {
      events.add(SimEvent(SimEventKind.hungerLow, t));
    }
    if (prevPoop < 2 && poop >= 2) {
      events.add(SimEvent(SimEventKind.poopPile, t));
    }

    // 7. 아픔 진입
    if (hunger == 0) {
      hungerZeroSince ??= t;
    } else {
      hungerZeroSince = null;
    }
    if (poop == kMaxPoop) {
      poop3Since ??= t;
    } else {
      poop3Since = null;
    }
    if (!sick &&
        ((hungerZeroSince != null &&
                t - hungerZeroSince >= kSickAfterMinutes) ||
            (poop3Since != null && t - poop3Since >= kSickAfterMinutes))) {
      sick = true;
      sickSince = t;
      events.add(SimEvent(SimEventKind.gotSick, t));
    }

    // 8. 떠남
    if (sick && sickSince != null && t - sickSince >= kLeaveAfterSickMinutes) {
      left = true;
      leftAt = t;
      events.add(SimEvent(SimEventKind.left, t));
      break;
    }

    // 9. 성장
    final age = t - s.birthAt;
    final target = _stageForAge(age);
    while (stage.index < target.index) {
      stage = Stage.values[stage.index + 1];
      events.add(SimEvent(SimEventKind.stageChanged, t, stage: stage));
    }
    if (tier == null && age >= kTierDecideAt && stage == Stage.adult) {
      tier = decideAdultTier(count == 0 ? 0 : sum8 / (8 * count));
      events.add(
        SimEvent(SimEventKind.adultFormDecided, t, stage: stage, tier: tier),
      );
    }

    // 10. 케어 점수 샘플 (부화 후 7일 미만, 취침 시간대 제외)
    if (t - lastSampleAt >= kSampleEvery) {
      lastSampleAt = t;
      if (age < kTierDecideAt && !rawWindow) {
        sum8 += _sampleScore8(hunger, happiness, poop, fatigue, sick);
        count++;
      }
    }
  }

  final newState = s.copyWith(
    stage: stage,
    adultTier: tier,
    lastUpdatedAt: left ? last : toMinute,
    hunger: hunger,
    happiness: happiness,
    fatigue: fatigue,
    poop: poop,
    sick: sick,
    sickSince: sickSince,
    sleeping: sleeping,
    asleep: asleep,
    awakeUntil: awakeUntil,
    hungerAcc: hungerAcc,
    happyAcc: happyAcc,
    fatigueAcc: fatigueAcc,
    sleepAcc: sleepAcc,
    poopQueue: queue.sublist(queueHead),
    hungerZeroSince: hungerZeroSince,
    poop3Since: poop3Since,
    careSampleSum8: sum8,
    careSampleCount: count,
    lastSampleAt: lastSampleAt,
    left: left,
    leftAt: leftAt,
  );
  return (newState, events);
}
