import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';
import 'theme.dart';

/// 복귀 안내 화면 (FR-9). 경과 시간과 스탯 변화를 요약한다.
/// 떠난 경우에는 부드러운 문구로 안내하고, 확인하면 [LeftScreen] 으로 이어진다.
class AwayScreen extends StatelessWidget {
  const AwayScreen({
    super.key,
    required this.controller,
    required this.summary,
  });
  final GameController controller;
  final AwaySummary summary;

  @override
  Widget build(BuildContext context) {
    final pet = controller.pet;
    if (pet == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final s = summary;
    final elapsed = Ko.awayElapsed(s.elapsedMinutes);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: Opacity(
                        opacity: s.left ? 0.5 : 1,
                        child: CustomPaint(
                          painter: PetPainter(
                            stage: pet.stage,
                            species: pet.species,
                            tier: pet.adultTier,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      s.left
                          ? Ko.awayLeftTitle(pet.name)
                          : Ko.awayTitle(pet.name),
                      style: t.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (s.left) ...[
                    Text(
                      Ko.awayLeftBody(Ko.durationDH(s.elapsedMinutes)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Ko.awayLastState(_lastState(s)),
                      textAlign: TextAlign.center,
                      style: t.bodySmall,
                    ),
                  ] else ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        elapsed,
                        textAlign: TextAlign.center,
                        style: t.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: PetoryColors.card,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Ko.awayHeading, style: t.titleSmall),
                            const SizedBox(height: 8),
                            _Row(
                              icon: Icons.restaurant,
                              color: PetoryColors.hunger,
                              title: Ko.awayStat(
                                Ko.hunger,
                                s.hungerAfter - s.hungerDelta,
                                s.hungerAfter,
                              ),
                              note: _stepNote(s.hungerDelta),
                            ),
                            _Row(
                              icon: Icons.favorite,
                              color: PetoryColors.happy,
                              title: Ko.awayStat(
                                Ko.happiness,
                                s.happinessAfter - s.happinessDelta,
                                s.happinessAfter,
                              ),
                              note: _stepNote(s.happinessDelta),
                            ),
                            _Row(
                              icon: Icons.bedtime,
                              color: PetoryColors.tired,
                              title: Ko.awayStat(
                                Ko.fatigue,
                                s.fatigueAfter - s.fatigueDelta,
                                s.fatigueAfter,
                              ),
                              note: _stepNote(s.fatigueDelta),
                            ),
                            _Row(
                              icon: Icons.cleaning_services,
                              color: PetoryColors.text,
                              title: Ko.awayPoopNow(s.poopAfter),
                              note: s.poopDelta == 0
                                  ? Ko.awayUnchanged
                                  : (s.poopDelta > 0
                                        ? Ko.awayPoopUp(s.poopDelta)
                                        : Ko.awayPoopDown(-s.poopDelta)),
                            ),
                            _Row(
                              icon: s.sickAfter
                                  ? Icons.healing
                                  : Icons.health_and_safety,
                              color: s.sickAfter
                                  ? const Color(0xFFB3261E)
                                  : PetoryColors.text,
                              title: s.sickAfter ? Ko.sickLabel : Ko.healthy,
                              note: switch (s.sickChange) {
                                SickChange.started => Ko.awaySickStarted,
                                SickChange.recovered => Ko.awayRecovered,
                                SickChange.none =>
                                  s.sickAfter
                                      ? Ko.awaySickStill
                                      : Ko.awayHealthy,
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (s.hasEvolution) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        container: true,
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Ko.awayEvolutionCount(s.evolutions.length),
                                    style: t.titleSmall,
                                  ),
                                  const Text(Ko.awayEvolutionNote),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 52),
                    ),
                    onPressed: controller.dismissAway,
                    child: Text(s.left ? Ko.awayLeftConfirm : Ko.awayConfirm),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _stepNote(int d) =>
      d == 0 ? Ko.awayUnchanged : (d < 0 ? Ko.awayDown(-d) : Ko.awayUp(d));

  static String _lastState(AwaySummary s) =>
      '${Ko.hunger} ${s.hungerAfter}/4, ${Ko.happiness} ${s.happinessAfter}/4, '
      '${Ko.fatigue} ${s.fatigueAfter}/4, ${Ko.poopCount(s.poopAfter)}, '
      '${s.sickAfter ? Ko.sickLabel : Ko.healthy}';
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.note,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title, $note',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(note),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
