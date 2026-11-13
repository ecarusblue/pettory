import 'package:flutter_test/flutter_test.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/domain/domain.dart';

const cfg = Settings(sleepStart: 23 * 60, sleepEnd: 7 * 60, tzOffsetMinutes: 0);
// 로컬 정오(취침 시간대 밖)에 부화한 펫
PetState born([int at = 12 * 60]) =>
    PetState.newborn(name: 'a', species: Species.eggA, birthAt: at);

void main() {
  test('3시간 경과 시 배고픔 4→3, 6시간 → 2', () {
    final b = born();
    expect(simulate(b, cfg, b.birthAt + 180).$1.hunger, 3);
    expect(simulate(b, cfg, b.birthAt + 360).$1.hunger, 2);
  });

  test('분할 불변성과 결정성', () {
    final b = born();
    final direct = simulate(b, cfg, b.birthAt + 5000);
    final half = simulate(b, cfg, b.birthAt + 1234);
    final split = simulate(half.$1, cfg, b.birthAt + 5000);
    expect(split.$1, direct.$1);
    expect([...half.$2, ...split.$2], direct.$2);
    expect(simulate(b, cfg, b.birthAt + 5000).$1, direct.$1);
  });

  test('밥 후 120분 뒤 똥, 아픔 진입, 약', () {
    final b = born();
    final r = applyCare(b, cfg, CareAction.feed, b.birthAt);
    final s = r.state!;
    expect(simulate(s, cfg, b.birthAt + 119).$1.poop, 0);
    expect(simulate(s, cfg, b.birthAt + 120).$1.poop, 1);
    expect(
      applyCare(b, cfg, CareAction.medicine, b.birthAt).error,
      CareError.notSick,
    );
  });

  test('방치하면 아파지고 24시간 뒤 떠남, 이후 틱 중단', () {
    final b = born();
    final (s, ev) = simulate(b, cfg, b.birthAt + 30 * 1440);
    expect(s.left, isTrue);
    expect(ev.where((e) => e.kind == SimEventKind.left).length, 1);
    expect(s.lastUpdatedAt, s.leftAt);
  });

  test('성장 단계 경계와 성체 확정', () {
    final b = born();
    expect(simulate(b, cfg, b.birthAt + 59).$1.stage, Stage.baby);
    expect(simulate(b, cfg, b.birthAt + 60).$1.stage, Stage.child);
    expect(decideAdultTier(69.99), Tier.normal);
    expect(decideAdultTier(70), Tier.excellent);
    expect(decideAdultTier(39.99), Tier.neglect);
    expect(decideAdultTier(40), Tier.normal);
  });

  test('checkClock', () {
    expect(checkClock(100, 50), 100);
    expect(checkClock(100, 400, serverNow: 339), 339);
    expect(checkClock(100, 400, serverNow: 340), 400);
  });

  test('JSON 왕복', () {
    final b = born();
    final (s, _) = simulate(b, cfg, b.birthAt + 3000);
    expect(PetState.fromJson(s.toJson()), s);
    final save = GameSave(pet: s, settings: cfg);
    expect(GameSave.fromJson(save.toJson()).pet, s);
  });

  test('알 부화 소급', () {
    const e = Egg(species: Species.eggA, name: 'a', startedAt: 100);
    expect(hatchMinute(e, 102), isNull);
    expect(hatchMinute(e, 5000), 103);
  });

  test('취침 시간대 감소 절반, 수면/기상 이벤트, 알림 이동', () {
    // 로컬 22:00에 부화 → 23:00~07:00 수면 시간대로 진입
    final b = born(22 * 60);
    final (s, ev) = simulate(b, cfg, b.birthAt + 60 + 180);
    expect(ev.where((e) => e.kind == SimEventKind.fellAsleep).length, 1);
    expect(s.asleep, isTrue);
    // 60분 정상(120) + 180분 절반(180) = 300 < 360 → 아직 4
    expect(s.hunger, 4);
    final list = nextNotifications(born(), cfg, 12 * 60);
    for (final n in list) {
      expect(inSleepWindow(cfg, n.fireAt), isFalse);
    }
    expect(list.any((n) => n.type == NotifyType.hunger), isTrue);
  });
}
