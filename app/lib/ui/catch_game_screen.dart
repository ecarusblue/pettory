import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../data/sfx.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'minigame_common.dart';
import 'pet_painter.dart';
import 'pixel_sprite.dart';
import 'play_sfx.dart';
import 'theme.dart';

enum _Phase { intro, playing, result }

/// 먹이 받기: 떨어지는 음식을 펫이 받는다. 난수는 주입할 수 있다(테스트용).
class CatchGameScreen extends StatefulWidget {
  CatchGameScreen({super.key, required this.controller, Random? random})
    : random = random ?? Random();
  final GameController controller;
  final Random random;

  @override
  State<CatchGameScreen> createState() => _CatchGameScreenState();
}

class _CatchGameScreenState extends State<CatchGameScreen>
    with SingleTickerProviderStateMixin {
  GameController get c => widget.controller;
  static const double _petSize = 64;
  static const double _itemSize = 40;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  _Phase _phase = _Phase.intro;
  late CatchGame _game;
  MinigameOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _game = CatchGame(random: widget.random);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start() {
    _game = CatchGame(random: widget.random);
    _last = Duration.zero;
    setState(() => _phase = _Phase.playing);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds;
    _last = elapsed;
    if (dt <= 0) return;
    final caught = _game.step(min(dt, 100));
    for (final k in caught) {
      playSfx(c, k == CatchKind.poop ? SfxKind.mgMiss : SfxKind.mgHit);
    }
    if (_game.finished) {
      _ticker.stop();
      final out = applyMinigameGain(c, gainForCatchScore(_game.score));
      setState(() {
        _outcome = out;
        _phase = _Phase.result;
      });
      return;
    }
    setState(() {});
  }

  void _nudge(double dx) =>
      setState(() => _game.movePlayer(_game.playerX + dx));

  @override
  Widget build(BuildContext context) {
    return MinigameFrame(
      title: Ko.catchTitle,
      child: switch (_phase) {
        _Phase.intro => MinigameIntro(
          icon: Icons.restaurant,
          text: Ko.catchIntro,
          onStart: _start,
        ),
        _Phase.playing => _play(context),
        _Phase.result => MinigameResultView(
          lines: [Ko.catchResultLine(_game.score)],
          outcome: _outcome!,
        ),
      },
    );
  }

  Widget _play(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pet = c.pet!;
    final secs = (_game.remainingMs / 1000).ceil();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              liveRegion: false,
              child: Text(Ko.catchScore(_game.score), style: t.titleMedium),
            ),
            Text(Ko.catchTimeLeft(secs), style: t.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: 1 - _game.progress,
            minHeight: 10,
            color: PetoryColors.tired,
            backgroundColor: PetoryColors.card,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              void move(Offset p) => setState(() => _game.movePlayer(p.dx / w));
              return GestureDetector(
                key: const Key('catch-stage'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => move(d.localPosition),
                onPanUpdate: (d) => move(d.localPosition),
                onTapDown: (d) => move(d.localPosition),
                child: Container(
                  decoration: BoxDecoration(
                    color: PetoryColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PetoryColors.text, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: h * 0.2,
                        child: const ColoredBox(color: Color(0xFFBFE7D0)),
                      ),
                      for (final it in _game.items)
                        Positioned(
                          left: it.x * w - _itemSize / 2,
                          top: it.y * h - _itemSize / 2,
                          child: PixelSprite(
                            _spriteOf(it.kind),
                            size: _itemSize,
                          ),
                        ),
                      Positioned(
                        left: _game.playerX * w - _petSize / 2,
                        bottom: h * 0.02,
                        width: _petSize,
                        height: _petSize,
                        child: CustomPaint(
                          painter: PetPainter(
                            stage: pet.stage,
                            species: pet.species,
                            tier: pet.adultTier,
                            mood: PetMood.happy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(Ko.catchHint, style: t.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('catch-left'),
                onPressed: () => _nudge(-0.12),
                icon: const Icon(Icons.chevron_left),
                label: const Text(Ko.catchLeft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('catch-right'),
                onPressed: () => _nudge(0.12),
                icon: const Icon(Icons.chevron_right),
                label: const Text(Ko.catchRight),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Sprite _spriteOf(CatchKind k) => switch (k) {
    CatchKind.apple => Sprite.apple,
    CatchKind.cookie => Sprite.cookie,
    CatchKind.poop => Sprite.poop,
  };
}
