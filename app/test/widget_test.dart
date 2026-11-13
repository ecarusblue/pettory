import 'package:flutter_test/flutter_test.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/app.dart';

void main() {
  testWidgets('온보딩 → 부화 대기 화면', (tester) async {
    final c = GameController(
      repo: InMemoryPetRepository(),
      push: FakePushScheduleClient(),
    );
    await tester.runAsync(c.init);
    await tester.pumpWidget(PetoryApp(controller: c));
    await tester.pump();
    expect(find.text(Ko.onboardTitle), findsOneWidget);
    await tester.tap(find.text(Ko.start));
    await tester.pump();
    expect(find.text(Ko.hatchTitle), findsOneWidget);
    c.dispose();
  });
}
