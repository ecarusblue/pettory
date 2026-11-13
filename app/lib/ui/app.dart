import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../l10n/ko.dart';
import 'away_screen.dart';
import 'hatching_screen.dart';
import 'home_screen.dart';
import 'left_screen.dart';
import 'onboarding_screen.dart';
import 'push_prompt.dart';
import 'theme.dart';

class PetoryApp extends StatelessWidget {
  const PetoryApp({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Ko.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _Gate(controller: controller),
    );
  }
}

/// 단계(phase)에 따라 온보딩 → 부화 → 부화 연출 → 홈 → 떠남 화면을 고른다.
class _Gate extends StatefulWidget {
  const _Gate({required this.controller});
  final GameController controller;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> with WidgetsBindingObserver {
  GamePhase? _prev;
  bool _reveal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChange);
    _prev = widget.controller.phase;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final p = widget.controller.phase;
    if (_prev == GamePhase.hatching && p == GamePhase.home) {
      _reveal = true;
    }
    _prev = p;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.controller.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      widget.controller.refresh();
      unawaited(widget.controller.checkServerTime());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (_reveal && c.phase == GamePhase.home) {
          return HatchRevealScreen(
            controller: c,
            onDone: () {
              setState(() => _reveal = false);
              // 부화 완료 직후 알림 권한 요청 / iOS 설치 안내 (PRD 6장)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) showPushPrompt(context, c);
              });
            },
          );
        }
        final away = c.away;
        if (away != null &&
            (c.phase == GamePhase.home || c.phase == GamePhase.left)) {
          return AwayScreen(controller: c, summary: away);
        }
        return switch (c.phase) {
          GamePhase.loading => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          GamePhase.onboarding => OnboardingScreen(controller: c),
          GamePhase.hatching => HatchingScreen(controller: c),
          GamePhase.home => HomeScreen(controller: c),
          GamePhase.left => LeftScreen(controller: c),
        };
      },
    );
  }
}
