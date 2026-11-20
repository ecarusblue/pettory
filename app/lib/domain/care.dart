import 'simulate.dart';
import 'time_util.dart';
import 'types.dart';

enum CareKind { feed, snack, play, minigame, cleanPoop, sleep, medicine, wake }

enum CareError {
  /// 수면 중이라 먼저 깨워야 함.
  asleep,
  alreadySleeping,
  notAsleep,

  /// 피로 0이라 재울 수 없음.
  alreadyRested,

  /// 일일 한도(놀아주기 5회 / 약 2회) 초과.
  dailyLimit,
  notSick,

  /// 이미 떠난 펫.
  left,
}

class CareAction {
  const CareAction._(this.kind, [this.minigameGain = 0]);
  final CareKind kind;

  /// 미니게임 점수 구간에 따른 행복 증가량(0/1/2).
  final int minigameGain;

  static const feed = CareAction._(CareKind.feed);
  static const snack = CareAction._(CareKind.snack);
  static const play = CareAction._(CareKind.play);
  static const cleanPoop = CareAction._(CareKind.cleanPoop);
  static const sleep = CareAction._(CareKind.sleep);
  static const medicine = CareAction._(CareKind.medicine);
  static const wake = CareAction._(CareKind.wake);
  factory CareAction.minigame(int happinessGain) =>
      CareAction._(CareKind.minigame, happinessGain.clamp(0, 2));
}

class CareResult {
  const CareResult.ok(PetState this.state, this.events) : error = null;
  const CareResult.err(CareError this.error, this.state, this.events);

  /// 성공 시 행동이 반영된 상태, 실패 시 `simulate(now)`까지만 반영된 상태.
  final PetState? state;
  final CareError? error;

  /// `simulate` 중 발생한 이벤트(+ 행동으로 인한 수면/기상 이벤트).
  final List<SimEvent> events;
  bool get ok => error == null;
}

List<int> _insertSorted(List<int> q, int v) {
  final out = List<int>.of(q)..add(v);
  out.sort();
  return out;
}

int _clamp4(int v) => v < 0 ? 0 : (v > 4 ? 4 : v);

/// 행동 적용. 내부에서 먼저 `simulate(now)`를 수행하므로 호출부는
/// "applyCare 결과를 저장"만 하면 된다 (이미 simulate된 상태여도 결과 동일).
CareResult applyCare(PetState state, Settings cfg, CareAction action, int now) {
  final (sim, events) = simulate(state, cfg, now);
  var s = sim;
  if (s.left) return CareResult.err(CareError.left, s, events);

  CareResult fail(CareError e) => CareResult.err(e, s, events);

  // 일일 카운터 (로컬 자정 리셋)
  final day = localDayOf(now, cfg.tzOffsetMinutes);
  if (s.dailyDay != day) {
    s = s.copyWith(dailyDay: day, playCount: 0, medicineCount: 0);
  }

  final k = action.kind;
  if (k != CareKind.sleep && k != CareKind.wake && s.asleep) {
    return fail(CareError.asleep);
  }
  final extra = <SimEvent>[];

  switch (k) {
    case CareKind.feed:
    case CareKind.snack:
      final isFeed = k == CareKind.feed;
      s = s.copyWith(
        hunger: _clamp4(s.hunger + (isFeed ? 2 : 1)),
        poopQueue: _insertSorted(s.poopQueue, now + (isFeed ? 120 : 180)),
      );
    case CareKind.play:
    case CareKind.minigame:
      s = s.copyWith(
        happiness: _clamp4(
          s.happiness + (k == CareKind.play ? 1 : action.minigameGain),
        ),
        fatigue: _clamp4(s.fatigue + 1),
        playCount: s.playCount + 1,
      );
    case CareKind.cleanPoop:
      s = s.copyWith(poop: 0);
    case CareKind.sleep:
      if (s.asleep) return fail(CareError.alreadySleeping);
      if (s.fatigue == 0) return fail(CareError.alreadyRested);
      s = s.copyWith(
        sleeping: true,
        asleep: true,
        awakeUntil: null,
        sleepAcc: 0,
      );
      extra.add(SimEvent(SimEventKind.fellAsleep, now));
    case CareKind.medicine:
      if (!s.sick) return fail(CareError.notSick);
      if (s.medicineCount >= 2) return fail(CareError.dailyLimit);
      s = s.copyWith(
        sick: false,
        sickSince: null,
        medicineCount: s.medicineCount + 1,
      );
    case CareKind.wake:
      if (!s.asleep) return fail(CareError.notAsleep);
      s = s.copyWith(
        sleeping: false,
        asleep: false,
        // 취침 시간대 중 수동 기상: 시간대가 끝날 때까지 정상 속도
        awakeUntil: inSleepWindow(cfg, now) ? sleepWindowEnd(cfg, now) : null,
      );
      extra.add(SimEvent(SimEventKind.woke, now));
  }

  // 아픔 진입 타이머 재동기화 (스탯이 바뀌었거나 약으로 리셋된 경우)
  s = s.copyWith(
    hungerZeroSince: s.hunger == 0 ? (s.hungerZeroSince ?? now) : null,
    poop3Since: s.poop == kMaxPoop ? (s.poop3Since ?? now) : null,
  );
  if (k == CareKind.medicine) {
    s = s.copyWith(
      hungerZeroSince: s.hunger == 0 ? now : null,
      poop3Since: s.poop == kMaxPoop ? now : null,
    );
  }
  return CareResult.ok(s, [...events, ...extra]);
}
