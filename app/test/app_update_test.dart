// 새 버전 안내 배너와 설정의 강제 새로고침 위젯 테스트.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/app_updater.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/app.dart';
import 'package:petory/ui/settings_screen.dart';
import 'package:petory/ui/theme.dart';

final DateTime t0 = DateTime.utc(2026, 11, 14, 12);

class FakeUpdater implements AppUpdater {
  FakeUpdater({this.supported = true});
  final ValueNotifier<bool> ready = ValueNotifier(false);
  int applied = 0;
  int forced = 0;
  @override
  final bool supported;
  @override
  ValueListenable<bool> get updateReady => ready;
  @override
  Future<void> applyUpdate() async => applied++;
  @override
  Future<void> forceRefresh() async => forced++;
}

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<GameController> boot(WidgetTester tester, FakeUpdater updater) async {
  final ms = t0.millisecondsSinceEpoch;
  final repo = InMemoryPetRepository();
  await repo.save(
    GameSave(
      pet: PetState.newborn(
        name: 'a',
        species: Species.eggA,
        birthAt: ms ~/ 60000,
      ),
      dex: const [],
      memories: const [],
      clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
    ),
  );
  final c = GameController(
    repo: repo,
    push: FakePushScheduleClient(),
    updater: updater,
    now: () => t0,
  );
  await tester.runAsync(c.init);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('새 버전 안내', () {
    testWidgets('새 버전이 없으면 배너가 없다', (tester) async {
      bigView(tester);
      final u = FakeUpdater();
      final c = await boot(tester, u);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(Ko.updateReadyTitle), findsNothing);
    });

    testWidgets('새 버전이 준비되면 배너가 뜨고 다시 시작을 누르면 적용한다', (tester) async {
      bigView(tester);
      final u = FakeUpdater();
      final c = await boot(tester, u);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      u.ready.value = true;
      await tester.pump();
      expect(find.text(Ko.updateReadyTitle), findsOneWidget);
      expect(find.text(Ko.updateReadyBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-restart')));
      await tester.pump();
      expect(u.applied, 1);
    });

    testWidgets('이미 준비된 상태로 시작해도 배너가 보인다', (tester) async {
      bigView(tester);
      final u = FakeUpdater()..ready.value = true;
      final c = await boot(tester, u);
      await tester.pumpWidget(PetoryApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(Ko.updateRestart), findsOneWidget);
    });
  });

  group('강제 새로고침', () {
    Future<void> openSettings(WidgetTester tester, GameController c) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: SettingsScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('확인하면 강제 새로고침을 실행한다', (tester) async {
      bigView(tester);
      final u = FakeUpdater();
      final c = await boot(tester, u);
      await openSettings(tester, c);
      await tester.tap(find.byKey(const Key('force-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(Ko.forceRefreshConfirmTitle), findsOneWidget);
      expect(u.forced, 0, reason: '확인 전에는 실행하지 않는다');
      await tester.tap(find.text(Ko.refresh));
      await tester.pumpAndSettle();
      expect(u.forced, 1);
      expect(c.pet, isNotNull, reason: '펫 데이터는 지워지지 않는다');
    });

    testWidgets('취소하면 아무 일도 없다', (tester) async {
      bigView(tester);
      final u = FakeUpdater();
      final c = await boot(tester, u);
      await openSettings(tester, c);
      await tester.tap(find.byKey(const Key('force-refresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.cancel));
      await tester.pumpAndSettle();
      expect(u.forced, 0);
    });

    testWidgets('업데이트를 지원하지 않는 환경에서는 항목이 없다', (tester) async {
      bigView(tester);
      final c = await boot(tester, FakeUpdater(supported: false));
      await openSettings(tester, c);
      expect(find.byKey(const Key('force-refresh')), findsNothing);
    });
  });
}
