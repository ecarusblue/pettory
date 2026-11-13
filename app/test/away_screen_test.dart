// FR-9 복귀 안내 화면 위젯 테스트.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/app.dart';

final DateTime t0 = DateTime.utc(2026, 11, 14, 12);
int minutesOf(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 저장된 부화 직후 펫을 [later] 뒤에 다시 열어 컨트롤러를 부팅한다.
Future<GameController> bootAfter(
  WidgetTester tester,
  Duration later, {
  int speed = 1,
}) async {
  final ms = t0.millisecondsSinceEpoch;
  final repo = InMemoryPetRepository();
  await repo.save(
    GameSave(
      pet: PetState.newborn(
        name: 'a',
        species: Species.eggA,
        birthAt: minutesOf(t0),
      ),
      clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: speed),
    ),
  );
  final c = GameController(
    repo: repo,
    push: FakePushScheduleClient(),
    now: () => t0.add(later),
  );
  await tester.runAsync(c.init);
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('임계값 미만(2시간 59분)이면 복귀 화면 없이 홈', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(minutes: 179));
    expect(c.away, isNull);
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayConfirm), findsNothing);
    expect(find.text(Ko.navHome), findsWidgets);
  });

  testWidgets('임계값(3시간) 이상이면 경과·변화 요약을 보여주고 확인 후 홈', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(minutes: 200));
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayTitle('a')), findsOneWidget);
    expect(find.text(Ko.awayElapsed(200)), findsOneWidget);
    expect(find.text(Ko.awayStat(Ko.hunger, 4, 3)), findsOneWidget);
    expect(find.text(Ko.awayDown(1)), findsOneWidget);
    expect(find.text(Ko.awayHealthy), findsOneWidget);
    expect(find.text(Ko.navHome), findsNothing); // 아직 홈이 아님
    await tester.tap(find.text(Ko.awayConfirm));
    await tester.pumpAndSettle();
    expect(c.away, isNull);
    expect(find.text(Ko.awayConfirm), findsNothing);
    expect(find.text(Ko.navHome), findsWidgets);
  });

  testWidgets('"n일 n시간" 표기', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(hours: 5, minutes: 10));
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('5시간 만에 돌아왔어요'), findsOneWidget);
    expect(Ko.durationDH(26 * 60), '1일 2시간');
  });

  testWidgets('시간 가속 모드에서는 표시하지 않는다', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(minutes: 200), speed: 2);
    expect(c.away, isNull);
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayConfirm), findsNothing);
  });

  testWidgets('시계 역행(경과 0 이하)이면 표시하지 않는다', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(hours: -5));
    expect(c.away, isNull);
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayConfirm), findsNothing);
  });

  testWidgets('진화가 있으면 복귀 화면 먼저, 확인 후 기존 진화 연출이 차례로', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(minutes: 1500));
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayEvolutionCount(2)), findsOneWidget);
    expect(find.text(Ko.evolved('a', Stage.child)), findsNothing);
    expect(c.hasPendingEvolutions, isTrue); // 아직 소비되지 않음
    await tester.tap(find.text(Ko.awayConfirm));
    await tester.pumpAndSettle();
    expect(find.text(Ko.evolved('a', Stage.child)), findsOneWidget);
    await tester.tap(find.text(Ko.ok));
    await tester.pumpAndSettle();
    expect(find.text(Ko.evolved('a', Stage.teen)), findsOneWidget);
    await tester.tap(find.text(Ko.ok));
    await tester.pumpAndSettle();
    expect(find.text(Ko.evolved('a', Stage.teen)), findsNothing);
  });

  testWidgets('떠난 경우: 부드러운 안내 후 기존 떠남 화면, 추억은 1건만', (tester) async {
    bigView(tester);
    final c = await bootAfter(tester, const Duration(days: 5));
    expect(c.phase, GamePhase.left);
    expect(c.data.memories.length, 1);
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text(Ko.awayLeftTitle('a')), findsOneWidget);
    expect(find.text(Ko.newEgg), findsNothing);
    await tester.tap(find.text(Ko.awayLeftConfirm));
    await tester.pumpAndSettle();
    expect(find.text(Ko.newEgg), findsOneWidget);
    expect(find.text(Ko.leftBody), findsOneWidget);
    expect(c.data.memories.length, 1);
  });
}
