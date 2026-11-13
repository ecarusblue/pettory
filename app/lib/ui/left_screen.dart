import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';

class LeftScreen extends StatelessWidget {
  const LeftScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final pet = controller.pet;
    if (pet == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Opacity(
                    opacity: 0.5,
                    child: CustomPaint(
                      painter: PetPainter(
                        stage: pet.stage,
                        species: pet.species,
                        tier: pet.adultTier,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    Ko.leftTitle(pet.name),
                    style: t.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(Ko.leftBody, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 52),
                  ),
                  onPressed: controller.restartAfterLeft,
                  child: const Text(Ko.newEgg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
