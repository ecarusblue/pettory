import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';

/// 임시 부화: 알 탭 10회 또는 3분 자동 (PRD FR-2).
class HatchingScreen extends StatefulWidget {
  const HatchingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<HatchingScreen> createState() => _HatchingScreenState();
}

class _HatchingScreenState extends State<HatchingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final egg = widget.controller.egg;
    if (egg == null) return const SizedBox.shrink();
    final left = (kEggTapsToHatch - egg.taps).clamp(0, kEggTapsToHatch);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(Ko.hatchTitle, style: t.headlineMedium),
              ),
              const SizedBox(height: 24),
              Semantics(
                button: true,
                label: Ko.hatchHint(left),
                excludeSemantics: true,
                onTap: _tap,
                child: GestureDetector(
                  onTap: _tap,
                  child: AnimatedBuilder(
                    animation: _wobble,
                    builder: (_, child) => Transform.rotate(
                      angle:
                          (0.5 - (_wobble.value - 0.5).abs()) *
                          0.4 *
                          (egg.taps.isEven ? 1 : -1),
                      child: child,
                    ),
                    child: SizedBox(
                      width: 200,
                      height: 220,
                      child: CustomPaint(
                        painter: PetPainter(
                          stage: Stage.egg,
                          species: egg.species,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(Ko.hatchHint(left), style: t.titleMedium),
              const SizedBox(height: 8),
              Text(Ko.hatchAuto, style: t.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  void _tap() {
    _wobble.forward(from: 0);
    widget.controller.tapEgg();
  }
}

/// 부화 직후 짧은 연출. 탭하면 건너뛰고, 3초 뒤 자동 종료 (5초 이내).
class HatchRevealScreen extends StatefulWidget {
  const HatchRevealScreen({
    super.key,
    required this.controller,
    required this.onDone,
  });
  final GameController controller;
  final VoidCallback onDone;

  @override
  State<HatchRevealScreen> createState() => _HatchRevealScreenState();
}

class _HatchRevealScreenState extends State<HatchRevealScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 3), _finish);
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.controller.pet;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(Ko.hatchedTitle, style: t.headlineMedium),
              ),
              const SizedBox(height: 24),
              if (pet != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: CustomPaint(
                      painter: PetPainter(
                        stage: pet.stage,
                        species: pet.species,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                onPressed: _finish,
                child: const Text(Ko.continueBtn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
