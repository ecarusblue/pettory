import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:petory/data/sfx.dart';
import 'package:petory/data/sfx_stub.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/pet_stage.dart';
import 'package:petory/ui/play_sfx.dart';

void main() {
  test('모든 효과음에 음이 있고 짧고 들을 만한 높이다', () {
    for (final k in SfxKind.values) {
      final tones = tonesFor(k);
      expect(tones, isNotEmpty, reason: '$k');
      var end = 0.0;
      for (final t in tones) {
        expect(t.hz, inInclusiveRange(100, 2000), reason: '$k');
        expect(t.dur, greaterThan(0), reason: '$k');
        end = end > t.at + t.dur ? end : t.at + t.dur;
      }
      expect(end, lessThan(1.0), reason: '$k 는 1초 안에 끝나야 한다');
    }
  });

  test('케어 종류마다 효과음이 정해져 있다', () {
    for (final k in CareKind.values) {
      expect(sfxForCare(k), isA<SfxKind>());
    }
    expect(sfxForCare(CareKind.feed), SfxKind.feed);
    expect(sfxForCare(CareKind.minigame), SfxKind.play);
  });

  testWidgets('쓰다듬으면 onPet 이 불린다', (tester) async {
    var n = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetStage(
            pet: PetState.newborn(
              name: '몽이',
              species: Species.eggA,
              birthAt: 0,
            ),
            semanticsLabel: '몽이',
            onPet: () => n++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pet-stage')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(n, 1);
    expect(find.text(Ko.petHappy), findsOneWidget);
    await tester.pumpAndSettle();
  });

  test('여섯 케어 버튼은 서로 다른 소리를 낸다', () {
    final kinds = {
      for (final k in [
        CareKind.feed,
        CareKind.snack,
        CareKind.play,
        CareKind.cleanPoop,
        CareKind.sleep,
        CareKind.medicine,
      ])
        sfxForCare(k),
    };
    expect(kinds.length, 6);
    // 실패음은 거친 톱니파가 아니라 부드러운 삼각파
    expect(tonesFor(SfxKind.error).every((t) => t.wave == Wave.triangle), true);
  });

  test('테스트 환경의 재생기는 요청을 기록만 한다', () {
    final p = sfx as RecordingSfxPlayer;
    p.played.clear();
    sfx.play(SfxKind.tap);
    expect(p.played, [SfxKind.tap]);
  });
}
