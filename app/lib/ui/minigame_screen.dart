import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'theme.dart';

enum _Phase { intro, waiting, signal, roundDone, result }

/// 반응속도 미니게임 (FR-5). 시간원과 난수는 주입 가능 (테스트용).
class MinigameScreen extends StatefulWidget {
  MinigameScreen({
    super.key,
    required this.controller,
    ReactionClock? clock,
    Random? random,
  }) : clock = clock ?? StopwatchReactionClock(),
       random = random ?? Random();
  final GameController controller;
  final ReactionClock clock;
  final Random random;

  @override
  State<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends State<MinigameScreen> {
  GameController get c => widget.controller;
  _Phase _phase = _Phase.intro;
  final List<RoundResult> _rounds = [];
  Timer? _timer;
  int? _signalAt;
  int _gain = 0;
  CareError? _error;
  int _happinessAfter = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRound() {
    _timer?.cancel();
    _signalAt = null;
    setState(() => _phase = _Phase.waiting);
    _timer = Timer(Duration(milliseconds: signalDelayMs(widget.random)), () {
      if (!mounted) return;
      _signalAt = widget.clock.nowMs();
      setState(() => _phase = _Phase.signal);
      _timer = Timer(const Duration(milliseconds: kMinigameTimeoutMs), () {
        if (mounted && _phase == _Phase.signal) {
          _finishRound(const RoundResult.missed());
        }
      });
    });
  }

  void _onPad() {
    if (_phase != _Phase.waiting && _phase != _Phase.signal) return;
    _finishRound(
      judgeTap(
        signalAtMs: _phase == _Phase.signal ? _signalAt : null,
        tapAtMs: widget.clock.nowMs(),
      ),
    );
  }

  void _finishRound(RoundResult r) {
    _timer?.cancel();
    setState(() {
      _rounds.add(r);
      _phase = _Phase.roundDone;
    });
  }

  void _next() {
    if (_rounds.length < kMinigameRounds) {
      _startRound();
      return;
    }
    // 결과 확정: 점수 → 행복 증가량, 컨트롤러로 한 번만 적용
    final gain = gainForRounds(_rounds);
    final res = c.care(CareAction.minigame(gain));
    setState(() {
      _gain = gain;
      _error = res.ok ? null : res.error;
      _happinessAfter = c.pet?.happiness ?? 0;
      _phase = _Phase.result;
    });
  }

  String _roundText(RoundResult r) => switch (r.status) {
    RoundStatus.hit => Ko.mgHit(r.reactionMs!),
    RoundStatus.early => Ko.mgEarly,
    RoundStatus.missed => Ko.mgMissed,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: const Text(Ko.mgTitle)),
        backgroundColor: PetoryColors.bg,
        foregroundColor: PetoryColors.text,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_phase) {
                _Phase.intro => _intro(context),
                _Phase.waiting || _Phase.signal => _play(context),
                _Phase.roundDone => _roundDone(context),
                _Phase.result => _result(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.flash_on, size: 72, color: PetoryColors.accent),
        const SizedBox(height: 16),
        Text(
          Ko.mgIntro(kMinigameRounds),
          style: t.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          Ko.playsLeft(kDailyPlayLimit - c.playsToday, kDailyPlayLimit),
          style: t.titleSmall,
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
          onPressed: _startRound,
          child: const Text(Ko.mgStart),
        ),
      ],
    );
  }

  Widget _play(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final signal = _phase == _Phase.signal;
    // 색 외에 아이콘 모양 + 문구로도 구분한다.
    final bg = signal ? const Color(0xFFFFE08A) : PetoryColors.card;
    final icon = signal ? Icons.bolt : Icons.hourglass_empty;
    final text = signal ? Ko.mgSignal : Ko.mgWaiting;
    return Column(
      children: [
        Text(
          Ko.mgRound(_rounds.length + 1, kMinigameRounds),
          style: t.titleMedium,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Semantics(
            // 신호 변화를 스크린 리더에도 알린다 (라이브 리전).
            liveRegion: true,
            button: true,
            label: signal
                ? Ko.mgSignalAnnounce
                : '${Ko.mgWaiting} ${Ko.mgWaitingHint}',
            hint: Ko.mgPad,
            onTap: _onPad,
            excludeSemantics: true,
            child: Listener(
              key: const Key('reaction-pad'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _onPad(),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: PetoryColors.text,
                    width: signal ? 6 : 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 96, color: PetoryColors.text),
                    const SizedBox(height: 12),
                    Text(
                      text,
                      style: t.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!signal) ...[
                      const SizedBox(height: 8),
                      Text(Ko.mgWaitingHint, style: t.bodyMedium),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _roundDone(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _rounds.last;
    final last = _rounds.length >= kMinigameRounds;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(Ko.mgRound(_rounds.length, kMinigameRounds), style: t.titleMedium),
        const SizedBox(height: 16),
        Icon(
          r.failed ? Icons.close : Icons.check_circle_outline,
          size: 72,
          color: r.failed ? PetoryColors.accent : const Color(0xFF2E8B57),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _roundText(r),
            style: t.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
          onPressed: _next,
          child: Text(last ? Ko.mgShowResult : Ko.mgNextRound),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final avg = averageReactionMs(_rounds);
    final failedApply = _error != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(Ko.mgResultTitle, style: t.titleLarge),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _rounds.length; i++)
          Text(Ko.mgRoundLine(i + 1, _roundText(_rounds[i]))),
        const SizedBox(height: 12),
        Text(avg == null ? Ko.mgAverageNone : Ko.mgAverage(avg)),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: failedApply
              ? Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: PetoryColors.accent,
                    ),
                    Text(Ko.mgNotApplied, style: t.titleMedium),
                    Text(Ko.careError(_error!), textAlign: TextAlign.center),
                  ],
                )
              : Column(
                  children: [
                    Icon(
                      _gain > 0 ? Icons.favorite : Icons.favorite_border,
                      size: 48,
                      color: PetoryColors.happy,
                    ),
                    Text(
                      _gain > 0 ? Ko.mgHappinessGain(_gain) : Ko.mgGainNone,
                      style: t.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    Text(Ko.mgCurrentHappiness(_happinessAfter)),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(Ko.mgBackHome),
        ),
      ],
    );
  }
}
