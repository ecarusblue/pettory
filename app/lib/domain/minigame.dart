/// 반응속도 미니게임의 순수 로직 (Flutter 의존 없음). 난수·시각은 호출부가 주입한다.
library;

import 'dart:math';

/// 한 판의 라운드 수.
const int kMinigameRounds = 3;

/// 신호가 바뀌기까지의 무작위 대기 시간 범위(ms).
const int kMinigameMinDelayMs = 1200;
const int kMinigameMaxDelayMs = 3500;

/// 신호 후 이 시간 안에 탭하지 않으면 해당 라운드는 '놓침'(실패).
const int kMinigameTimeoutMs = 2000;

/// 평균 반응시간(ms) 구간 경계: 이하이면 해당 보상.
const int kMinigameGain2MaxAvgMs = 450; // 이하 → 행복 +2
const int kMinigameGain1MaxAvgMs = 800; // 이하 → 행복 +1 (초과 → +0)

enum RoundStatus {
  /// 신호 후 시간 안에 탭함.
  hit,

  /// 신호 전에 탭함(실패).
  early,

  /// 제한 시간 안에 탭하지 못함(실패).
  missed,
}

class RoundResult {
  const RoundResult.hit(int ms) : status = RoundStatus.hit, reactionMs = ms;
  const RoundResult.early() : status = RoundStatus.early, reactionMs = null;
  const RoundResult.missed() : status = RoundStatus.missed, reactionMs = null;

  final RoundStatus status;

  /// 성공한 라운드의 반응시간(ms). 실패면 null.
  final int? reactionMs;
  bool get failed => status != RoundStatus.hit;

  @override
  bool operator ==(Object other) =>
      other is RoundResult &&
      other.status == status &&
      other.reactionMs == reactionMs;
  @override
  int get hashCode => Object.hash(status, reactionMs);
  @override
  String toString() => 'RoundResult($status${reactionMs ?? ''})';
}

/// 신호까지의 무작위 대기 시간(ms). 난수 공급자를 주입받는다.
int signalDelayMs(Random rng) =>
    kMinigameMinDelayMs +
    rng.nextInt(kMinigameMaxDelayMs - kMinigameMinDelayMs + 1);

/// 탭 1회를 판정한다. [signalAtMs]가 null(아직 신호 전)이거나 탭이 신호보다
/// 빠르면 early, 반응이 [kMinigameTimeoutMs]를 넘으면 missed.
RoundResult judgeTap({int? signalAtMs, required int tapAtMs}) {
  if (signalAtMs == null || tapAtMs < signalAtMs) {
    return const RoundResult.early();
  }
  final ms = tapAtMs - signalAtMs;
  if (ms > kMinigameTimeoutMs) return const RoundResult.missed();
  return RoundResult.hit(ms);
}

/// 성공한 라운드만의 평균 반응시간(ms, 반올림). 성공이 하나도 없으면 null.
int? averageReactionMs(Iterable<RoundResult> rounds) {
  var sum = 0, n = 0;
  for (final r in rounds) {
    if (!r.failed) {
      sum += r.reactionMs!;
      n++;
    }
  }
  if (n == 0) return null;
  return (sum / n).round();
}

/// 평균 반응시간 → 행복 증가량(0/1/2). null(전부 실패)이면 0.
int gainForAverage(int? avgMs) {
  if (avgMs == null) return 0;
  if (avgMs <= kMinigameGain2MaxAvgMs) return 2;
  if (avgMs <= kMinigameGain1MaxAvgMs) return 1;
  return 0;
}

/// 라운드 결과 전체 → 행복 증가량.
int gainForRounds(Iterable<RoundResult> rounds) =>
    gainForAverage(averageReactionMs(rounds));

/// 단조 시간원(ms). 테스트에서는 수동 구현으로 바꿔 끼운다.
abstract class ReactionClock {
  int nowMs();
}

class StopwatchReactionClock implements ReactionClock {
  StopwatchReactionClock() : _sw = Stopwatch()..start();
  final Stopwatch _sw;
  @override
  int nowMs() => _sw.elapsedMilliseconds;
}
