import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'dex_screen.dart';
import 'gauge.dart';
import 'minigame_screen.dart';
import 'catch_game_screen.dart';
import 'cups_game_screen.dart';
import 'memory_game_screen.dart';
import '../data/sfx.dart';
import 'pet_stage.dart';
import 'play_sfx.dart';
import 'poop_icon.dart';
import 'settings_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GameController get c => widget.controller;
  bool _showingEvolution = false;
  String? _reaction;
  int _reactionSerial = 0;

  void _maybeShowEvolution() {
    if (_showingEvolution || !c.hasPendingEvolutions) return;
    _showingEvolution = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final events = c.takePendingEvolutions();
      final pet = c.pet;
      if (events.isNotEmpty) playSfx(c, SfxKind.evolve);
      for (final e in events) {
        if (!mounted || pet == null) break;
        final msg = e.kind == SimEventKind.adultFormDecided
            ? Ko.adultDecided(pet.name, e.tier!)
            : Ko.evolved(pet.name, e.stage!);
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            content: Semantics(liveRegion: true, child: Text(msg)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(Ko.ok),
              ),
            ],
          ),
        );
      }
      _showingEvolution = false;
    });
  }

  void _do(CareAction a) {
    final r = c.care(a);
    playSfx(c, r.ok ? sfxForCare(a.kind) : SfxKind.error);
    if (r.ok) {
      setState(() {
        _reaction = Ko.careReaction(a.kind);
        _reactionSerial++;
      });
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Ko.careError(r.error!))));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 놀기: 한도/수면을 먼저 확인하고, 선택 시트(기본 / 미니게임)를 띄운다.
  Future<void> _onPlay() async {
    if (c.pet?.asleep ?? false) {
      playSfx(c, SfxKind.error);
      _snack(Ko.careError(CareError.asleep));
      return;
    }
    playSfx(c, SfxKind.button); // 놀이 선택창이 열리는 순간
    final choice = await showModalBottomSheet<_PlayChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PetoryColors.bg,
      builder: (_) => const _PlaySheet(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _PlayChoice.basic:
        _do(CareAction.play);
      case _PlayChoice.minigame:
        await _openGame((_) => MinigameScreen(controller: c));
      case _PlayChoice.catchGame:
        await _openGame((_) => CatchGameScreen(controller: c));
      case _PlayChoice.memory:
        await _openGame((_) => MemoryGameScreen(controller: c));
      case _PlayChoice.cups:
        await _openGame((_) => CupsGameScreen(controller: c));
    }
  }

  Future<void> _openGame(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  @override
  Widget build(BuildContext context) {
    final pet = c.pet;
    if (pet == null) return const SizedBox.shrink();
    _maybeShowEvolution();
    final t = Theme.of(context).textTheme;
    final stageText = pet.adultTier != null
        ? '${Ko.stageName(pet.stage)} · ${Ko.tierName(pet.adultTier!)}'
        : Ko.stageName(pet.stage);
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        backgroundColor: PetoryColors.card,
        onDestinationSelected: (i) {
          if (i == 1) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => DexScreen(controller: c)),
            );
          } else if (i == 2) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: c),
              ),
            );
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: Ko.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: Ko.navDex,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Ko.navSettings,
            tooltip: Ko.navSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        // Jua 에는 '·' 글리프가 없어 단계 표기는 본문 폰트로 쓴다.
                        child: Text.rich(
                          TextSpan(
                            text: pet.name,
                            style: t.titleLarge,
                            children: [
                              TextSpan(
                                text: '   $stageText',
                                style: t.titleMedium?.copyWith(
                                  fontFamily: 'NotoSansKR',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                PetStage(
                  pet: pet,
                  semanticsLabel:
                      '${pet.name}, $stageText'
                      '${pet.asleep ? ', ${Ko.sleepingNow}' : ''}'
                      '${pet.sick ? ', ${Ko.sickLabel}' : ''}',
                  onPet: () => playSfx(c, SfxKind.tap),
                  reaction: _reaction,
                  reactionSerial: _reactionSerial,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StatusChip(
                      icon: const PoopIcon(size: 24),
                      text: Ko.poopCount(pet.poop),
                      semanticsLabel: Ko.poopCount(pet.poop),
                      alert: pet.poop >= 2,
                    ),
                    const SizedBox(width: 12),
                    StatusChip(
                      icon: Icon(
                        pet.sick
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: pet.sick
                            ? PetoryColors.accent
                            : const Color(0xFF2E8B57),
                      ),
                      text: pet.sick ? Ko.sickLabel : Ko.healthy,
                      semanticsLabel:
                          '건강 상태: ${pet.sick ? Ko.sickLabel : '정상'}',
                      alert: pet.sick,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Gauge(
                  label: Ko.hunger,
                  value: pet.hunger,
                  color: PetoryColors.hunger,
                  filledIcon: Icons.circle,
                  emptyIcon: Icons.circle_outlined,
                ),
                const SizedBox(height: 8),
                Gauge(
                  label: Ko.happiness,
                  value: pet.happiness,
                  color: PetoryColors.happy,
                  filledIcon: Icons.favorite,
                  emptyIcon: Icons.favorite_border,
                ),
                const SizedBox(height: 8),
                Gauge(
                  label: Ko.fatigue,
                  value: pet.fatigue,
                  color: PetoryColors.tired,
                  filledIcon: Icons.square,
                  emptyIcon: Icons.square_outlined,
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                  children: [
                    _CareButton(
                      label: Ko.feed,
                      icon: Icons.rice_bowl,
                      onTap: () => _do(CareAction.feed),
                    ),
                    _CareButton(
                      label: Ko.snack,
                      icon: Icons.cookie,
                      onTap: () => _do(CareAction.snack),
                    ),
                    _CareButton(
                      label: Ko.play,
                      icon: Icons.sports_esports,
                      onTap: _onPlay,
                    ),
                    _CareButton(
                      label: Ko.cleanPoop,
                      icon: Icons.cleaning_services,
                      onTap: () => _do(CareAction.cleanPoop),
                    ),
                    pet.asleep
                        ? _CareButton(
                            label: Ko.wake,
                            icon: Icons.wb_sunny,
                            onTap: () => _do(CareAction.wake),
                          )
                        : _CareButton(
                            label: Ko.sleep,
                            icon: Icons.bedtime,
                            onTap: () => _do(CareAction.sleep),
                          ),
                    _CareButton(
                      label: Ko.medicine,
                      icon: Icons.medication,
                      onTap: () => _do(CareAction.medicine),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CareButton extends StatelessWidget {
  const _CareButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: PetoryColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PetoryColors.text, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: PetoryColors.text),
                const SizedBox(height: 4),
                Text(label, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PlayChoice { basic, minigame, catchGame, memory, cups }

class _PlaySheet extends StatelessWidget {
  const _PlaySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                Ko.playSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            _SheetOption(
              icon: Icons.toys,
              title: Ko.playBasic,
              desc: Ko.playBasicDesc,
              onTap: () => Navigator.of(context).pop(_PlayChoice.basic),
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.flash_on,
              title: Ko.playMinigame,
              desc: Ko.playMinigameDesc,
              onTap: () => Navigator.of(context).pop(_PlayChoice.minigame),
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.restaurant,
              title: Ko.playCatch,
              desc: Ko.playCatchDesc,
              onTap: () => Navigator.of(context).pop(_PlayChoice.catchGame),
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.style,
              title: Ko.playMemory,
              desc: Ko.playMemoryDesc,
              onTap: () => Navigator.of(context).pop(_PlayChoice.memory),
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.sports_bar,
              title: Ko.playCups,
              desc: Ko.playCupsDesc,
              onTap: () => Navigator.of(context).pop(_PlayChoice.cups),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title, $desc',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: PetoryColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PetoryColors.text, width: 2),
            ),
            child: Row(
              children: [
                Icon(icon, size: 28, color: PetoryColors.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: t.titleSmall),
                      Text(desc, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
