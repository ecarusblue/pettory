// 설계서 9장 단위 테스트 20개 + 분할 불변성 속성 기반 테스트 (QA).
// 기존 domain_smoke_test.dart 는 건드리지 않고, 빠진 항목을 여기서 보강한다.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petory/domain/domain.dart';

/// 로컬 자정(tz 0 기준) 에 해당하는 UTC epoch 분. 2026년경.
const int day0 = 1440 * 20000;

const Settings noSleep = Settings(
  sleepStart: 0,
  sleepEnd: 0,
  tzOffsetMinutes: 0,
);
const Settings night = Settings(
  sleepStart: 23 * 60,
  sleepEnd: 7 * 60,
  tzOffsetMinutes: 0,
);

PetState born(int at) =>
    PetState.newborn(name: 't', species: Species.eggA, birthAt: at);
PetState at(PetState s, Settings c, int t) => simulate(s, c, t).$1;

/// 점심(12:00, 취침 시간대 밖)에 부화.
final int noon = day0 + 12 * 60;

/// 일정 간격으로 돌봄을 계속해 7일 이상 살아남게 하는 도우미.
PetState live(
  PetState s,
  Settings c,
  int until, {
  int step = 60,
  bool minimal = false,
}) {
  var cur = s;
  for (var t = s.lastUpdatedAt + step; t <= until; t += step) {
    cur = simulate(cur, c, t).$1;
    if (cur.left) return cur;
    PetState? tryDo(CareAction a) {
      final r = applyCare(cur, c, a, t);
      return r.ok ? r.state : null;
    }

    if (cur.asleep) continue;
    if (cur.sick) cur = tryDo(CareAction.medicine) ?? cur;
    if (minimal) {
      if (cur.hunger <= 1) cur = tryDo(CareAction.feed) ?? cur;
      if (cur.poop >= 3) cur = tryDo(CareAction.cleanPoop) ?? cur;
    } else {
      if (cur.hunger <= 2) cur = tryDo(CareAction.feed) ?? cur;
      if (cur.poop >= 1) cur = tryDo(CareAction.cleanPoop) ?? cur;
      if (cur.happiness <= 2) cur = tryDo(CareAction.play) ?? cur;
      if (cur.fatigue >= 3) cur = tryDo(CareAction.sleep) ?? cur;
    }
  }
  return simulate(cur, c, until).$1;
}

