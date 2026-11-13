// FR-9 복귀 요약 순수 함수 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:petory/domain/domain.dart';

const cfg = Settings(tzOffsetMinutes: 0);
const t0 = 12 * 60; // 로컬 12:00 (취침 시간대 밖)

PetState newborn() =>
    PetState.newborn(name: 'a', species: Species.eggA, birthAt: t0);

/// 이미 어린이 단계인 펫(몇 시간 안에는 진화가 없다).
PetState child() => PetState.newborn(
  name: 'a',
  species: Species.eggA,
  birthAt: t0 - 120,
).copyWith(stage: Stage.child, lastUpdatedAt: t0, lastSampleAt: t0);

AwaySummary summary(PetState before, int minutes) {
  final to = before.lastUpdatedAt + minutes;
  final (after, events) = simulate(before, cfg, to);
  return buildAwaySummary(before, after, events, nowMinute: to);
}

void main() {
  test('임계값 상수는 3시간이고 판정은 이상(>=)', () {
    expect(kAwayThresholdMinutes, 180);
    expect(isAwayLongEnough(179), isFalse);
    expect(isAwayLongEnough(180), isTrue);
    expect(isAwayLongEnough(0), isFalse);
    expect(isAwayLongEnough(-60), isFalse); // 시계 역행
    expect(isAwayLongEnough(10, threshold: 10), isTrue);
  });

  test('스탯 변화량: 3시간 뒤 배고픔 -1, 이후 값과 경과 시간', () {
    final b = child();
    final s = summary(b, 200);
    expect(s.elapsedMinutes, 200);
    expect(s.hungerDelta, -1);
    expect(s.hungerAfter, 3);
    expect(s.happinessDelta, 0);
    expect(s.sickChange, SickChange.none);
    expect(s.sickAfter, isFalse);
    expect(s.left, isFalse);
    expect(s.hasEvolution, isFalse);
  });

  test('피로·똥 증가와 행복 감소가 부호대로 나온다', () {
    final b = child();
    final s = summary(b, 600);
    expect(s.hungerDelta, lessThan(0));
    expect(s.happinessDelta, lessThan(0));
    expect(s.fatigueDelta, greaterThanOrEqualTo(0));
    expect(s.poopDelta, greaterThanOrEqualTo(0));
    expect(s.hungerAfter, b.hunger + s.hungerDelta);
    expect(s.poopAfter, b.poop + s.poopDelta);
  });

  test('아픔 시작이 감지된다', () {
    final b = child();
    final s = summary(b, 20 * 60);
    expect(s.sickAfter, isTrue);
    expect(s.sickChange, SickChange.started);
    expect(s.left, isFalse);
  });

  test('이미 아프던 상태가 계속되면 변화 없음 + sickAfter true', () {
    final (sick, _) = simulate(child(), cfg, t0 + 20 * 60);
    expect(sick.sick, isTrue);
    final s = summary(sick, 3 * 60);
    expect(s.sickChange, SickChange.none);
    expect(s.sickAfter, isTrue);
  });

  test('아픔 해소를 recovered 로 표시한다', () {
    final (sick, _) = simulate(child(), cfg, t0 + 20 * 60);
    final s = buildAwaySummary(sick, sick.copyWith(sick: false), const []);
    expect(s.sickChange, SickChange.recovered);
  });

  test('진화 이벤트가 시간순으로 포함되고 다른 이벤트는 제외된다', () {
    final b = newborn();
    final s = summary(b, 1500); // 25시간: child(1h), teen(24h)
    expect(s.evolutions.map((e) => e.stage), [Stage.child, Stage.teen]);
    expect(s.evolutions.map((e) => e.kind).toSet(), {
      SimEventKind.stageChanged,
    });
    expect(s.hasEvolution, isTrue);
  });

  test('성체 형태 확정도 진화로 포함된다', () {
    final s = buildAwaySummary(newborn(), newborn(), const [
      SimEvent(SimEventKind.gotSick, 5),
      SimEvent(SimEventKind.adultFormDecided, 9, tier: Tier.normal),
      SimEvent(SimEventKind.stageChanged, 3, stage: Stage.adult),
    ]);
    expect(s.evolutions.map((e) => e.at), [3, 9]);
  });

  test('떠난 경우: left 와 경과는 nowMinute 기준, 마지막 상태 유지', () {
    final b = newborn();
    final now = t0 + 3 * 1440;
    final (after, events) = simulate(b, cfg, now);
    expect(after.left, isTrue);
    final s = buildAwaySummary(b, after, events, nowMinute: now);
    expect(s.left, isTrue);
    expect(s.elapsedMinutes, 3 * 1440);
    expect(s.sickAfter, isTrue);
    expect(s.hungerAfter, after.hunger);
  });

  test('nowMinute 없으면 갱신 시각 차이로 경과를 계산한다', () {
    final b = newborn();
    final (after, ev) = simulate(b, cfg, t0 + 300);
    expect(buildAwaySummary(b, after, ev).elapsedMinutes, 300);
  });
}
