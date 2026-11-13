import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';
import 'theme.dart';

/// 알 3종 중 선택 + 이름. 탭 수: 알 선택 1 + 시작 1 (이름은 기본값 제공).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Species _selected = Species.eggA;
  final _name = TextEditingController(text: Ko.defaultName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    Ko.onboardTitle,
                    style: t.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Ko.onboardPickEgg,
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    for (final s in Species.values)
                      Expanded(
                        child: _EggChoice(
                          species: s,
                          selected: s == _selected,
                          onTap: () => setState(() => _selected = s),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: Ko.nameLabel,
                    hintText: Ko.nameHint,
                    filled: true,
                    fillColor: PetoryColors.card,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () =>
                      widget.controller.startEgg(_selected, _name.text),
                  child: const Text(Ko.start),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EggChoice extends StatelessWidget {
  const _EggChoice({
    required this.species,
    required this.selected,
    required this.onTap,
  });
  final Species species;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: Ko.eggSemantics(species, selected),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: PetoryColors.card,
            borderRadius: BorderRadius.circular(16),
            // 선택은 색 외에 두꺼운 테두리 + 체크 아이콘으로도 표시
            border: Border.all(
              color: selected ? PetoryColors.accent : PetoryColors.empty,
              width: selected ? 4 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 72,
                height: 80,
                child: CustomPaint(
                  painter: PetPainter(stage: Stage.egg, species: species),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Ko.eggName(species),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(
                height: 24,
                child: selected
                    ? const Icon(
                        Icons.check_circle,
                        color: PetoryColors.accent,
                        size: 20,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
