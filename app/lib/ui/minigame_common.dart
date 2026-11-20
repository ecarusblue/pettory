import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../data/sfx.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'play_sfx.dart';
import 'theme.dart';

/// 결과를 행복에 적용한 결과. [error] 가 있으면 적용하지 못한 것이다.
class MinigameOutcome {
  const MinigameOutcome({
    required this.gain,
    required this.error,
    required this.happinessAfter,
  });
  final int gain;
  final CareError? error;
  final int happinessAfter;
}

/// 점수에서 구한 [gain] 을 컨트롤러에 한 번만 적용한다.
MinigameOutcome applyMinigameGain(GameController c, int gain) {
  final res = c.care(CareAction.minigame(gain));
  if (res.ok && gain > 0) playSfx(c, SfxKind.mgWin);
  return MinigameOutcome(
    gain: gain,
    error: res.ok ? null : res.error,
    happinessAfter: c.pet?.happiness ?? 0,
  );
}

/// 미니게임 공통 화면 틀: 제목 줄 + 가운데 정렬된 480폭 본문.
class MinigameFrame extends StatelessWidget {
  const MinigameFrame({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(title)),
        backgroundColor: PetoryColors.bg,
        foregroundColor: PetoryColors.text,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }
}

/// 시작 전 안내.
class MinigameIntro extends StatelessWidget {
  const MinigameIntro({
    super.key,
    required this.icon,
    required this.text,
    required this.onStart,
  });
  final IconData icon;
  final String text;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 72, color: PetoryColors.accent),
        const SizedBox(height: 16),
        Text(text, style: t.bodyLarge, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
          onPressed: onStart,
          child: const Text(Ko.mgStart),
        ),
      ],
    );
  }
}

/// 결과 화면: 요약 줄들 + 행복 증가(또는 적용 실패) + 홈으로 버튼.
class MinigameResultView extends StatelessWidget {
  const MinigameResultView({
    super.key,
    required this.lines,
    required this.outcome,
  });
  final List<String> lines;
  final MinigameOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final failed = outcome.error != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(Ko.mgResultTitle, style: t.titleLarge),
        ),
        const SizedBox(height: 12),
        for (final l in lines) Text(l, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: failed
              ? Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: PetoryColors.accent,
                    ),
                    Text(Ko.mgNotApplied, style: t.titleMedium),
                    Text(
                      Ko.careError(outcome.error!),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  children: [
                    Icon(
                      outcome.gain > 0 ? Icons.favorite : Icons.favorite_border,
                      size: 48,
                      color: PetoryColors.happy,
                    ),
                    Text(
                      outcome.gain > 0
                          ? Ko.mgHappinessGain(outcome.gain)
                          : Ko.mgGainNone,
                      style: t.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    Text(Ko.mgCurrentHappiness(outcome.happinessAfter)),
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
