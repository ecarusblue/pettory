// 추가 미니게임 3종(먹이 받기 / 짝 맞추기 / 숨은 공 찾기) 도메인 로직 테스트.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petory/domain/domain.dart';

void main() {
  group('먹이 받기', () {
    test('점수 → 행복: 7개 이하 +0, 8~14개 +1, 15개 이상 +2', () {
      expect(gainForCatchScore(0), 0);
      expect(gainForCatchScore(7), 0);
      expect(gainForCatchScore(8), 1);
      expect(gainForCatchScore(14), 1);
      expect(gainForCatchScore(15), 2);
      expect(gainForCatchScore(40), 2);
    });

    test('30초가 지나면 끝나고 더 흐르지 않는다', () {
      final g = CatchGame(random: Random(1));
      for (var i = 0; i < 40; i++) {
        g.step(1000);
      }
      expect(g.finished, isTrue);
      expect(g.elapsedMs, kCatchDurationMs);
      expect(g.step(1000), isEmpty);
      expect(g.elapsedMs, kCatchDurationMs);
    });

    test('펫 위치는 화면 안으로 제한된다', () {
      final g = CatchGame();
      g.movePlayer(-3);
      expect(g.playerX, kCatchMinX);
      g.movePlayer(9);
      expect(g.playerX, kCatchMaxX);
    });

    test('같은 위치의 음식은 받아서 +1, 똥은 −1(0 미만 불가)', () {
      final g = CatchGame(random: Random(2));
      g.playerX = 0.5;
      g.items.add(FallingItem(x: 0.5, kind: CatchKind.apple)..y = 0.79);
      expect(g.step(100), [CatchKind.apple]);
      expect(g.score, 1);
      g.items.add(FallingItem(x: 0.5, kind: CatchKind.poop)..y = 0.79);
      expect(g.step(100), [CatchKind.poop]);
      expect(g.score, 0);
      g.items.add(FallingItem(x: 0.5, kind: CatchKind.poop)..y = 0.79);
      g.step(100);
      expect(g.score, 0, reason: '점수는 0 아래로 내려가지 않는다');
    });

    test('멀리 떨어진 음식은 받지 못하고 바닥에서 사라진다', () {
      final g = CatchGame(random: Random(3));
      g.playerX = 0.2;
      g.items
        ..clear()
        ..add(FallingItem(x: 0.9, kind: CatchKind.apple)..y = 0.79);
      final caught = g.step(2000);
      expect(caught.where((k) => k == CatchKind.apple), isEmpty);
      expect(g.items.any((i) => i.x == 0.9), isFalse);
    });

    test('큰 dt 한 번이나 잘게 쪼갠 dt 나 같은 결과(시간 분할 불변)', () {
      CatchGame run(int dt) {
        final g = CatchGame(random: Random(7))..playerX = 0.5;
        for (var t = 0; t < 30000; t += dt) {
          g.step(dt);
        }
        return g;
      }

      final a = run(50), b = run(10000);
      expect(a.score, b.score);
      expect(a.finished && b.finished, isTrue);
    });
  });

  group('짝 맞추기', () {
    test('카드는 12장, 그림은 6종이 각각 2장', () {
      final g = MemoryGame(random: Random(1));
      expect(g.cards.length, kMemoryPairs * 2);
      for (var f = 0; f < kMemoryPairs; f++) {
        expect(g.cards.where((c) => c == f).length, 2);
      }
    });

    test('점수: 12회 이하 +2, 13~18회 +1, 그 이상·미완성 +0', () {
      expect(gainForMemory(complete: true, attempts: 6), 2);
      expect(gainForMemory(complete: true, attempts: 12), 2);
      expect(gainForMemory(complete: true, attempts: 13), 1);
      expect(gainForMemory(complete: true, attempts: 18), 1);
      expect(gainForMemory(complete: true, attempts: 19), 0);
      expect(gainForMemory(complete: false, attempts: 3), 0);
    });

    int indexOfPair(MemoryGame g, int card, {int skip = -1}) => List.generate(
      g.cards.length,
      (i) => i,
    ).firstWhere((i) => g.cards[i] == card && i != skip);

    test('같은 그림 두 장을 뒤집으면 맞추고 시도가 1 늘어난다', () {
      final g = MemoryGame(random: Random(1));
      final a = indexOfPair(g, g.cards[0]);
      final b = indexOfPair(g, g.cards[0], skip: a);
      expect(g.flip(a), FlipOutcome.first);
      expect(g.flip(b), FlipOutcome.match);
      expect(g.attempts, 1);
      expect(g.pairsFound, 1);
      expect(g.faceUp, isEmpty);
    });

    test('다른 그림이면 mismatch, 다음 뒤집기 전에 자동으로 덮인다', () {
      final g = MemoryGame(random: Random(1));
      final a = 0;
      final b = List.generate(
        12,
        (i) => i,
      ).firstWhere((i) => g.cards[i] != g.cards[a]);
      g.flip(a);
      expect(g.flip(b), FlipOutcome.mismatch);
      expect(g.hasPendingMismatch, isTrue);
      final c = List.generate(12, (i) => i).firstWhere((i) => i != a && i != b);
      expect(g.flip(c), FlipOutcome.first);
      expect(g.faceUp, [c]);
      expect(g.attempts, 1);
    });

    test('맞춘 카드·이미 뒤집은 카드·범위 밖은 무시', () {
      final g = MemoryGame(random: Random(4));
      expect(g.flip(-1), FlipOutcome.ignored);
      expect(g.flip(12), FlipOutcome.ignored);
      g.flip(0);
      expect(g.flip(0), FlipOutcome.ignored);
      final b = indexOfPair(g, g.cards[0], skip: 0);
      g.flip(b);
      expect(g.flip(0), FlipOutcome.ignored);
    });

    test('정답을 아는 플레이어는 6번 시도로 끝낸다', () {
      final g = MemoryGame(random: Random(5));
      for (var f = 0; f < kMemoryPairs; f++) {
        final a = indexOfPair(g, f);
        final b = indexOfPair(g, f, skip: a);
        g.flip(a);
        g.flip(b);
      }
      expect(g.complete, isTrue);
      expect(g.attempts, kMemoryPairs);
      expect(gainForMemory(complete: g.complete, attempts: g.attempts), 2);
    });
  });

  group('숨은 공 찾기', () {
    test('맞힌 개수 → 행복: 0~1 +0, 2~3 +1, 4~5 +2', () {
      expect([for (var i = 0; i <= 5; i++) gainForCups(i)], [0, 0, 1, 1, 2, 2]);
    });

    test('판이 갈수록 컵이 늘고 섞기는 많아지고 빨라진다', () {
      expect(
        [for (var r = 0; r < kCupsRounds; r++) cupCountForRound(r)],
        [3, 3, 3, 4, 4],
      );
      for (var r = 1; r < kCupsRounds; r++) {
        expect(swapCountForRound(r), greaterThan(swapCountForRound(r - 1)));
        expect(
          swapDurationMsForRound(r),
          lessThan(swapDurationMsForRound(r - 1)),
        );
      }
      expect(swapDurationMsForRound(99), greaterThanOrEqualTo(240));
    });

    test('섞기 규칙: 서로 다른 두 자리, 공의 최종 자리는 섞기를 따라간 결과', () {
      final rng = Random(11);
      for (var round = 0; round < kCupsRounds; round++) {
        for (var k = 0; k < 50; k++) {
          final cfg = buildCupsRound(round, rng);
          expect(cfg.swaps.length, swapCountForRound(round));
          var slot = cfg.ballCup;
          for (final s in cfg.swaps) {
            expect(s.a, isNot(s.b));
            expect(s.a, inInclusiveRange(0, cfg.cups - 1));
            expect(s.b, inInclusiveRange(0, cfg.cups - 1));
            if (slot == s.a) {
              slot = s.b;
            } else if (slot == s.b) {
              slot = s.a;
            }
          }
          expect(cfg.finalSlotOfBall, slot);
          expect(cfg.isCorrect(slot), isTrue);
          expect(cfg.isCorrect((slot + 1) % cfg.cups), isFalse);
        }
      }
    });
  });
}
