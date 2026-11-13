// 미니게임 순수 함수 (lib/domain/minigame.dart) 단위 테스트.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petory/domain/domain.dart';

List<RoundResult> hits(List<int> ms) => [
  for (final m in ms) RoundResult.hit(m),
];

void main() {
  group('judgeTap', () {
    test('신호 전 탭은 early 실패', () {
      expect(
        judgeTap(signalAtMs: null, tapAtMs: 500),
        const RoundResult.early(),
      );
    });
    test('신호보다 빠른 시각은 early', () {
      expect(
        judgeTap(signalAtMs: 1000, tapAtMs: 999),
        const RoundResult.early(),
      );
    });
    test('신호 직후 0ms 와 제한 시간 경계는 성공, 초과는 missed', () {
      expect(
        judgeTap(signalAtMs: 1000, tapAtMs: 1000),
        const RoundResult.hit(0),
      );
      expect(
        judgeTap(signalAtMs: 1000, tapAtMs: 1000 + kMinigameTimeoutMs),
        const RoundResult.hit(kMinigameTimeoutMs),
      );
      expect(
        judgeTap(signalAtMs: 1000, tapAtMs: 1001 + kMinigameTimeoutMs),
        const RoundResult.missed(),
      );
    });
    test('반응시간은 탭 - 신호', () {
      expect(judgeTap(signalAtMs: 2000, tapAtMs: 2312).reactionMs, 312);
    });
  });

  group('averageReactionMs', () {
    test('성공 라운드만 평균(반올림), 실패는 제외', () {
      final r = [
        const RoundResult.hit(300),
        const RoundResult.early(),
        const RoundResult.hit(401),
      ];
      expect(averageReactionMs(r), 351); // (300+401)/2 = 350.5 → 351
    });
    test('전부 실패면 null', () {
      expect(
        averageReactionMs(const [
          RoundResult.early(),
          RoundResult.missed(),
          RoundResult.early(),
        ]),
        isNull,
      );
      expect(averageReactionMs(const []), isNull);
    });
  });

  group('점수 구간 → 행복 증가량 (경계값)', () {
    test('상수 경계', () {
      expect(kMinigameGain2MaxAvgMs, 450);
      expect(kMinigameGain1MaxAvgMs, 800);
    });
    test('450ms 이하 +2, 451ms +1', () {
      expect(gainForAverage(0), 2);
      expect(gainForAverage(450), 2);
      expect(gainForAverage(451), 1);
    });
    test('800ms 이하 +1, 801ms +0', () {
      expect(gainForAverage(800), 1);
      expect(gainForAverage(801), 0);
      expect(gainForAverage(kMinigameTimeoutMs), 0);
    });
    test('라운드 목록 기준: 평균 450 → +2, 평균 451 → +1', () {
      expect(gainForRounds(hits([400, 450, 500])), 2);
      expect(gainForRounds(hits([401, 451, 501])), 1); // 평균 451
      expect(gainForRounds(hits([800, 800, 800])), 1);
      expect(gainForRounds(hits([801, 801, 801])), 0);
    });
    test('일부 실패는 성공 라운드 평균으로 판정', () {
      expect(
        gainForRounds([
          const RoundResult.hit(300),
          const RoundResult.early(),
          const RoundResult.hit(500),
        ]),
        2, // 평균 400
      );
    });
    test('전부 실패 → +0 / null → +0', () {
      expect(
        gainForRounds(const [
          RoundResult.early(),
          RoundResult.early(),
          RoundResult.missed(),
        ]),
        0,
      );
      expect(gainForAverage(null), 0);
    });
    test('gain 은 CareAction.minigame 의 0..2 범위에 항상 들어간다', () {
      for (final avg in [null, 0, 450, 451, 800, 801, 5000]) {
        expect(gainForAverage(avg), inInclusiveRange(0, 2));
      }
    });
  });

  group('signalDelayMs (난수 주입)', () {
    test('범위 안, 같은 시드면 같은 값', () {
      for (var seed = 0; seed < 50; seed++) {
        final d = signalDelayMs(Random(seed));
        expect(d, inInclusiveRange(kMinigameMinDelayMs, kMinigameMaxDelayMs));
        expect(signalDelayMs(Random(seed)), d);
      }
    });
  });
}
