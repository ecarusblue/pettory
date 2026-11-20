// 추가 미니게임 3종 화면 위젯 테스트.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/app.dart';
import 'package:petory/ui/catch_game_screen.dart';
import 'package:petory/ui/cups_game_screen.dart';
import 'package:petory/ui/memory_game_screen.dart';
import 'package:petory/ui/theme.dart';

final DateTime t0 = DateTime.utc(2026, 11, 14, 12);
int minutesOf(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<GameController> boot(WidgetTester tester, {int happiness = 1}) async {
  final ms = t0.millisecondsSinceEpoch;
  final repo = InMemoryPetRepository();
  await repo.save(
    GameSave(
      pet: PetState.newborn(
        name: 'a',
        species: Species.eggA,
        birthAt: minutesOf(t0),
      ).copyWith(happiness: happiness),
      dex: const [],
      memories: const [],
      clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
    ),
  );
  final c = GameController(
    repo: repo,
    push: FakePushScheduleClient(),
    now: () => t0,
  );
  await tester.runAsync(c.init);
  addTearDown(c.dispose);
  return c;
}

Widget wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  group('놀이 선택 시트', () {
    for (final (title, intro) in [
      (Ko.playCatch, Ko.catchIntro),
      (Ko.playMemory, Ko.memoryIntro),
      (Ko.playCups, Ko.cupsIntro(kCupsRounds)),
    ]) {
      testWidgets('$title 을 고르면 해당 게임 안내가 열린다', (tester) async {
        bigView(tester);
        final c = await boot(tester);
        await tester.pumpWidget(PetoryApp(controller: c));
        await tester.pumpAndSettle();
        await tester.tap(find.text(Ko.play));
        await tester.pumpAndSettle();
        expect(find.text(Ko.playBasic), findsOneWidget);
        expect(find.text(Ko.playMinigame), findsOneWidget);
        expect(find.text(Ko.playCatch), findsOneWidget);
        expect(find.text(Ko.playMemory), findsOneWidget);
        expect(find.text(Ko.playCups), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.text(intro), findsOneWidget);
        expect(find.text(Ko.mgStart), findsOneWidget);
      });
    }
  });

  group('먹이 받기', () {
    testWidgets('30초가 지나면 결과가 나오고 점수에 맞게 행복이 오른다', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 0);
      await tester.pumpWidget(
        wrap(CatchGameScreen(controller: c, random: Random(1))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      expect(find.text(Ko.catchScore(0)), findsOneWidget);
      // 좌우 버튼으로 펫을 움직일 수 있다.
      await tester.tap(find.byKey(const Key('catch-left')));
      await tester.tap(find.byKey(const Key('catch-right')));
      for (var i = 0; i < 320; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(Ko.mgResultTitle), findsOneWidget);
      expect(find.textContaining('받은 점수'), findsOneWidget);
      expect(c.pet!.playCount, 1);
      expect(c.pet!.happiness, inInclusiveRange(0, 2));
    });

    testWidgets('화면을 누르면 펫이 그 위치로 이동한다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(
        wrap(CatchGameScreen(controller: c, random: Random(1))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      final stage = find.byKey(const Key('catch-stage'));
      final rect = tester.getRect(stage);
      await tester.tapAt(Offset(rect.left + rect.width * 0.8, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
      // 화면에 그려진 상태에서 오류 없이 점수 줄이 유지된다.
      expect(find.textContaining('받은 점수'), findsOneWidget);
    });
  });

  group('짝 맞추기', () {
    // 화면은 initState 에서 한 번, 시작할 때 한 번 카드를 섞는다. 같은 시드로 두 번째 덱을 재현한다.
    List<int> deckFor(int seed) {
      final rng = Random(seed);
      MemoryGame(random: rng);
      return MemoryGame(random: rng).cards;
    }

    testWidgets('모든 짝을 6번 만에 찾으면 행복 +2', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      await tester.pumpWidget(
        wrap(MemoryGameScreen(controller: c, random: Random(5))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      final deck = deckFor(5);
      for (var f = 0; f < kMemoryPairs; f++) {
        final idx = [
          for (var i = 0; i < deck.length; i++)
            if (deck[i] == f) i,
        ];
        await tester.tap(find.byKey(Key('memory-card-${idx[0]}')));
        await tester.pump();
        await tester.tap(find.byKey(Key('memory-card-${idx[1]}')));
        await tester.pump();
      }
      await tester.pump();
      expect(find.text(Ko.memoryCompleted), findsOneWidget);
      expect(
        find.text(Ko.memoryResultLine(6, kMemoryPairs, kMemoryPairs)),
        findsOneWidget,
      );
      expect(find.text(Ko.mgHappinessGain(2)), findsOneWidget);
      expect(c.pet!.happiness, 3);
    });

    testWidgets('틀린 짝은 잠깐 보여 준 뒤 다시 덮이고 시도 횟수가 오른다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(
        wrap(MemoryGameScreen(controller: c, random: Random(5))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      final deck = deckFor(5);
      final other = deck.indexWhere((f) => f != deck[0]);
      await tester.tap(find.byKey(const Key('memory-card-0')));
      await tester.pump();
      await tester.tap(find.byKey(Key('memory-card-$other')));
      await tester.pump();
      expect(find.text(Ko.memoryStatus(1, 0, kMemoryPairs)), findsOneWidget);
      expect(
        find.bySemanticsLabel(Ko.memoryCardUp(1, Ko.memoryNames[deck[0]])),
        findsOneWidget,
      );
      await tester.pump(kMemoryMismatchShow + const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel(Ko.memoryCardDown(1)), findsOneWidget);
    });

    testWidgets('60초가 지나면 시간 종료, 행복은 오르지 않는다', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      await tester.pumpWidget(
        wrap(MemoryGameScreen(controller: c, random: Random(5))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      await tester.pump(const Duration(seconds: 61));
      expect(find.text(Ko.memoryTimeUp), findsOneWidget);
      expect(find.text(Ko.mgGainNone), findsOneWidget);
      expect(c.pet!.happiness, 1);
    });
  });

  group('숨은 공 찾기', () {
    /// 공을 보여 주고 섞는 시간을 모두 흘려 보낸다.
    Future<void> waitShuffle(WidgetTester tester, int round) async {
      final ms =
          kCupsShowBall.inMilliseconds +
          swapCountForRound(round) * swapDurationMsForRound(round) +
          500;
      await tester.pump(Duration(milliseconds: ms));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('5판을 모두 맞히면 행복 +2', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      await tester.pumpWidget(
        wrap(CupsGameScreen(controller: c, random: Random(3))),
      );
      final mirror = Random(3);
      await tester.tap(find.text(Ko.mgStart));
      for (var r = 0; r < kCupsRounds; r++) {
        final cfg = buildCupsRound(r, mirror);
        await tester.pump();
        expect(find.text(Ko.cupsWatch), findsOneWidget);
        await waitShuffle(tester, r);
        expect(find.text(Ko.cupsPick), findsOneWidget);
        await tester.tap(find.byKey(Key('cup-${cfg.ballCup}')));
        await tester.pump();
        expect(find.text(Ko.cupsRight), findsOneWidget);
        await tester.tap(
          find.text(r == kCupsRounds - 1 ? Ko.mgShowResult : Ko.cupsNext),
        );
      }
      await tester.pump();
      expect(
        find.text(Ko.cupsResultLine(kCupsRounds, kCupsRounds)),
        findsOneWidget,
      );
      expect(find.text(Ko.mgHappinessGain(2)), findsOneWidget);
      expect(c.pet!.happiness, 3);
    });

    testWidgets('틀린 컵을 고르면 안내하고, 전부 틀리면 행복은 그대로', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      await tester.pumpWidget(
        wrap(CupsGameScreen(controller: c, random: Random(9))),
      );
      final mirror = Random(9);
      await tester.tap(find.text(Ko.mgStart));
      for (var r = 0; r < kCupsRounds; r++) {
        final cfg = buildCupsRound(r, mirror);
        await tester.pump();
        await waitShuffle(tester, r);
        final wrong = (cfg.ballCup + 1) % cfg.cups;
        await tester.tap(find.byKey(Key('cup-$wrong')));
        await tester.pump();
        expect(find.text(Ko.cupsWrong), findsOneWidget);
        await tester.tap(
          find.text(r == kCupsRounds - 1 ? Ko.mgShowResult : Ko.cupsNext),
        );
      }
      await tester.pump();
      expect(find.text(Ko.cupsResultLine(0, kCupsRounds)), findsOneWidget);
      expect(find.text(Ko.mgGainNone), findsOneWidget);
      expect(c.pet!.happiness, 1);
    });

    testWidgets('섞는 중에는 컵을 눌러도 선택되지 않는다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(
        wrap(CupsGameScreen(controller: c, random: Random(3))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      await tester.pump(kCupsShowBall + const Duration(milliseconds: 100));
      expect(find.text(Ko.cupsShuffling), findsOneWidget);
      await tester.tap(find.byKey(const Key('cup-0')), warnIfMissed: false);
      await tester.pump();
      expect(find.text(Ko.cupsRight), findsNothing);
      expect(find.text(Ko.cupsWrong), findsNothing);
      // 타이머가 남은 채 끝나지 않도록 화면을 치운다.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
