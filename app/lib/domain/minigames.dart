/// 추가 미니게임 3종(먹이 받기 / 짝 맞추기 / 숨은 공 찾기)의 순수 로직.
/// Flutter 의존 없음. 난수와 경과 시간은 호출부가 주입한다.
/// 각 게임은 결과를 행복 증가량(0/1/2)으로 환산해 `CareAction.minigame(gain)` 으로 적용한다.
library;

import 'dart:math';

// ---------------------------------------------------------------------------
// 먹이 받기
// ---------------------------------------------------------------------------

/// 한 판 길이(ms).
const int kCatchDurationMs = 30000;

/// 받은 점수 → 행복 +1 / +2 가 되는 최소 점수.
const int kCatchGain1Min = 8;
const int kCatchGain2Min = 15;

/// 화면 위쪽 0, 바닥 1 로 정규화한 세로 좌표. 이 선 아래로 내려온 아이템부터 받을 수 있다.
const double kCatchLine = 0.80;

/// 펫 중심에서 좌우로 이만큼(가로 0~1 기준) 안이면 받는다.
const double kCatchHalfWidth = 0.13;

/// 펫이 화면 밖으로 나가지 않도록 하는 가로 범위.
const double kCatchMinX = 0.1;
const double kCatchMaxX = 0.9;

enum CatchKind { apple, cookie, poop }

class FallingItem {
  FallingItem({required this.x, required this.kind}) : y = 0;
  final double x;
  final CatchKind kind;

  /// 0(위) ~ 1(바닥).
  double y;
}

/// 점수 → 행복 증가량.
int gainForCatchScore(int score) {
  if (score >= kCatchGain2Min) return 2;
  if (score >= kCatchGain1Min) return 1;
  return 0;
}

class CatchGame {
  CatchGame({Random? random}) : _rng = random ?? Random();
  final Random _rng;

  final List<FallingItem> items = [];
  double playerX = 0.5;

  /// 음식 +1, 똥 −1 (0 미만으로는 내려가지 않는다).
  int score = 0;
  int elapsedMs = 0;
  int _sinceSpawnMs = 0;

  bool get finished => elapsedMs >= kCatchDurationMs;
  int get remainingMs => max(0, kCatchDurationMs - elapsedMs);
  double get progress => (elapsedMs / kCatchDurationMs).clamp(0.0, 1.0);

  void movePlayer(double x) => playerX = x.clamp(kCatchMinX, kCatchMaxX);

  /// 시간이 [dtMs] 만큼 흐른다. 이번에 받은 아이템 종류를 돌려준다.
  List<CatchKind> step(int dtMs) {
    final caught = <CatchKind>[];
    var left = min(dtMs, kCatchDurationMs - elapsedMs);
    while (left > 0) {
      final dt = min(left, 50); // 큰 dt 도 한 칸씩 쪼개 충돌을 놓치지 않는다.
      left -= dt;
      elapsedMs += dt;
      _sinceSpawnMs += dt;
      final spawnEvery = 750 - (250 * progress).round();
      if (_sinceSpawnMs >= spawnEvery) {
        _sinceSpawnMs -= spawnEvery;
        _spawn();
      }
      final fall = (0.00035 + 0.00025 * progress) * dt;
      for (final it in items) {
        it.y += fall;
      }
      items.removeWhere((it) {
        if (it.y >= kCatchLine &&
            it.y <= 1.0 &&
            (it.x - playerX).abs() <= kCatchHalfWidth) {
          score = it.kind == CatchKind.poop ? max(0, score - 1) : score + 1;
          caught.add(it.kind);
          return true;
        }
        return it.y > 1.05;
      });
    }
    return caught;
  }

