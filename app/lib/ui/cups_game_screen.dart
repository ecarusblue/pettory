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

enum _Phase { intro, show, shuffling, pick, reveal, result }

/// 공을 보여 주는 시간.
const Duration kCupsShowBall = Duration(milliseconds: 900);

/// 숨은 공 찾기. 난수는 주입할 수 있다(테스트용).
class CupsGameScreen extends StatefulWidget {
  CupsGameScreen({super.key, required this.controller, Random? random})
    : random = random ?? Random();
  final GameController controller;
  final Random random;

  @override
  State<CupsGameScreen> createState() => _CupsGameScreenState();
}

class _CupsGameScreenState extends State<CupsGameScreen> {
  GameController get c => widget.controller;
  static const double _cupW = 72;

  _Phase _phase = _Phase.intro;
  int _round = 0; // 0부터
  int _correct = 0;
  late CupsRound _cfg;

  /// 자리 → 컵 번호.
  List<int> _order = [];
  Set<int> _lifted = {};
  bool? _lastRight;
  Timer? _timer;
  MinigameOutcome? _outcome;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRound() {
    _cfg = buildCupsRound(_round, widget.random);
    _order = List.generate(_cfg.cups, (i) => i);
    _lifted = {_cfg.ballCup};
    _lastRight = null;
    setState(() => _phase = _Phase.show);
    _timer?.cancel();
    _timer = Timer(kCupsShowBall, () {
      if (!mounted) return;
      setState(() {
        _lifted = {};
        _phase = _Phase.shuffling;
      });
      _doSwap(0);
    });
  }

  void _doSwap(int i) {
    if (!mounted) return;
    if (i >= _cfg.swaps.length) {
      setState(() => _phase = _Phase.pick);
      return;
    }
    final s = _cfg.swaps[i];
    setState(() {
      final tmp = _order[s.a];
      _order[s.a] = _order[s.b];
      _order[s.b] = tmp;
    });
    _timer = Timer(
      Duration(milliseconds: swapDurationMsForRound(_round)),
      () => _doSwap(i + 1),
    );
  }

  void _onCup(int cup) {
    if (_phase != _Phase.pick) return;
    final slot = _order.indexOf(cup);
    final right = _cfg.isCorrect(slot);
    playSfx(c, right ? SfxKind.mgHit : SfxKind.mgMiss);
    setState(() {
      if (right) _correct++;
      _lastRight = right;
      _lifted = {cup, _cfg.ballCup};
      _phase = _Phase.reveal;
    });
  }

  void _next() {
    if (_round + 1 < kCupsRounds) {
      _round++;
      _startRound();
      return;
    }
    final out = applyMinigameGain(c, gainForCups(_correct));
    setState(() {
      _outcome = out;
      _phase = _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MinigameFrame(
      title: Ko.cupsTitle,
      child: switch (_phase) {
        _Phase.intro => MinigameIntro(
          icon: Icons.sports_bar,
          text: Ko.cupsIntro(kCupsRounds),
          onStart: _startRound,
        ),
        _Phase.result => MinigameResultView(
          lines: [Ko.cupsResultLine(_correct, kCupsRounds)],
          outcome: _outcome!,
        ),
        _ => _play(context),
      },
    );
  }

  String get _say => switch (_phase) {
    _Phase.show => Ko.cupsWatch,
    _Phase.shuffling => Ko.cupsShuffling,
    _Phase.pick => Ko.cupsPick,
    _Phase.reveal => _lastRight == true ? Ko.cupsRight : Ko.cupsWrong,
    _ => '',
  };

  Widget _play(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final last = _round + 1 >= kCupsRounds;
    return Column(
      children: [
        Text(Ko.cupsRound(_round + 1, kCupsRounds), style: t.titleMedium),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PetoryColors.text, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final cupW = min(_cupW, w / _cfg.cups - 12);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 110,
                      child: const ColoredBox(color: Color(0xFFFFE3B8)),
                    ),
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _say,
                          style: t.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    for (var cup = 0; cup < _cfg.cups; cup++)
                      AnimatedPositioned(
                        key: Key('cup-$cup'),
                        duration: Duration(
                          milliseconds: (swapDurationMsForRound(_round) * 0.85)
                              .round(),
                        ),
                        curve: Curves.easeInOut,
                        // 탁자(높이 110) 위에 컵 바닥이 살짝 걸치도록 놓는다.
                        bottom: 70,
                        left:
                            (_order.indexOf(cup) + 0.5) * (w / _cfg.cups) -
                            cupW / 2,
                        width: cupW,
                        height: cupW * 1.1,
                        child: _cup(cup, cupW),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_phase == _Phase.reveal)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
            onPressed: _next,
            child: Text(last ? Ko.mgShowResult : Ko.cupsNext),
          )
        else
          const SizedBox(height: 56),
      ],
    );
  }

  Widget _cup(int cup, double w) {
    final lifted = _lifted.contains(cup);
    final hasBall = cup == _cfg.ballCup;
    return Semantics(
      button: _phase == _Phase.pick,
      label: Ko.cupsCupLabel(_order.indexOf(cup) + 1),
      excludeSemantics: true,
      onTap: () => _onCup(cup),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onCup(cup),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            if (hasBall)
              Positioned(
                bottom: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: lifted ? 1 : 0,
                  child: const PixelSprite(Sprite.ball, size: 36),
                ),
              ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              offset: lifted ? const Offset(0, -0.45) : Offset.zero,
              child: CupShape(size: w),
            ),
          ],
        ),
      ),
    );
  }
}
