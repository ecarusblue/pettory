// FR-5 미니게임 / FR-7 도감·추억 화면 위젯 테스트.
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
import 'package:petory/ui/dex_screen.dart';
import 'package:petory/ui/minigame_screen.dart';
import 'package:petory/ui/theme.dart';

final DateTime t0 = DateTime.utc(2026, 11, 14, 12);
int minutesOf(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

class ManualClock implements ReactionClock {
  int ms = 0;
  @override
  int nowMs() => ms;
}

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 부화 직후 펫(행복 [happiness])과 선택 데이터를 저장소에 넣고 컨트롤러를 부팅한다.
Future<GameController> boot(
  WidgetTester tester, {
  int happiness = 1,
  List<DexEntry> dex = const [],
  List<MemoryEntry> memories = const [],
}) async {
  final ms = t0.millisecondsSinceEpoch;
  final repo = InMemoryPetRepository();
  await repo.save(
    GameSave(
      pet: PetState.newborn(
        name: 'a',
        species: Species.eggA,
        birthAt: minutesOf(t0),
      ).copyWith(happiness: happiness),
      dex: dex,
      memories: memories,
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

/// 신호가 바뀔 때까지 100ms 씩 시간을 흘려 보낸다(무작위 대기 시간과 무관하게 동작).
Future<void> waitForSignal(WidgetTester tester) async {
  for (var i = 0; i < 50 && find.text(Ko.mgSignal).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text(Ko.mgSignal), findsOneWidget);
}

/// 미니게임 한 라운드: 시작/다음 버튼 → 신호 대기 → 반응 [ms] 후 탭.
Future<void> playRound(WidgetTester tester, ManualClock clock, int ms) async {
  await waitForSignal(tester);
  clock.ms += ms;
  await tester.tap(find.byKey(const Key('reaction-pad')));
  await tester.pump();
}

void main() {
  group('FR-5 놀기 진입', () {
    testWidgets('놀기를 누르면 선택 시트(기본 놀아주기 / 미니게임)가 뜨고 기본은 행복 +1', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.play));
      await tester.pumpAndSettle();
      expect(find.text(Ko.playBasic), findsOneWidget);
      expect(find.text(Ko.playMinigame), findsOneWidget);
      await tester.tap(find.text(Ko.playBasic));
      await tester.pumpAndSettle();
      expect(c.pet!.happiness, 2);
      expect(c.pet!.playCount, 1);
    });

    testWidgets('미니게임을 고르면 미니게임 화면(안내)이 열린다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.play));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.playMinigame));
      await tester.pumpAndSettle();
      expect(find.text(Ko.mgIntro(kMinigameRounds)), findsOneWidget);
      expect(find.text(Ko.mgStart), findsOneWidget);
    });

    testWidgets('놀아주기 횟수 제한 없음: 5회 넘어도 선택 시트가 열린다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      for (var i = 0; i < 3; i++) {
        expect(c.care(CareAction.play).ok, isTrue);
      }
      for (var i = 0; i < 2; i++) {
        expect(c.care(CareAction.minigame(1)).ok, isTrue);
      }
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.play));
      await tester.pumpAndSettle();
      expect(find.text(Ko.playMinigame), findsOneWidget);
      expect(c.pet!.playCount, 5);
    });

    testWidgets('자는 중에는 시트 대신 careError(asleep) 안내', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      c.care(CareAction.play); // 피로 1 (재우기 가능하게)
      expect(c.care(CareAction.sleep).ok, isTrue);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.play));
      await tester.pumpAndSettle();
      expect(find.text(Ko.careError(CareError.asleep)), findsOneWidget);
      expect(find.text(Ko.playMinigame), findsNothing);
    });
  });

  group('FR-5 미니게임 화면', () {
    testWidgets('빠른 반응(평균 300ms) 3라운드 → 행복 +2 가 컨트롤러에 적용되고 결과에 표시', (
      tester,
    ) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      final clock = ManualClock();
      await tester.pumpWidget(
        wrap(MinigameScreen(controller: c, clock: clock, random: Random(1))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      expect(find.text(Ko.mgWaiting), findsOneWidget);
      for (var i = 0; i < kMinigameRounds; i++) {
        await playRound(tester, clock, 300);
        expect(find.text(Ko.mgHit(300)), findsOneWidget);
        await tester.tap(
          find.text(
            i == kMinigameRounds - 1 ? Ko.mgShowResult : Ko.mgNextRound,
          ),
        );
        await tester.pump();
      }
      expect(find.text(Ko.mgAverage(300)), findsOneWidget);
      expect(find.text(Ko.mgHappinessGain(2)), findsOneWidget);
      expect(c.pet!.happiness, 3); // 1 + 2
      expect(c.pet!.playCount, 1);
      expect(c.pet!.fatigue, 1);
      expect(find.text(Ko.mgCurrentHappiness(3)), findsOneWidget);
    });

    testWidgets('보통 반응(평균 600ms) → +1, 느림(900ms) → +0', (tester) async {
      bigView(tester);
      for (final (ms, gain) in [(600, 1), (900, 0)]) {
        final c = await boot(tester, happiness: 1);
        final clock = ManualClock();
        await tester.pumpWidget(
          wrap(MinigameScreen(controller: c, clock: clock, random: Random(2))),
        );
        await tester.tap(find.text(Ko.mgStart));
        await tester.pump();
        for (var i = 0; i < kMinigameRounds; i++) {
          await playRound(tester, clock, ms);
          await tester.tap(
            find.text(
              i == kMinigameRounds - 1 ? Ko.mgShowResult : Ko.mgNextRound,
            ),
          );
          await tester.pump();
        }
        expect(c.pet!.happiness, 1 + gain, reason: '$ms ms');
        expect(
          find.text(gain > 0 ? Ko.mgHappinessGain(gain) : Ko.mgGainNone),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('신호 전에 일찍 탭하면 그 라운드 실패, 전부 실패하면 +0 (한도는 소모)', (tester) async {
      bigView(tester);
      final c = await boot(tester, happiness: 1);
      final clock = ManualClock();
      await tester.pumpWidget(
        wrap(MinigameScreen(controller: c, clock: clock, random: Random(3))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      for (var i = 0; i < kMinigameRounds; i++) {
        // 신호 전(최소 대기 시간 안)에 탭
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(Ko.mgWaiting), findsOneWidget);
        await tester.tap(find.byKey(const Key('reaction-pad')));
        await tester.pump();
        expect(find.text(Ko.mgEarly), findsOneWidget);
        await tester.tap(
          find.text(
            i == kMinigameRounds - 1 ? Ko.mgShowResult : Ko.mgNextRound,
          ),
        );
        await tester.pump();
      }
      expect(find.text(Ko.mgAverageNone), findsOneWidget);
      expect(find.text(Ko.mgGainNone), findsOneWidget);
      expect(c.pet!.happiness, 1);
      expect(c.pet!.playCount, 1);
    });

    testWidgets('신호 후 제한 시간 안에 탭하지 않으면 놓침(실패)', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      final clock = ManualClock();
      await tester.pumpWidget(
        wrap(MinigameScreen(controller: c, clock: clock, random: Random(4))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      await waitForSignal(tester);
      await tester.pump(const Duration(milliseconds: kMinigameTimeoutMs + 10));
      expect(find.text(Ko.mgMissed), findsOneWidget);
    });

    testWidgets('신호 변화는 스크린 리더용 라이브 리전 문구로도 제공된다', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      final clock = ManualClock();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(MinigameScreen(controller: c, clock: clock, random: Random(5))),
      );
      await tester.tap(find.text(Ko.mgStart));
      await tester.pump();
      await waitForSignal(tester);
      expect(find.bySemanticsLabel(Ko.mgSignalAnnounce), findsOneWidget);
      handle.dispose();
    });
  });

  group('FR-7 도감', () {
    final dex = [
      DexEntry('eggA_baby', minutesOf(t0)),
      DexEntry('eggA_child', minutesOf(t0) + 1440),
      DexEntry('eggB_adult_excellent', minutesOf(t0) + 2880),
    ];

    test('도감 총 형태 수: 알 3종 × (단계 3 + 성체 티어 3)', () {
      expect(dexTotal, 18);
    });

    testWidgets('해금 3개: 진행률 3/18, 획득 날짜 표시, 미해금은 ???', (tester) async {
      bigView(tester);
      final c = await boot(tester, dex: dex);
      await tester.pumpWidget(wrap(DexScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text(Ko.dexProgress(3, dexTotal)), findsOneWidget);
      expect(find.text(Ko.dexLocked), findsNWidgets(dexTotal - 3));
      final tz = c.settings.tzOffsetMinutes;
      for (final d in dex) {
        expect(
          find.text(Ko.dexAcquired(formatDate(d.unlockedAt, tz))),
          findsOneWidget,
          reason: d.key,
        );
      }
      // 해금된 성체는 등급을 글자로도 표시
      expect(
        find.text(
          '${Ko.stageName(Stage.adult)} ${Ko.tierName(Tier.excellent)}',
        ),
        findsOneWidget,
      );
      // 알 종류 구분 제목 3개
      for (final sp in Species.values) {
        expect(find.text(Ko.eggName(sp)), findsOneWidget);
      }
    });

    testWidgets('아무것도 해금하지 않으면 0/18 이고 전부 ???', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(wrap(DexScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text(Ko.dexProgress(0, dexTotal)), findsOneWidget);
      expect(find.text(Ko.dexLocked), findsNWidgets(dexTotal));
    });

    testWidgets('홈 하단 내비의 도감 탭으로 진입하고 컨트롤러의 도감 키를 그대로 사용', (tester) async {
      bigView(tester);
      final c = await boot(tester, dex: dex);
      // 컨트롤러가 부화 시 저장하는 키 형식과 같은지 확인
      expect(dexKey(Species.eggA, Stage.baby), 'eggA_baby');
      expect(
        dexKey(Species.eggA, Stage.adult, Tier.excellent),
        'eggA_adult_excellent',
      );
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(Ko.navHome), findsOneWidget);
      await tester.tap(find.text(Ko.navDex));
      await tester.pumpAndSettle();
      expect(find.text(Ko.dexProgress(3, dexTotal)), findsOneWidget);
    });
  });

  group('FR-7 추억 탭', () {
    testWidgets('떠난 펫 목록: 이름·종·도달 단계·함께한 기간, 최신순', (tester) async {
      bigView(tester);
      final base = minutesOf(t0);
      final c = await boot(
        tester,
        memories: [
          MemoryEntry(
            name: '오래된이',
            species: Species.eggA,
            maxStage: Stage.child,
            bornAt: base,
            leftAt: base + 3 * 1440 + 5 * 60 + 30,
          ),
          MemoryEntry(
            name: '최근이',
            species: Species.eggC,
            maxStage: Stage.teen,
            bornAt: base + 10000,
            leftAt: base + 10000 + 30,
          ),
        ],
      );
      await tester.pumpWidget(wrap(DexScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.memoryTab));
      await tester.pumpAndSettle();
      expect(find.text('오래된이'), findsOneWidget);
      expect(find.text('최근이'), findsOneWidget);
      expect(
        find.text(Ko.memorySubtitle(Species.eggA, Stage.child)),
        findsOneWidget,
      );
      expect(
        find.text(Ko.memorySubtitle(Species.eggC, Stage.teen)),
        findsOneWidget,
      );
      expect(find.text(Ko.memoryTogether('3일 5시간')), findsOneWidget);
      expect(find.text(Ko.memoryTogether('1시간 미만')), findsOneWidget);
      // 최신순: 나중에 떠난 '최근이' 가 위
      expect(
        tester.getTopLeft(find.text('최근이')).dy,
        lessThan(tester.getTopLeft(find.text('오래된이')).dy),
      );
      expect(find.text(Ko.memoryEmpty), findsNothing);
    });

    testWidgets('비어 있으면 빈 상태 문구', (tester) async {
      bigView(tester);
      final c = await boot(tester);
      await tester.pumpWidget(wrap(DexScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.memoryTab));
      await tester.pumpAndSettle();
      expect(find.text(Ko.memoryEmpty), findsOneWidget);
    });

    test('기간 표기: 일/시간', () {
      expect(Ko.durationDH(0), '1시간 미만');
      expect(Ko.durationDH(59), '1시간 미만');
      expect(Ko.durationDH(60), '1시간');
      expect(Ko.durationDH(1440), '1일');
      expect(Ko.durationDH(1440 + 120), '1일 2시간');
    });
  });
}
