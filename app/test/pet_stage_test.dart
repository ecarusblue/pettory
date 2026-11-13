import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/pet_painter.dart';
import 'package:petory/ui/pet_stage.dart';

PetState _pet({int hunger = 4, int happiness = 4, bool sick = false}) =>
    PetState.newborn(
      name: '몽이',
      species: Species.eggA,
      birthAt: 0,
    ).copyWith(hunger: hunger, happiness: happiness, sick: sick);

void main() {
  test('기분은 스탯에서 파생된다', () {
    expect(moodOf(_pet()), PetMood.happy);
    expect(moodOf(_pet(hunger: 1)), PetMood.sad);
    expect(moodOf(_pet(happiness: 0)), PetMood.sad);
    expect(moodOf(_pet(hunger: 2, happiness: 2)), PetMood.neutral);
    expect(moodOf(_pet(sick: true)), PetMood.neutral);
  });

  testWidgets('쓰다듬으면 말풍선이 나왔다가 사라진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetStage(pet: _pet(), semanticsLabel: '몽이, 아기'),
        ),
      ),
    );
    expect(find.text(Ko.petHappy), findsNothing);
    await tester.tap(find.byKey(const Key('pet-stage')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(Ko.petHappy), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(Ko.petHappy), findsNothing);
  });

  testWidgets('케어 반응 문구가 바뀌면 한 번 재생된다', (tester) async {
    Widget app(int serial) => MaterialApp(
      home: Scaffold(
        body: PetStage(
          pet: _pet(),
          semanticsLabel: '몽이, 아기',
          reaction: Ko.careReaction(CareKind.feed),
          reactionSerial: serial,
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    expect(find.text(Ko.careReaction(CareKind.feed)), findsNothing);
    await tester.pumpWidget(app(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(Ko.careReaction(CareKind.feed)), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