void main() {
  group('설계서 9장 - 시간 경과 계산 (1~4)', () {
    test('1. 3시간 hunger 4→3, 6시간 →2 (경계 179/180 포함)', () {
      final b = born(noon);
      expect(at(b, noSleep, noon + 179).hunger, 4);
      expect(at(b, noSleep, noon + 180).hunger, 3);
      expect(at(b, noSleep, noon + 359).hunger, 3);
      expect(at(b, noSleep, noon + 360).hunger, 2);
      // 행복은 240분당 -1
      expect(at(b, noSleep, noon + 239).happiness, 4);
      expect(at(b, noSleep, noon + 240).happiness, 3);
    });

    test('2. 취침 시간대에는 감소가 절반: 같은 3시간에 hunger 변화 없음', () {
      final b = born(day0 + 23 * 60); // 23:00 부화 → 7시간 내내 취침 시간대
      expect(at(b, night, b.birthAt + 180).hunger, 4);
      expect(at(b, night, b.birthAt + 359).hunger, 4);
      expect(at(b, night, b.birthAt + 360).hunger, 3); // 절반 속도: 360분에 -1
      // 낮이면 같은 3시간에 -1
      expect(at(born(noon), night, noon + 180).hunger, 3);
    });

    test('3. 22:00~02:00 경계 걸침에서 누산기가 연속 (손계산과 일치)', () {
      const c = Settings(
        sleepStart: 22 * 60,
        sleepEnd: 2 * 60,
        tzOffsetMinutes: 0,
      );
      final b = born(day0 + 21 * 60); // 21:00 부화
      // 21:01~21:59 깨어 있음 59틱×2=118, 22:00~01:59 취침 240틱×1=240 → 358, 02:00 틱에서 360 도달
      expect(at(b, c, b.birthAt + 299).hunger, 4);
      expect(at(b, c, b.birthAt + 300).hunger, 3);
      // 경계 앞뒤에서 쪼개도 누산기가 이어진다
      for (final split in [59, 60, 61, 180, 299, 300, 301]) {
        final a = at(at(b, c, b.birthAt + split), c, b.birthAt + 600);
        expect(a, at(b, c, b.birthAt + 600), reason: 'split=$split');
      }
    });

    test('4. 30일 미접속: 스탯이 0에서 멈추고(음수 없음) 떠난 뒤 더 진행하지 않음', () {
      final b = born(noon);
      final (s, ev) = simulate(b, night, b.birthAt + 30 * 1440);
      expect(s.hunger, 0);
      expect(s.happiness, 0);
      expect(s.fatigue, inInclusiveRange(0, 4));
      expect(s.left, isTrue);
      expect(s.lastUpdatedAt, s.leftAt);
      expect(ev.where((e) => e.kind == SimEventKind.left), hasLength(1));
      // 30일을 훨씬 넘겨도 결과 동일 (상한 경로)
      final far = simulate(b, night, b.birthAt + 45 * 1440);
      expect(far.$1, s);
      // 이미 떠난 상태에서 더 호출해도 변화 없음
      expect(simulate(s, night, s.lastUpdatedAt + 100000).$1, s);
    });
  });

  group('설계서 9장 - 똥·건강 (5~8)', () {
    test('5. 밥 후 120분에 poop +1, 3개 이후 무시', () {
      final b = born(noon);
      var s = b;
      for (var i = 0; i < 4; i++) {
        s = applyCare(s, noSleep, CareAction.feed, noon).state!; // 큐에 4건
      }
      expect(s.poopQueue, hasLength(4));
      expect(at(s, noSleep, noon + 119).poop, 0);
      final (s2, ev) = simulate(s, noSleep, noon + 120);
      expect(s2.poop, 3);
      expect(ev.where((e) => e.kind == SimEventKind.poopSpawned), hasLength(3));
      // 4번째 예약은 무시되고 사라진다: 치운 뒤 다시 생기지 않음
      final cleaned = applyCare(
        s2,
        noSleep,
        CareAction.cleanPoop,
        noon + 121,
      ).state!;
      expect(cleaned.poopQueue, isEmpty);
      expect(at(cleaned, noSleep, noon + 300).poop, 0);
      // 간식은 180분
      final sn = applyCare(b, noSleep, CareAction.snack, noon).state!;
      expect(at(sn, noSleep, noon + 179).poop, 0);
      expect(at(sn, noSleep, noon + 180).poop, 1);
    });

    test('6. hunger 0이 119분 → 정상, 120분 → 아픔', () {
      final b = born(noon);
      // hunger 4→0 은 720분(4×180)에 도달, 이후 120분
      expect(at(b, noSleep, noon + 720).hunger, 0);
      expect(at(b, noSleep, noon + 838).sick, isFalse);
      expect(at(b, noSleep, noon + 839).sick, isFalse); // 0 지속 119분
      final (s, ev) = simulate(b, noSleep, noon + 840); // 120분
      expect(s.sick, isTrue);
      expect(s.sickSince, noon + 840);
      expect(
        ev.where((e) => e.kind == SimEventKind.gotSick).single.at,
        noon + 840,
      );
    });

    test('7. poop 3이 120분 지속 → 아픔, 도중에 치우면 타이머 리셋', () {
      final b = born(noon);
      var s = b;
      for (var i = 0; i < 3; i++) {
        s = applyCare(s, noSleep, CareAction.feed, noon).state!;
      }
      expect(at(s, noSleep, noon + 120).poop, 3);
      expect(at(s, noSleep, noon + 239).sick, isFalse);
      expect(at(s, noSleep, noon + 240).sick, isTrue);

      // 200분에 치우고, 다시 3개를 쌓으면 타이머가 새로 시작
      var r = applyCare(s, noSleep, CareAction.cleanPoop, noon + 200).state!;
      expect(r.sick, isFalse);
      expect(r.poop3Since, isNull);
      for (var i = 0; i < 3; i++) {
        r = applyCare(r, noSleep, CareAction.feed, noon + 200).state!;
      }
      expect(at(r, noSleep, noon + 320).poop, 3);
      expect(at(r, noSleep, noon + 439).sick, isFalse); // 320+119
      expect(at(r, noSleep, noon + 440).sick, isTrue);
    });

    test('8. 약: 아플 때만 성공, 일일 3번째는 거부, 다음 날 리셋', () {
      final b = born(noon);
      expect(
        applyCare(b, noSleep, CareAction.medicine, noon).error,
        CareError.notSick,
      );
      var s = b;
      for (var i = 0; i < 2; i++) {
        s = s.copyWith(sick: true, sickSince: noon);
        final r = applyCare(s, noSleep, CareAction.medicine, noon);
        expect(r.ok, isTrue, reason: '${i + 1}번째');
        s = r.state!;
        expect(s.sick, isFalse);
      }
      s = s.copyWith(sick: true, sickSince: noon);
      expect(
        applyCare(s, noSleep, CareAction.medicine, noon).error,
        CareError.dailyLimit,
      );
      // 로컬 자정이 지나면 다시 가능 (day0 + 1440 = 다음 날 0시)
      final next = day0 + 1440 + 60;
      final s2 = at(s.copyWith(sickSince: next - 10), noSleep, next);
      expect(applyCare(s2, noSleep, CareAction.medicine, next).ok, isTrue);
    });

    test('8b. 약 일일 한도의 날짜 경계는 tz 오프셋 기준(KST 자정)', () {
      const kst = Settings(sleepStart: 0, sleepEnd: 0, tzOffsetMinutes: 540);
      // KST 23:50 = UTC 14:50
      final t1 = day0 + 14 * 60 + 50;
      var s = at(born(t1 - 5), kst, t1);
      for (var i = 0; i < 2; i++) {
        s = applyCare(
          s.copyWith(sick: true, sickSince: t1),
          kst,
          CareAction.medicine,
          t1,
        ).state!;
      }
      s = s.copyWith(sick: true, sickSince: t1);
      expect(
        applyCare(s, kst, CareAction.medicine, t1).error,
        CareError.dailyLimit,
      );
      // 20분 뒤 KST 00:10 (UTC로는 같은 날 15:10) → 새 날
      final t2 = t1 + 20;
      final s2 = at(s, kst, t2).copyWith(sick: true, sickSince: t2);
      expect(applyCare(s2, kst, CareAction.medicine, t2).ok, isTrue);
    });

    test('8c. 놀아주기 하루 5회 한도(미니게임 합산), 자정에 리셋', () {
      var s = at(born(day0 + 23 * 60 - 120), noSleep, day0 + 23 * 60);
      for (var i = 0; i < 5; i++) {
        final r = applyCare(
          s,
          noSleep,
          i.isEven ? CareAction.play : CareAction.minigame(2),
          day0 + 23 * 60,
        );
        expect(r.ok, isTrue, reason: 'play ${i + 1}');
        s = r.state!;
      }
      expect(s.playCount, 5);
      expect(
        applyCare(s, noSleep, CareAction.play, day0 + 23 * 60).error,
        CareError.dailyLimit,
      );
      expect(
        applyCare(s, noSleep, CareAction.minigame(1), day0 + 23 * 60).error,
        CareError.dailyLimit,
      );
      final t2 = day0 + 1440 + 5;
      expect(
        applyCare(at(s, noSleep, t2), noSleep, CareAction.play, t2).ok,
        isTrue,
      );
    });

    test('8d. 미니게임 점수 구간 행복 +0/+1/+2 (범위 밖은 clamp), 피로 +1', () {
      var s = born(noon).copyWith(happiness: 0);
      for (final (gain, want) in [(0, 0), (1, 1), (2, 2), (5, 2), (-3, 0)]) {
        final r = applyCare(
          s.copyWith(happiness: 0, fatigue: 0, playCount: 0),
          noSleep,
          CareAction.minigame(gain),
          noon,
        );
        expect(r.state!.happiness, want, reason: 'gain=$gain');
        expect(r.state!.fatigue, 1);
      }
    });
  });

  group('설계서 9장 - 피로·수면 (9~11)', () {
    test('9. 깨어 있으면 4시간마다 fatigue +1, 상한 4', () {
      final b = born(noon);
      expect(at(b, noSleep, noon + 239).fatigue, 0);
      expect(at(b, noSleep, noon + 240).fatigue, 1);
      expect(at(b, noSleep, noon + 480).fatigue, 2);
      expect(at(b, noSleep, noon + 960).fatigue, 4);
      expect(at(b, noSleep, noon + 1200).fatigue, 4);
    });

    test('10. 수동 수면 중 60분마다 -1, 0에서 자동 기상', () {
      var s = at(born(noon), noSleep, noon + 10).copyWith(fatigue: 2);
      final r = applyCare(s, noSleep, CareAction.sleep, noon + 10);
      expect(r.ok, isTrue);
      s = r.state!;
      expect(s.asleep, isTrue);
      final t = noon + 10;
      expect(at(s, noSleep, t + 59).fatigue, 2);
      expect(at(s, noSleep, t + 60).fatigue, 1);
      expect(at(s, noSleep, t + 119).sleeping, isTrue);
      final (w, ev) = simulate(s, noSleep, t + 120);
      expect(w.fatigue, 0);
      expect(w.sleeping, isFalse);
      expect(w.asleep, isFalse);
      expect(ev.where((e) => e.kind == SimEventKind.woke).single.at, t + 120);
      // 깬 뒤에는 다시 피로가 쌓임
      expect(at(w, noSleep, t + 120 + 240).fatigue, 1);
    });

    test('10b. 재우기는 피로 0이면 거부, 이미 자는 중이면 거부', () {
      final s = born(noon);
      expect(
        applyCare(s, noSleep, CareAction.sleep, noon).error,
        CareError.alreadyRested,
      );
      final tired = s.copyWith(fatigue: 3);
      final sl = applyCare(tired, noSleep, CareAction.sleep, noon).state!;
      expect(
        applyCare(sl, noSleep, CareAction.sleep, noon).error,
        CareError.alreadySleeping,
      );
      expect(
        applyCare(s, noSleep, CareAction.wake, noon).error,
        CareError.notAsleep,
      );
    });

    test('10c. 취침 시간대 중 수동 기상하면 시간대 종료까지 정상 속도', () {
      // 23:00 부화 → 취침 시간대. 01:00에 깨움.
      final b = born(day0 + 23 * 60);
      final t = day0 + 25 * 60; // 다음 날 01:00
      final s = at(b, night, t);
      expect(s.asleep, isTrue);
      final w = applyCare(s, night, CareAction.wake, t).state!;
      expect(w.asleep, isFalse);
      expect(w.awakeUntil, day0 + 1440 + 7 * 60);
      // 이후 한 시간 동안은 깨어 있는 상태(감소율 1.0) → 피로 누산기 증가
      final w2 = at(w, night, t + 60);
      expect(w2.asleep, isFalse);
      expect(w2.fatigueAcc, greaterThan(0));
      // 시간대가 끝나면 awakeUntil 해제
      final w3 = at(w, night, day0 + 1440 + 7 * 60);
      expect(w3.awakeUntil, isNull);
    });

    test('11. 수면 중 밥/간식/놀기/똥/약은 거부(asleep), 깨우기/재우기만 가능', () {
      final s = applyCare(
        born(noon).copyWith(fatigue: 3),
        noSleep,
        CareAction.sleep,
        noon,
      ).state!;
      for (final a in [
        CareAction.feed,
        CareAction.snack,
        CareAction.play,
        CareAction.cleanPoop,
        CareAction.medicine,
        CareAction.minigame(1),
      ]) {
        expect(
          applyCare(s, noSleep, a, noon).error,
          CareError.asleep,
          reason: a.kind.name,
        );
      }
      // 취침 시간대(자동 수면)에도 동일
      final n = at(born(day0 + 23 * 60), night, day0 + 24 * 60);
      expect(
        applyCare(n, night, CareAction.feed, day0 + 24 * 60).error,
        CareError.asleep,
      );
    });
  });

  group('설계서 9장 - 성장·분기 (12~15)', () {
    test('12. 59분 baby, 60분 child, 1일 teen, 3일 adult (경계 -1/0)', () {
      final b = born(noon);
      expect(at(b, noSleep, noon + 59).stage, Stage.baby);
      expect(at(b, noSleep, noon + 60).stage, Stage.child);
      expect(at(b, noSleep, noon + 1439).stage, Stage.child);
      expect(at(b, noSleep, noon + 1440).stage, Stage.teen);
      // 3일 adult 는 돌봄이 있어야 도달 가능
      final alive = live(b, night, noon + 4319);
      expect(alive.left, isFalse);
      expect(alive.stage, Stage.teen);
      final (a, ev) = simulate(alive, night, noon + 4320);
      expect(a.stage, Stage.adult);
      expect(
        ev.where((e) => e.kind == SimEventKind.stageChanged).single,
        SimEvent(SimEventKind.stageChanged, noon + 4320, stage: Stage.adult),
      );
    });

    test('13. 7일 시점 careScore 70/40 경계값이 성체 등급으로 확정', () {
      PetState atSeven(int sum8, int count) => PetState(
        name: 't',
        species: Species.eggA,
        stage: Stage.adult,
        birthAt: noon,
        lastUpdatedAt: noon + 7 * 1440 - 1,
        lastSampleAt: noon + 7 * 1440 - 10,
        careSampleSum8: sum8,
        careSampleCount: count,
      );
      Tier? tierFor(double score) {
        final (s, ev) = simulate(
          atSeven((score * 800).round(), 100),
          noSleep,
          noon + 7 * 1440,
        );
        final e = ev.where((e) => e.kind == SimEventKind.adultFormDecided);
        expect(e, hasLength(1), reason: 'score=$score');
        expect(s.adultTier, e.single.tier);
        return s.adultTier;
      }

      expect(tierFor(70), Tier.excellent);
      expect(tierFor(69.99), Tier.normal);
      expect(tierFor(40), Tier.normal);
      expect(tierFor(39.99), Tier.neglect);
      expect(tierFor(100), Tier.excellent);
      expect(tierFor(0), Tier.neglect);
      // 확정은 한 번만
      final (s, _) = simulate(atSeven(56000, 100), noSleep, noon + 7 * 1440);
      expect(
        simulate(
          s,
          noSleep,
          noon + 8 * 1440,
        ).$2.where((e) => e.kind == SimEventKind.adultFormDecided),
        isEmpty,
      );
    });

    test('13b. 샘플이 하나도 없으면 방치형(0점)', () {
      final s = PetState(
        name: 't',
        species: Species.eggA,
        stage: Stage.adult,
        birthAt: noon,
        lastUpdatedAt: noon + 7 * 1440 - 1,
        lastSampleAt: noon + 7 * 1440 - 10,
      );
      expect(simulate(s, noSleep, noon + 7 * 1440).$1.adultTier, Tier.neglect);
      expect(careScoreOf(s), 0);
    });

    test('13c. 상태 점수 식(PRD): 만점 100, 아픔 ×0.5, 취침 없음 샘플 1건 검증', () {
      // 부화 직후 hunger4 happy4 poop0 fatigue0 → 100점. 60분 시점 샘플은 약간 감소 전.
      final (s, _) = simulate(born(noon), noSleep, noon + 60);
      expect(s.careSampleCount, 1);
      expect(careScoreOf(s), closeTo(100, 1e-9));
      // 알려진 중간값: hunger 2, happy 2, poop 1, fatigue 2, 건강 → 100*(.35*.5+.35*.5+.15*(2/3)+.15*.5)=
      const expected =
          100 * (0.35 * 0.5 + 0.35 * 0.5 + 0.15 * (2 / 3) + 0.15 * 0.5);
      final custom = born(noon).copyWith(
        hunger: 2,
        happiness: 2,
        poop: 1,
        fatigue: 2,
        lastSampleAt: noon,
      );
      // 점수는 수명 중 변하므로 상태를 고정하기 위해 60틱 안에 감소가 없는 누산기 0 상태에서 샘플
      final r = simulate(custom, noSleep, noon + 60).$1;
      expect(careScoreOf(r), closeTo(expected, 1e-9));
      // 아픔이면 절반
      final sick = custom.copyWith(sick: true, sickSince: noon);
      expect(
        careScoreOf(simulate(sick, noSleep, noon + 60).$1),
        closeTo(expected / 2, 1e-9),
      );
    });

    test('14. 방치(최소 돌봄) 7일: 점수가 낮고 취침 시간대 샘플은 제외', () {
      final start = born(noon);
      final s = live(start, night, noon + 7 * 1440 + 30, minimal: true);
      expect(s.left, isFalse, reason: '최소 돌봄으로 7일 생존해야 한다');
      expect(s.adultTier, isNotNull);
      expect(careScoreOf(s), lessThan(70));
      // 샘플 개수 = 부화 후 매 60분 중 7일 미만이고 취침 시간대가 아닌 시각의 수
      var expected = 0;
      for (var age = 60; age < 7 * 1440; age += 60) {
        if (!inSleepWindow(night, noon + age)) expected++;
      }
      expect(s.careSampleCount, expected);
      // 취침 시간대가 없으면 167개
      final sNo = live(start, noSleep, noon + 7 * 1440 + 30, minimal: true);
      expect(sNo.left, isFalse);
      expect(sNo.careSampleCount, 167);
      expect(expected, lessThan(167));
    });

    test('14b. 좋은 돌봄 7일은 최소 돌봄보다 점수가 높다', () {
      final good = live(born(noon), night, noon + 7 * 1440 + 30);
      final minimal = live(
        born(noon),
        night,
        noon + 7 * 1440 + 30,
        minimal: true,
      );
      expect(good.left, isFalse);
      expect(careScoreOf(good), greaterThan(careScoreOf(minimal)));
    });

    test('15. 앱 종료 중 진화가 simulate 이벤트로 반환됨 (FR-6)', () {
      final b = born(noon);
      final (_, ev) = simulate(b, night, noon + 1500); // 25시간 미접속
      final stages = ev
          .where((e) => e.kind == SimEventKind.stageChanged)
          .toList();
      expect(stages.map((e) => e.stage), [Stage.child, Stage.teen]);
      expect(stages.map((e) => e.at), [noon + 60, noon + 1440]);
      // 성체: 3일 직전까지 돌본 뒤 비운 구간
      final alive = live(b, night, noon + 4200);
      final (_, ev2) = simulate(alive, night, noon + 4400);
      expect(
        ev2.where((e) => e.kind == SimEventKind.stageChanged).single.stage,
        Stage.adult,
      );
    });
  });

  group('설계서 9장 - 떠남 (16)', () {
    test('16. 아픔 1439분 → 생존, 1440분 → left, 이후 틱 중단', () {
      final b = born(noon);
      final sickAt = noon + 840;
      final s0 = at(b, noSleep, sickAt);
      expect(s0.sick, isTrue);
      expect(s0.sickSince, sickAt);
      final alive = simulate(b, noSleep, sickAt + 1439);
      expect(alive.$1.left, isFalse);
      expect(alive.$2.where((e) => e.kind == SimEventKind.left), isEmpty);
      final (gone, ev) = simulate(b, noSleep, sickAt + 1440);
      expect(gone.left, isTrue);
      expect(gone.leftAt, sickAt + 1440);
      expect(ev.last, SimEvent(SimEventKind.left, sickAt + 1440));
      // 훨씬 뒤까지 호출해도 lastUpdatedAt 이 떠난 시각에 고정
      final (later, ev2) = simulate(b, noSleep, sickAt + 1440 + 9999);
      expect(later, gone);
      expect(ev2, ev);
      expect(simulate(gone, noSleep, sickAt + 100000).$2, isEmpty);
    });

    test('16b. 약으로 아픔을 풀면 떠남 타이머가 리셋되고 다시 아픔 전까지 안전', () {
      final b = born(noon);
      final s = at(b, noSleep, noon + 840 + 1000); // 아픔 1000분
      final cured = applyCare(
        s,
        noSleep,
        CareAction.feed,
        noon + 1840,
      ).state!; // 밥으로 hunger>0
      final m = applyCare(
        cured,
        noSleep,
        CareAction.medicine,
        noon + 1840,
      ).state!;
      expect(m.sick, isFalse);
      expect(m.sickSince, isNull);
      // 옛 타이머(sickSince=840)였다면 noon+2280 에 이미 떠났을 시점. 리셋됐으므로 생존.
      expect(at(m, noSleep, noon + 1840 + 1000).left, isFalse);
    });
  });

  group('설계서 9장 - 무결성·알림 (17~19)', () {
    test('17. checkClock: 과거 → 경과 0, 미래 편차 61분 + 서버 시각 → 서버 기준', () {
      expect(checkClock(1000, 900), 1000);
      expect(checkClock(1000, 1000), 1000);
      expect(checkClock(1000, 2000, serverNow: 2000 - 61), 2000 - 61);
      expect(checkClock(1000, 2000, serverNow: 2000 - 60), 2000);
      expect(
        checkClock(1000, 2000, serverNow: 5000),
        2000,
      ); // 기기가 서버보다 느림 → 그대로
      expect(checkClock(1000, 2000), 2000); // 오프라인
    });

    test('18. 알림: 취침 시간대에 걸린 발송이 기상 + 30분으로 이동', () {
      // 17:00 부화: 배고픔 1 도달 시각이 05:01 (취침 시간대) → 07:30
      final b = born(day0 + 17 * 60);
      final list = nextNotifications(b, night, b.birthAt);
      final hungry = list.firstWhere((n) => n.type == NotifyType.hunger);
      expect(hungry.fireAt, day0 + 1440 + 7 * 60 + 30);
      for (final n in list) {
        expect(inSleepWindow(night, n.fireAt), isFalse, reason: n.toString());
      }
      // 취침 시간대가 없으면 원래 시각
      final raw = nextNotifications(
        b,
        noSleep,
        b.birthAt,
      ).firstWhere((n) => n.type == NotifyType.hunger);
      expect(raw.fireAt, day0 + 1440 + 2 * 60); // 취침 없이 2/틱: 540분 뒤 02:00
    });

    test('18b. 진화 임박은 단계 전환 10분 전, 이미 10분 이내면 now+1', () {
      final b = born(noon);
      final list = nextNotifications(b, noSleep, noon);
      expect(
        list.firstWhere((n) => n.type == NotifyType.evolve).fireAt,
        noon + 50,
      );
      final near = at(b, noSleep, noon + 55);
      expect(
        nextNotifications(
          near,
          noSleep,
          noon + 55,
        ).firstWhere((n) => n.type == NotifyType.evolve).fireAt,
        noon + 56,
      );
    });

    test('18c. 떠난 펫/알림 끔이면 빈 목록, 이미 아프면 아픔 경고 없음', () {
      final gone = at(born(noon), noSleep, noon + 5000);
      expect(gone.left, isTrue);
      expect(nextNotifications(gone, noSleep, noon + 5000), isEmpty);
      expect(
        nextNotifications(
          born(noon),
          noSleep.copyWith(notifyEnabled: false),
          noon,
        ),
        isEmpty,
      );
      final sick = at(born(noon), noSleep, noon + 900);
      expect(sick.sick, isTrue);
      expect(
        nextNotifications(
          sick,
          noSleep,
          noon + 900,
        ).where((n) => n.type == NotifyType.sick),
        isEmpty,
      );
    });

    test('18d. 예약 목록은 항상 now 이후, 시각순 정렬, 종류 중복 없음', () {
      final rng = Random(7);
      for (var i = 0; i < 50; i++) {
        final b = born(day0 + rng.nextInt(1440 * 3));
        final t = b.birthAt + rng.nextInt(1440);
        final list = nextNotifications(b, night, t);
        expect(list.map((n) => n.type).toSet().length, list.length);
        for (var k = 0; k < list.length; k++) {
          expect(list[k].fireAt, greaterThan(t));
          if (k > 0) {
            expect(list[k].fireAt, greaterThanOrEqualTo(list[k - 1].fireAt));
          }
        }
      }
    });

    test('19. 결정성: 같은 입력 두 번 호출 결과 동일(상태·이벤트)', () {
      final b = born(noon + 33);
      final a = simulate(b, night, b.birthAt + 9000);
      final c = simulate(b, night, b.birthAt + 9000);
      expect(c.$1, a.$1);
      expect(c.$2, a.$2);
    });
  });

  group('설계서 9장 20 - 분할 불변성 (속성 기반)', () {
    final settingsPool = <Settings>[
      night,
      noSleep,
      const Settings(
        sleepStart: 22 * 60,
        sleepEnd: 2 * 60,
        tzOffsetMinutes: -300,
      ),
      const Settings(
        sleepStart: 13 * 60,
        sleepEnd: 15 * 60,
        tzOffsetMinutes: 540,
      ),
      const Settings(
        sleepStart: 20 * 60,
        sleepEnd: 6 * 60,
        tzOffsetMinutes: -840,
      ),
      const Settings(
        sleepStart: 23 * 60 + 17,
        sleepEnd: 6 * 60 + 43,
        tzOffsetMinutes: 840,
      ),
      const Settings(
        sleepStart: 5 * 60,
        sleepEnd: 5 * 60,
        tzOffsetMinutes: 330,
      ),
      const Settings(sleepStart: 0, sleepEnd: 1439, tzOffsetMinutes: 345),
    ];

    /// 무작위 선행 돌봄(밥, 놀기, 재우기, 깨우기, 약 ...)을 적용한 상태를 만든다.
    PetState history(Random rng, Settings c, PetState s, int spanMinutes) {
      final actions = [
        CareAction.feed,
        CareAction.snack,
        CareAction.play,
        CareAction.cleanPoop,
        CareAction.sleep,
        CareAction.wake,
        CareAction.medicine,
        CareAction.minigame(2),
      ];
      var t = s.lastUpdatedAt;
      final end = t + spanMinutes;
      var cur = s;
      while (true) {
        t += 1 + rng.nextInt(max(2, spanMinutes ~/ 6));
        if (t > end) break;
        final r = applyCare(cur, c, actions[rng.nextInt(actions.length)], t);
        cur = r.state ?? cur;
        if (cur.left) break;
      }
      return cur;
    }

    test('무작위 시작 상태 × 무작위 분할 지점 (400 시나리오)', () {
      final rng = Random(20261113);
      for (var i = 0; i < 400; i++) {
        final c = settingsPool[rng.nextInt(settingsPool.length)];
        final birth = day0 + rng.nextInt(1440 * 4);
        var s = born(birth);
        if (rng.nextBool()) s = history(rng, c, s, rng.nextInt(1440 * 3) + 1);
        final span =
            [30, 200, 1500, 4000, 10080, 20000][rng.nextInt(6)] +
            rng.nextInt(500);
        final t2 = s.lastUpdatedAt + span;
        final direct = simulate(s, c, t2);
        final tag =
            'i=$i cfg=${c.toJson()} birth=$birth start=${s.lastUpdatedAt} span=$span';

        // 한 번 분할
        final t1 = s.lastUpdatedAt + rng.nextInt(span + 1);
        final first = simulate(s, c, t1);
        final second = simulate(first.$1, c, t2);
        expect(second.$1, direct.$1, reason: 'split1 t1=$t1 $tag');
        expect(
          [...first.$2, ...second.$2],
          direct.$2,
          reason: 'events t1=$t1 $tag',
        );

        // 여러 번 분할 (1~12분 간격 포함)
        var cur = s;
        final evs = <SimEvent>[];
        var t = s.lastUpdatedAt;
        while (t < t2) {
          t = min(t2, t + 1 + rng.nextInt(rng.nextBool() ? 12 : 2000));
          final r = simulate(cur, c, t);
          cur = r.$1;
          evs.addAll(r.$2);
        }
        expect(cur, direct.$1, reason: 'multi $tag');
        expect(evs, direct.$2, reason: 'multi-events $tag');

        // 직렬화 왕복을 끼워도 같다 (저장/재시작 시뮬레이션)
        final mid = PetState.fromJson(first.$1.toJson());
        expect(simulate(mid, c, t2).$1, direct.$1, reason: 'json-split $tag');
      }
    });

    test('이벤트 시각 ±1분과 취침 시간대 경계 ±1분에서 분할 (경계 집중)', () {
      final rng = Random(99);
      for (var i = 0; i < 40; i++) {
        final c = settingsPool[i % settingsPool.length];
        var s = born(day0 + rng.nextInt(1440 * 3));
        // 절반은 좋은 돌봄으로 7일 이상 생존, 나머지는 방치(떠남 경로)
        final alive = i.isEven;
        if (alive) s = live(s, c, s.birthAt + 2 * 1440, minimal: i % 4 == 0);
        if (s.left) continue;
        final horizon = s.lastUpdatedAt + (alive ? 6 * 1440 : 4000);
        final direct = simulate(s, c, horizon);

        final cuts = <int>{};
        for (final e in direct.$2) {
          for (final d in [-1, 0, 1]) {
            cuts.add(e.at + d);
          }
        }
        // 취침 시간대가 바뀌는 분 (진입/이탈) 전후
        var prev = inSleepWindow(c, s.lastUpdatedAt);
        for (var t = s.lastUpdatedAt + 1; t <= horizon; t++) {
          final cur = inSleepWindow(c, t);
          if (cur != prev) {
            for (final d in [-1, 0, 1]) {
              cuts.add(t + d);
            }
          }
          prev = cur;
        }
        for (final cut in cuts) {
          if (cut <= s.lastUpdatedAt || cut >= horizon) continue;
          final a = simulate(s, c, cut);
          final b = simulate(a.$1, c, horizon);
          expect(b.$1, direct.$1, reason: 'cut=$cut i=$i cfg=${c.toJson()}');
          expect([...a.$2, ...b.$2], direct.$2, reason: 'events cut=$cut i=$i');
        }
      }
    });

    test('떠남 직전/직후, 7일 경계, 30일 상한 경로', () {
      final b = born(noon);
      // 떠남: 아픔 840 + 1440 = 2280
      final leaveAt = noon + 2280;
      for (final cut in [
        leaveAt - 2,
        leaveAt - 1,
        leaveAt,
        leaveAt + 1,
        leaveAt + 500,
      ]) {
        for (final end in [leaveAt, leaveAt + 1, leaveAt + 40 * 1440]) {
          if (cut >= end) continue;
          final direct = simulate(b, night, end);
          final a = simulate(b, night, cut);
          final c = simulate(a.$1, night, end);
          expect(
            c.$1,
            direct.$1,
            reason: 'cut=${cut - noon} end=${end - noon}',
          );
          expect([...a.$2, ...c.$2], direct.$2, reason: 'events');
        }
      }
      // 7일 경계 (좋은 돌봄)
      final alive = live(b, night, noon + 7 * 1440 - 100);
      expect(alive.left, isFalse);
      for (final cut in [
        noon + 7 * 1440 - 1,
        noon + 7 * 1440,
        noon + 7 * 1440 + 1,
      ]) {
        for (final end in [noon + 7 * 1440 + 60, noon + 7 * 1440 + 600]) {
          final direct = simulate(alive, night, end);
          final a = simulate(alive, night, cut);
          final c = simulate(a.$1, night, end);
          expect(c.$1, direct.$1, reason: 'cut=${cut - noon}');
          expect([...a.$2, ...c.$2], direct.$2);
          expect(direct.$1.adultTier, isNotNull);
        }
      }
      // 30일 상한: 이미 떠난 펫을 10일→45일로 쪼개도 한 번에 45일과 같다
      final direct = simulate(b, night, noon + 45 * 1440);
      final mid = simulate(b, night, noon + 10 * 1440);
      expect(simulate(mid.$1, night, noon + 45 * 1440).$1, direct.$1);
    });

    test('applyCare 는 사전 simulate 여부와 무관 (호출부 규칙 보장)', () {
      final rng = Random(5);
      for (var i = 0; i < 150; i++) {
        final c = settingsPool[rng.nextInt(settingsPool.length)];
        var s = born(day0 + rng.nextInt(2000));
        s = history(rng, c, s, rng.nextInt(2000) + 1);
        final t = s.lastUpdatedAt + rng.nextInt(1500) + 1;
        final pre = simulate(s, c, t - rng.nextInt(t - s.lastUpdatedAt)).$1;
        for (final a in [
          CareAction.feed,
          CareAction.play,
          CareAction.medicine,
          CareAction.sleep,
          CareAction.wake,
          CareAction.cleanPoop,
        ]) {
          final direct = applyCare(s, c, a, t);
          final viaPre = applyCare(pre, c, a, t);
          expect(viaPre.error, direct.error, reason: 'i=$i ${a.kind}');
          expect(viaPre.state, direct.state, reason: 'i=$i ${a.kind}');
        }
      }
    });
  });

  group('기타 도메인 경계', () {
    test('toMinute <= lastUpdatedAt 이면 변화 없음(시계 역행 안전)', () {
      final b = born(noon);
      final s = at(b, night, noon + 500);
      expect(simulate(s, night, noon + 100).$1, s);
      expect(simulate(s, night, noon + 500).$2, isEmpty);
    });

    test('tz 음수에서 localMinuteOfDay/localDayOf/sleepWindowEnd', () {
      // UTC-5: UTC 03:00 = 로컬 전날 22:00
      final t = day0 + 3 * 60;
      expect(localMinuteOfDay(t, -300), 22 * 60);
      expect(localDayOf(t, -300), day0 ~/ 1440 - 1);
      const c = Settings(
        sleepStart: 22 * 60,
        sleepEnd: 7 * 60,
        tzOffsetMinutes: -300,
      );
      expect(inSleepWindow(c, t), isTrue);
      expect(sleepWindowEnd(c, t), day0 + 12 * 60); // 로컬 07:00 = UTC 12:00
      expect(inSleepWindow(c, sleepWindowEnd(c, t)), isFalse);
      expect(inSleepWindow(c, sleepWindowEnd(c, t) - 1), isTrue);
    });

    test('Settings/PetState/Egg JSON 왕복과 누락 필드 기본값', () {
      final s = at(born(noon), night, noon + 3333);
      expect(PetState.fromJson(s.toJson()), s);
      expect(Settings.fromJson(const {}), const Settings());
      expect(PetState.fromJson(const {'birthAt': 5}).hunger, 4);
    });

    test('알 부화: 10탭 시각 vs 3분 자동 중 빠른 쪽', () {
      var e = const Egg(species: Species.eggA, name: 'a', startedAt: 1000);
      for (var i = 0; i < 9; i++) {
        e = tapEggAt(e, 1000 + i % 2);
      }
      expect(hatchMinute(e, 1001), isNull);
      e = tapEggAt(e, 1002);
      expect(e.tenthTapAt, 1002);
      expect(hatchMinute(e, 1002), 1002);
      expect(hatchMinute(e, 1001), isNull);
      // 11번째 탭은 무시
      expect(tapEggAt(e, 1500).tenthTapAt, 1002);
      // 탭이 3분 이후에 10번째면 자동 부화 시각
      var late = const Egg(species: Species.eggA, name: 'a', startedAt: 1000);
      for (var i = 0; i < 10; i++) {
        late = tapEggAt(late, 1100);
      }
      expect(hatchMinute(late, 1100), 1003);
    });
  });
}
