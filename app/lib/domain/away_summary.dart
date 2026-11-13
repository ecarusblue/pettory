import 'types.dart';

/// 복귀 안내 화면(FR-9)을 띄우는 최소 미접속 시간(분). 이 값 이상이면 표시한다.
const int kAwayThresholdMinutes = 180;

/// 아픔 상태의 변화.
enum SickChange {
  /// 변화 없음 (계속 건강하거나 계속 아픔: [AwaySummary.sickAfter] 로 구분).
  none,

  /// 미접속 중 아프기 시작함.
  started,

  /// 아프던 상태에서 건강해짐 (정상 흐름에서는 드묾).
  recovered,
}

/// 자리를 비운 동안의 변화 요약. 화면과 무관한 순수 값 객체.
class AwaySummary {
  const AwaySummary({
    required this.elapsedMinutes,
    required this.hungerDelta,
    required this.happinessDelta,
    required this.fatigueDelta,
    required this.poopDelta,
    required this.sickChange,
    required this.sickAfter,
    required this.hungerAfter,
    required this.happinessAfter,
    required this.fatigueAfter,
    required this.poopAfter,
    required this.evolutions,
    required this.left,
  });

  /// 마지막 접속(마지막 갱신)부터 이번 갱신까지 경과(분).
  final int elapsedMinutes;

  /// 변화량 = 이후 - 이전 (배고픔·행복은 보통 음수, 피로·똥은 보통 양수).
  final int hungerDelta;
  final int happinessDelta;
  final int fatigueDelta;
  final int poopDelta;

  final SickChange sickChange;
  final bool sickAfter;

  /// 이후 값 (떠난 경우 떠난 시점의 마지막 상태).
  final int hungerAfter;
  final int happinessAfter;
  final int fatigueAfter;
  final int poopAfter;

  /// 그 사이 발생한 진화 이벤트(stageChanged, adultFormDecided), 시간순.
  final List<SimEvent> evolutions;

  /// 그 사이 떠났는가.
  final bool left;

  bool get hasEvolution => evolutions.isNotEmpty;
}

/// 임계값 이상 비웠는가. 시계 역행/0 은 항상 false.
bool isAwayLongEnough(
  int elapsedMinutes, {
  int threshold = kAwayThresholdMinutes,
}) => elapsedMinutes > 0 && elapsedMinutes >= threshold;

/// 시뮬레이션 직전 [before] 와 직후 [after], 그 사이 [events] 로 요약을 만든다.
///
/// [nowMinute] 를 주면 경과를 그 시각까지로 센다(떠난 경우 갱신 시각이 떠난 시점에 멈추므로).
/// 순수 함수. 표시 여부(임계값)는 [isAwayLongEnough] 로 따로 판단한다.
AwaySummary buildAwaySummary(
  PetState before,
  PetState after,
  List<SimEvent> events, {
  int? nowMinute,
}) {
  final sick = before.sick == after.sick
      ? SickChange.none
      : (after.sick ? SickChange.started : SickChange.recovered);
  final evo = [
    for (final e in events)
      if (e.kind == SimEventKind.stageChanged ||
          e.kind == SimEventKind.adultFormDecided)
        e,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return AwaySummary(
    elapsedMinutes: (nowMinute ?? after.lastUpdatedAt) - before.lastUpdatedAt,
    hungerDelta: after.hunger - before.hunger,
    happinessDelta: after.happiness - before.happiness,
    fatigueDelta: after.fatigue - before.fatigue,
    poopDelta: after.poop - before.poop,
    sickChange: sick,
    sickAfter: after.sick,
    hungerAfter: after.hunger,
    happinessAfter: after.happiness,
    fatigueAfter: after.fatigue,
    poopAfter: after.poop,
    evolutions: evo,
    left: after.left,
  );
}