  void _spawn() {
    final r = _rng.nextDouble();
    final kind = r < 0.25
        ? CatchKind.poop
        : (r < 0.6 ? CatchKind.cookie : CatchKind.apple);
    items.add(
      FallingItem(
        x: kCatchMinX + _rng.nextDouble() * (kCatchMaxX - kCatchMinX),
        kind: kind,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 짝 맞추기
// ---------------------------------------------------------------------------

const int kMemoryPairs = 6;
const int kMemoryTimeLimitMs = 60000;

/// 이 시도 횟수 이하면 행복 +2 / +1 (초과·미완성은 +0).
const int kMemoryGain2MaxAttempts = 12;
const int kMemoryGain1MaxAttempts = 18;

enum FlipOutcome {
  /// 이미 맞췄거나 뒤집힌 카드, 범위 밖.
  ignored,

  /// 첫 장을 뒤집음.
  first,

  /// 두 장이 같음.
  match,

  /// 두 장이 다름. 호출부가 잠깐 보여 준 뒤 [MemoryGame.hideMismatch] 를 부른다.
  mismatch,
}

int gainForMemory({required bool complete, required int attempts}) {
  if (!complete) return 0;
  if (attempts <= kMemoryGain2MaxAttempts) return 2;
  if (attempts <= kMemoryGain1MaxAttempts) return 1;
  return 0;
}

class MemoryGame {
  MemoryGame({Random? random})
    : cards = ([
        for (var i = 0; i < kMemoryPairs; i++) ...[i, i],
      ]..shuffle(random ?? Random()));

  /// 카드 칸마다 그림 번호(0 ~ kMemoryPairs-1).
  final List<int> cards;
  final Set<int> matched = {};

  /// 지금 앞면인(맞추지 못한) 카드. 최대 2장.
  final List<int> faceUp = [];
  int attempts = 0;

  bool get complete => matched.length == cards.length;
  bool get hasPendingMismatch => faceUp.length == 2;
  int get pairsFound => matched.length ~/ 2;

  FlipOutcome flip(int i) {
    if (i < 0 || i >= cards.length) return FlipOutcome.ignored;
    if (matched.contains(i) || faceUp.contains(i)) return FlipOutcome.ignored;
    if (faceUp.length == 2) faceUp.clear(); // 틀린 짝이 남아 있으면 먼저 덮는다.
    faceUp.add(i);
    if (faceUp.length == 1) return FlipOutcome.first;
    attempts++;
    if (cards[faceUp[0]] == cards[i]) {
      matched.addAll(faceUp);
      faceUp.clear();
      return FlipOutcome.match;
    }
    return FlipOutcome.mismatch;
  }

  void hideMismatch() {
    if (faceUp.length == 2) faceUp.clear();
  }
}

// ---------------------------------------------------------------------------
// 숨은 공 찾기
// ---------------------------------------------------------------------------

const int kCupsRounds = 5;

/// 맞힌 개수 → 행복. 4개 이상 +2, 2개 이상 +1.
int gainForCups(int correct) {
  if (correct >= 4) return 2;
  if (correct >= 2) return 1;
  return 0;
}

/// 판(0부터)마다 컵 수: 앞 3판은 3개, 뒤 2판은 4개.
int cupCountForRound(int round) => round < 3 ? 3 : 4;

/// 판이 갈수록 섞는 횟수는 늘고 한 번 섞는 시간(ms)은 줄어든다.
int swapCountForRound(int round) => 4 + round;
int swapDurationMsForRound(int round) => max(240, 520 - 70 * round);

class CupSwap {
  const CupSwap(this.a, this.b);

  /// 자리 번호 두 개(서로 다름).
  final int a;
  final int b;
}

class CupsRound {
  const CupsRound({
    required this.cups,
    required this.ballCup,
    required this.swaps,
    required this.finalSlotOfBall,
  });

  final int cups;

  /// 공이 들어 있는 컵 번호(처음 자리와 같다).
  final int ballCup;
  final List<CupSwap> swaps;

  /// 섞기가 끝난 뒤 공이 있는 자리.
  final int finalSlotOfBall;

  bool isCorrect(int slot) => slot == finalSlotOfBall;
}

CupsRound buildCupsRound(int round, Random rng) {
  final cups = cupCountForRound(round);
  final ball = rng.nextInt(cups);
  final swaps = <CupSwap>[];
  var slot = ball;
  for (var i = 0; i < swapCountForRound(round); i++) {
    final a = rng.nextInt(cups);
    final b = (a + 1 + rng.nextInt(cups - 1)) % cups;
    swaps.add(CupSwap(a, b));
    if (slot == a) {
      slot = b;
    } else if (slot == b) {
      slot = a;
    }
  }
  return CupsRound(
    cups: cups,
    ballCup: ball,
    swaps: swaps,
    finalSlotOfBall: slot,
  );
}
