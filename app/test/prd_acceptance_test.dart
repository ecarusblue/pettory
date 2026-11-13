// PRD FR-1~FR-9 수용 기준 점검 + 프론트-백엔드 계약 점검 (QA).
// 알려진 버그는 [BUG-n] 이름 + skip 으로 남긴다 (qa-report.md 의 표 참고).
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/app.dart';

/// UTC 12:00 (tz 0, 취침 시간대 23~07 밖).
final DateTime t0 = DateTime.utc(2026, 11, 14, 12);
int minutesOf(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

class H {
  H({DateTime? start}) : now = start ?? t0;
  DateTime now;
  final repo = InMemoryPetRepository();
  final push = FakePushScheduleClient();
  late GameController c;

  Future<GameController> boot({bool pushEnabled = false}) async {
    c = GameController(
      pushEnabled: pushEnabled,
      repo: repo,
      push: push,
      pushSubscription: const PushSubscriptionInfo(
        endpoint: 'https://x.test/e',
        p256dh: 'p',
        auth: 'a',
      ),
      now: () => now,
    );
    await c.init();
    return c;
  }

  void advance(Duration d) {
    now = now.add(d);
    c.refresh();
  }

  /// 저장소에 부화 직후 펫을 미리 넣어 둔다.
  Future<void> seedPet({int? birth}) async {
    final ms = now.millisecondsSinceEpoch;
    await repo.save(
      GameSave(
        pet: PetState.newborn(
          name: 'a',
          species: Species.eggA,
          birthAt: birth ?? minutesOf(now),
        ),
        clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
      ),
    );
  }
}

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('FR-1 온보딩 / FR-2 부화 (컨트롤러)', () {
    test('FR-2 알은 3분 뒤 자동 부화 (2분 59초는 아직)', () async {
      final h = H();
      final c = await h.boot();
      expect(c.phase, GamePhase.onboarding);
      c.startEgg(Species.eggB, '  콩이 ');
      expect(c.phase, GamePhase.hatching);
      expect(c.egg!.name, '콩이'); // 공백 trim
      h.advance(const Duration(minutes: 2, seconds: 59));
      expect(c.phase, GamePhase.hatching);
      h.advance(const Duration(seconds: 1));
      expect(c.phase, GamePhase.home);
      expect(c.pet!.species, Species.eggB);
      expect(c.pet!.stage, Stage.baby);
      c.dispose();
    });

    test('FR-2 알 10회 탭이면 즉시 부화', () async {
      final h = H();
      final c = await h.boot();
      c.startEgg(Species.eggA, '');
      expect(c.egg!.name, '이름없음');
      for (var i = 0; i < 9; i++) {
        c.tapEgg();
      }
      expect(c.phase, GamePhase.hatching);
      c.tapEgg();
      expect(c.phase, GamePhase.home);
      c.dispose();
    });

    test('FR-2 앱을 닫은 채 3분이 지나면 다음 실행에서 3분 시점으로 소급 부화', () async {
      final h = H();
      var c = await h.boot();
      c.startEgg(Species.eggC, '몽');
      final start = minutesOf(h.now);
      c.dispose();
      h.now = h.now.add(const Duration(minutes: 10));
      c = await h.boot();
      expect(c.phase, GamePhase.home);
      expect(c.pet!.birthAt, start + 3);
      expect(c.pet!.lastUpdatedAt, start + 10);
      c.dispose();
    });
  });

  group('FR-4 케어 / FR-5 놀아주기 한도 (컨트롤러)', () {
    test('FR-4 밥/간식/똥/약/재우기 규칙대로 증감', () async {
      final h = H();
      await h.seedPet();
      final c = await h.boot();
      h.advance(const Duration(minutes: 200)); // hunger 3
      expect(c.pet!.hunger, 3);
      expect(c.care(CareAction.feed).ok, isTrue);
      expect(c.pet!.hunger, 4);
      h.advance(const Duration(minutes: 125)); // 똥 1개
      expect(c.pet!.poop, 1);
      expect(c.care(CareAction.cleanPoop).ok, isTrue);
      expect(c.pet!.poop, 0);
      expect(c.care(CareAction.medicine).error, CareError.notSick);
      c.dispose();
    });

    test('FR-5 놀아주기 하루 5회, 6번째는 dailyLimit', () async {
      final h = H();
      await h.seedPet();
      final c = await h.boot();
      for (var i = 0; i < 5; i++) {
        expect(c.care(CareAction.play).ok, isTrue, reason: '${i + 1}번째');
      }
      final r = c.care(CareAction.play);
      expect(r.error, CareError.dailyLimit);
      expect(Ko.careError(CareError.dailyLimit), isNotEmpty);
      c.dispose();
    });
  });

  group('FR-6 앱 종료 중 진화는 다음 실행에서 연출', () {
    test('컨트롤러: 25시간 뒤 재실행하면 child, teen 진화가 대기열에 있다', () async {
      final h = H();
      await h.seedPet();
      h.now = h.now.add(const Duration(minutes: 1500));
      final c = await h.boot();
      expect(c.hasPendingEvolutions, isTrue);
      final ev = c.takePendingEvolutions();
      expect(ev.map((e) => e.stage), [Stage.child, Stage.teen]);
      expect(c.hasPendingEvolutions, isFalse);
      // 도감에도 기록
      expect(
        c.data.dex.map((d) => d.key),
        containsAll(['eggA_child', 'eggA_teen']),
      );
      c.dispose();
    });

    testWidgets('위젯: 홈에 진입하면 진화 다이얼로그가 차례로 뜬다', (tester) async {
      bigView(tester);
      final h = H();
      await h.seedPet();
      h.now = h.now.add(const Duration(minutes: 1500));
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      // FR-9: 25시간 만의 복귀이므로 복귀 안내 화면을 확인한 뒤 진화 연출이 이어진다
      await tester.tap(find.text(Ko.awayConfirm));
      await tester.pumpAndSettle();
      expect(find.text(Ko.evolved('a', Stage.child)), findsOneWidget);
      await tester.tap(find.text(Ko.ok));
      await tester.pumpAndSettle();
      expect(find.text(Ko.evolved('a', Stage.teen)), findsOneWidget);
      await tester.tap(find.text(Ko.ok));
      await tester.pumpAndSettle();
      expect(find.text(Ko.evolved('a', Stage.teen)), findsNothing);
      c.dispose();
    });
  });

  group('FR-7 도감/추억 (데이터; 화면은 test/dex_minigame_ui_test.dart)', () {
    test('떠나면 추억 상자 기록(이름·종·도달 단계·기간)이 저장된다', () async {
      final h = H();
      await h.seedPet();
      h.now = h.now.add(const Duration(days: 5));
      final c = await h.boot();
      expect(c.phase, GamePhase.left);
      final m = c.data.memories.single;
      expect(m.name, 'a');
      expect(m.species, Species.eggA);
      expect(m.maxStage, Stage.teen);
      expect(m.leftAt - m.bornAt, greaterThan(0));
      c.dispose();
    });
  });

  group('FR-8 설정', () {
    test('변경 즉시 저장(알림/사운드/취침 시간)', () async {
      final h = H();
      await h.seedPet();
      final c = await h.boot();
      c.updateSettings(
        c.settings.copyWith(
          notifyEnabled: false,
          soundEnabled: false,
          sleepStart: 22 * 60,
          sleepEnd: 6 * 60,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final saved = (await h.repo.load())!.settings;
      expect(saved.notifyEnabled, isFalse);
      expect(saved.soundEnabled, isFalse);
      expect(saved.sleepStart, 22 * 60);
      expect(saved.sleepEnd, 6 * 60);
      c.dispose();
    });

    test('취침 시간 변경 시 변경 전까지의 경과는 이전 설정으로 확정된다', () async {
      final h = H(start: DateTime.utc(2026, 11, 14, 21)); // 21:00
      await h.seedPet();
      final c = await h.boot();
      h.now = h.now.add(const Duration(hours: 4)); // 01:00 (취침 시간대)
      // 변경 전: 23~07 로 4시간 중 2시간은 절반 속도
      c.updateSettings(c.settings.copyWith(sleepStart: 0, sleepEnd: 0));
      final p = c.pet!;
      // 정상 속도였다면 240분*2=480 → hunger 3 + acc 120 / 절반 구간 포함 시 acc 가 더 작아야 함
      expect(p.hunger * 360 - p.hungerAcc, greaterThan(4 * 360 - 480));
      c.dispose();
    });

    testWidgets('초기화는 확인 팝업 필수: 취소하면 유지, 확인해야 삭제', (tester) async {
      bigView(tester);
      final h = H();
      await h.seedPet();
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.navSettings)); // 하단 내비의 설정 탭
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.resetData));
      await tester.pumpAndSettle();
      expect(find.text(Ko.resetConfirmTitle), findsOneWidget);
      await tester.tap(find.text(Ko.cancel));
      await tester.pumpAndSettle();
      expect(c.pet, isNotNull);
      await tester.tap(find.text(Ko.resetData));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.reset));
      await tester.pumpAndSettle();
      expect(c.pet, isNull);
      expect(c.phase, GamePhase.onboarding);
      expect(await tester.runAsync(h.repo.load), isNull);
      c.dispose();
    });
  });

  group('FR-9 복귀 화면', () {
    test('FR-9 복귀 안내 화면(경과 시간·변화 요약)이 구현돼 있다', () {
      expect(File('lib/ui/away_screen.dart').existsSync(), isTrue);
      expect(File('lib/domain/away_summary.dart').existsSync(), isTrue);
      expect(kAwayThresholdMinutes, greaterThan(0));
      expect(Ko.awayElapsed(200), contains('돌아왔'));
      // 상세 동작은 test/away_summary_test.dart, test/away_screen_test.dart
    });
  });

  group('FR-1 / FR-3 / FR-5 위젯', () {
    testWidgets('FR-1 알 선택 → 시작 → (자동 부화) → 만나러 가기: 탭 3회 이하로 홈 진입', (
      tester,
    ) async {
      bigView(tester);
      final h = H();
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pump();
      var taps = 0;
      await tester.tap(find.text(Ko.eggName(Species.eggB)));
      taps++;
      await tester.pump();
      await tester.tap(find.text(Ko.start));
      taps++;
      await tester.pump();
      expect(find.text(Ko.hatchTitle), findsOneWidget);
      // 두드리지 않고 3분 대기 (자동 부화)
      h.advance(const Duration(minutes: 3));
      await tester.pump();
      expect(find.text(Ko.hatchedTitle), findsOneWidget);
      await tester.tap(find.text(Ko.continueBtn));
      taps++;
      await tester.pump(const Duration(seconds: 4)); // 연출 타이머 소진
      await tester.pumpAndSettle();
      expect(find.text(Ko.feed), findsOneWidget); // 홈 도착
      expect(taps, lessThanOrEqualTo(3));
      c.dispose();
    });

    testWidgets('FR-1 연출은 5초 이내 자동 종료 (3초) / 탭 없이도 홈 진입', (tester) async {
      bigView(tester);
      final h = H();
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pump();
      await tester.tap(find.text(Ko.start));
      await tester.pump();
      h.advance(const Duration(minutes: 3));
      await tester.pump();
      expect(find.text(Ko.hatchedTitle), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(Ko.hatchedTitle), findsNothing);
      expect(find.text(Ko.feed), findsOneWidget);
      c.dispose();
    });

    testWidgets('FR-3 홈에 게이지 3개, 상태 2개, 케어 버튼 6개가 한 화면에 있고 변화가 즉시 반영', (
      tester,
    ) async {
      bigView(tester);
      final h = H();
      await h.seedPet();
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      for (final t in [
        Ko.hunger,
        Ko.happiness,
        Ko.fatigue,
        Ko.poopCount(0),
        Ko.healthy,
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      for (final t in [
        Ko.feed,
        Ko.snack,
        Ko.play,
        Ko.cleanPoop,
        Ko.sleep,
        Ko.medicine,
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('4/4'), findsNWidgets(2));
      // 1초 타이머 틱 대용. 한 번에 3시간 이상 건너뛰면 복귀 화면(FR-9)이 뜨므로 나눠서 진행
      h.advance(const Duration(minutes: 100));
      h.advance(const Duration(minutes: 81));
      await tester.pump();
      expect(find.text('3/4'), findsOneWidget); // hunger
      c.dispose();
    });

    testWidgets('FR-5 한도 도달 시 안내 문구(스낵바) 표시', (tester) async {
      bigView(tester);
      final h = H();
      await h.seedPet();
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      // 놀기를 누르면 선택 시트(기본/미니게임)가 뜬다: 기본 놀아주기 5회 후 6번째는 시트 없이 안내
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(Ko.play));
        await tester.pumpAndSettle();
        await tester.tap(find.text(Ko.playBasic));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(Ko.play));
      await tester.pumpAndSettle();
      expect(find.text(Ko.playLimitReached), findsOneWidget);
      expect(find.text(Ko.playBasic), findsNothing);
      c.dispose();
    });

    testWidgets('떠난 펫: 안내 화면 + 새 알 버튼이 온보딩으로 복귀', (tester) async {
      bigView(tester);
      final h = H();
      await h.seedPet();
      h.now = h.now.add(const Duration(days: 5));
      final c = await tester.runAsync(h.boot) as GameController;
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      // FR-9: 먼저 복귀 안내(부드러운 문구)가 나오고, 확인하면 떠남 화면
      expect(find.text(Ko.awayLeftTitle('a')), findsOneWidget);
      await tester.tap(find.text(Ko.awayLeftConfirm));
      await tester.pumpAndSettle();
      expect(find.text(Ko.leftTitle('a')), findsOneWidget);
      await tester.tap(find.text(Ko.newEgg));
      await tester.pumpAndSettle();
      expect(find.text(Ko.onboardTitle), findsOneWidget);
      expect(c.data.memories, hasLength(1)); // 추억은 유지
      c.dispose();
    });
  });

  group('시간 무결성 (PRD 7장)', () {
    test('기기 시계를 과거로 돌리면 경과 0 (펫 상태 불변)', () async {
      final h = H();
      await h.seedPet();
      final c = await h.boot();
      h.advance(const Duration(minutes: 100));
      final before = c.pet!;
      h.advance(const Duration(days: -3));
      expect(c.pet!, before);
      expect(c.nowMinute, before.lastUpdatedAt);
      c.dispose();
    });

    test('[BUG-7] 시계를 미래로 돌리면 서버 시각 비교로 차단', () async {
      final h = H();
      await h.seedPet();
      h.push.serverTime = () => t0.millisecondsSinceEpoch; // 서버는 실제 시각 t0
      final c = await h.boot(pushEnabled: true);
      h.advance(const Duration(days: 10)); // 시계 조작
      c.refresh();
      expect(c.pet!.left, isFalse);
      expect((c.nowMinute - minutesOf(t0)).abs(), lessThan(2));
      c.dispose();
    });
  });

  group('프론트-백엔드 계약 (server/API.md)', () {
    const serverTypes = {'hunger', 'poop', 'sick', 'evolve'};
    final keyRe = RegExp(r'^[A-Za-z0-9:_-]{1,32}$');

    test('[BUG-1] NotifyType 이름이 서버 type 과 일치', () {
      expect(NotifyType.values.map((e) => e.name).toSet(), serverTypes);
    });

    test('[BUG-2] Scheduled.toJson 은 ISO-8601(오프셋) fireAt 문자열', () {
      final j = const Scheduled(NotifyType.poop, 29_000_000).toJson();
      expect(j.containsKey('fireAt'), isTrue);
      expect(j['fireAt'], isA<String>());
      expect(j['fireAt'] as String, matches(RegExp(r'(Z|[+-]\d\d:?\d\d)$')));
      expect(
        DateTime.parse(j['fireAt'] as String).millisecondsSinceEpoch,
        29_000_000 * 60000,
      );
    });

    test('[BUG-3] sick/evolve 항목에 dedupeKey 포함', () {
      // 돌보지 않은 새끼: 1시간 뒤 진화, 이후 굶어서 아파짐 -> 두 알림 모두 생김
      final p = PetState.newborn(
        name: 'a',
        species: Species.eggA,
        birthAt: 29_000_000,
      );
      final list = nextNotifications(
        p,
        const Settings(sleepStart: 0, sleepEnd: 0),
        p.birthAt,
      );
      for (final t in [NotifyType.sick, NotifyType.evolve]) {
        final j = list
            .firstWhere((e) => e.type == t, orElse: () => fail('${t.name} 없음'))
            .toJson();
        expect(j['dedupeKey'], isA<String>(), reason: t.name);
        expect(j['dedupeKey'] as String, matches(keyRe));
      }
    });

    test('[BUG-4] push_sw.js 가 서버 type(hunger) 의 문구를 가진다', () {
      final sw = File('web/push_sw.js').readAsStringSync();
      expect(RegExp(r'\bhunger\s*:').hasMatch(sw), isTrue);
    });

    test('[BUG-5] push_sw.js 를 등록하는 코드가 있다', () {
      final index = File('web/index.html').readAsStringSync();
      final libs = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join();
      final boot = File('web/flutter_bootstrap.js');
      expect(
        index.contains('push_sw') ||
            libs.contains('push_sw') ||
            (boot.existsSync() && boot.readAsStringSync().contains('push_sw')),
        isTrue,
      );
    });

    test('[BUG-6] 실제 PushScheduleClient 구현(HTTP)과 구독 등록 코드가 있다', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('FakePushScheduleClient'), isFalse);
      final libs = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join();
      expect(libs.contains('/subscribe') && libs.contains('/schedule'), isTrue);
    });

    test('SW 는 앱이 열려 있으면 표시를 생략한다 (서버 API.md 의 클라이언트 책임)', () {
      final sw = File('web/push_sw.js').readAsStringSync();
      expect(
        sw.contains("visibilityState === 'visible'") || sw.contains('focused'),
        isTrue,
      );
    });

    test('Settings.toJson 의 취침/tz 필드명은 서버와 동일(sleepStart/sleepEnd/tzOffsetMinutes)', () {
      final j = const Settings().toJson();
      expect(
        j.keys,
        containsAll(['sleepStart', 'sleepEnd', 'tzOffsetMinutes']),
      );
      // 서버 기준(로컬 자정부터의 분, KST=540)과 같은 의미
      expect(j['tzOffsetMinutes'], 540);
    });

    test(
      '캐릭터 이름이 푸시 클라이언트로 전달되는 경로가 없다 (Scheduled/PushSubscriptionInfo)',
      () async {
        final h = H();
        await h.seedPet();
        final c = await h.boot();
        c.care(CareAction.feed);
        await Future<void>.delayed(Duration.zero);
        final payload = jsonEncode([
          for (final call in h.push.calls)
            [for (final s in call.schedule) s.toJson()],
        ]);
        expect(payload.contains('"a"'), isFalse);
        expect(h.push.calls, isNotEmpty);
        c.dispose();
      },
    );

    test('케어 후 알림 목록이 계산되어 전송된다 (Fake 클라이언트)', () async {
      final h = H();
      await h.seedPet();
      final c = await h.boot();
      h.advance(const Duration(minutes: 10));
      c.care(CareAction.feed);
      await Future<void>.delayed(Duration.zero);
      expect(h.push.lastSchedule, isNotNull);
      expect(
        h.push.lastSchedule!.map((s) => s.type),
        contains(NotifyType.hunger),
      );
      c.dispose();
    });
  });
}
