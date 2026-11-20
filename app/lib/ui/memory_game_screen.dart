import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../data/sfx.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'minigame_common.dart';
import 'pixel_sprite.dart';
import 'play_sfx.dart';
import 'theme.dart';

enum _Phase { intro, playing, result }

const _faces = [
  Sprite.apple,
  Sprite.cookie,
  Sprite.ball,
  Sprite.fish,
  Sprite.heart,
  Sprite.star,
];

/// 틀린 짝을 보여 주는 시간.
const Duration kMemoryMismatchShow = Duration(milliseconds: 800);

/// 짝 맞추기. 난수는 주입할 수 있다(테스트용).
class MemoryGameScreen extends StatefulWidget {
  MemoryGameScreen({super.key, required this.controller, Random? random})
    : random = random ?? Random();
  final GameController controller;
  final Random random;

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  GameController get c => widget.controller;
  _Phase _phase = _Phase.intro;
  late MemoryGame _game;
  Timer? _clock;
  Timer? _hide;
  int _elapsedMs = 0;
  MinigameOutcome? _outcome;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _game = MemoryGame(random: widget.random);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  void _start() {
    _game = MemoryGame(random: widget.random);
    _elapsedMs = 0;
    setState(() => _phase = _Phase.playing);
    _clock = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _elapsedMs += 200;
      if (_elapsedMs >= kMemoryTimeLimitMs) {
        _finish(timedOut: true);
      } else {
        setState(() {});
      }
    });
  }

  void _onCard(int i) {
    if (_phase != _Phase.playing) return;
    _hide?.cancel();
    final out = _game.flip(i);
    switch (out) {
      case FlipOutcome.ignored:
        return;
      case FlipOutcome.first:
        playSfx(c, SfxKind.tap);
      case FlipOutcome.match:
        playSfx(c, SfxKind.mgHit);
      case FlipOutcome.mismatch:
        playSfx(c, SfxKind.mgMiss);
        _hide = Timer(kMemoryMismatchShow, () {
          if (!mounted) return;
          setState(_game.hideMismatch);
        });
    }
    if (_game.complete) {
      _finish(timedOut: false);
      return;
    }
    setState(() {});
  }

  void _finish({required bool timedOut}) {
    _clock?.cancel();
    _hide?.cancel();
    final gain = gainForMemory(
      complete: _game.complete,
      attempts: _game.attempts,
    );
    final out = applyMinigameGain(c, gain);
    setState(() {
      _timedOut = timedOut;
      _outcome = out;
      _phase = _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MinigameFrame(
      title: Ko.memoryTitle,
      child: switch (_phase) {
        _Phase.intro => MinigameIntro(
          icon: Icons.style,
          text: Ko.memoryIntro,
          onStart: _start,
        ),
        _Phase.playing => _play(context),
        _Phase.result => MinigameResultView(
          lines: [
            _timedOut ? Ko.memoryTimeUp : Ko.memoryCompleted,
            Ko.memoryResultLine(_game.attempts, _game.pairsFound, kMemoryPairs),
          ],
          outcome: _outcome!,
        ),
      },
    );
  }

  Widget _play(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final left = ((kMemoryTimeLimitMs - _elapsedMs) / kMemoryTimeLimitMs).clamp(
      0.0,
      1.0,
    );
    return Column(
      children: [
        Text(
          Ko.memoryStatus(_game.attempts, _game.pairsFound, kMemoryPairs),
          style: t.titleMedium,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: left,
            minHeight: 10,
            color: PetoryColors.tired,
            backgroundColor: PetoryColors.card,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (var i = 0; i < _game.cards.length; i++) _card(i)],
          ),
        ),
        const SizedBox(height: 8),
        Text(Ko.memoryHint, style: t.bodyMedium),
      ],
    );
  }

  Widget _card(int i) {
    final done = _game.matched.contains(i);
    final up = _game.faceUp.contains(i);
    final face = _game.cards[i];
    final n = i + 1;
    final name = Ko.memoryNames[face];
    final label = done
        ? Ko.memoryCardDone(n, name)
        : up
        ? Ko.memoryCardUp(n, name)
        : Ko.memoryCardDown(n);
    final shown = done || up;
    return Semantics(
      button: !done,
      label: label,
      excludeSemantics: true,
      onTap: done ? null : () => _onCard(i),
      child: GestureDetector(
        key: Key('memory-card-$i'),
        onTap: () => _onCard(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFDDF4E7)
                : shown
                ? const Color(0xFFFFF6E5)
                : PetoryColors.accent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PetoryColors.text, width: 2),
          ),
          alignment: Alignment.center,
          child: shown
              ? PixelSprite(_faces[face], size: 44)
              : const Icon(Icons.question_mark, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
