import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../l10n/ko.dart';
import '../data/sfx.dart';
import 'push_prompt.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.showDevOptions = !kReleaseMode,
  });
  final GameController controller;

  /// 시간 가속은 개발용이므로 릴리스 빌드에서는 숨긴다.
  final bool showDevOptions;

  static const speeds = [1, 60, 720, 2016];

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pick(
    BuildContext context,
    int initial,
    void Function(int) set,
  ) async {
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (r != null) set(r.hour * 60 + r.minute);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        return Scaffold(
          appBar: AppBar(title: const Text(Ko.settings)),
          body: ListView(
            children: [
              ListTile(
                title: const Text(Ko.sleepStart),
                trailing: Text(_fmt(s.sleepStart)),
                onTap: () => _pick(
                  context,
                  s.sleepStart,
                  (v) => controller.updateSettings(s.copyWith(sleepStart: v)),
                ),
              ),
              ListTile(
                title: const Text(Ko.sleepEnd),
                trailing: Text(_fmt(s.sleepEnd)),
                onTap: () => _pick(
                  context,
                  s.sleepEnd,
                  (v) => controller.updateSettings(s.copyWith(sleepEnd: v)),
                ),
              ),
              SwitchListTile(
                title: const Text(Ko.notify),
                value: s.notifyEnabled,
                onChanged: (v) async {
                  final st = await controller.setNotifyEnabled(v);
                  if (v && context.mounted) {
                    await explainPushStatus(context, st);
                  }
                },
              ),
              SwitchListTile(
                title: const Text(Ko.sound),
                value: s.soundEnabled,
                onChanged: (v) {
                  controller.updateSettings(s.copyWith(soundEnabled: v));
                  if (v) sfx.play(SfxKind.tap); // 켠 순간 미리 들려 준다
                },
              ),
              ListTile(
                title: const Text(Ko.soundTest),
                subtitle: const Text(Ko.soundTestHint),
                leading: const Icon(Icons.volume_up_outlined),
                onTap: () => sfx.play(SfxKind.play),
              ),
              ListTile(
                title: const Text(Ko.resetData),
                leading: const Icon(Icons.delete_outline),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text(Ko.resetConfirmTitle),
                      content: const Text(Ko.resetConfirmBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text(Ko.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(Ko.reset),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await controller.resetAll();
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),
              if (controller.updater.supported)
                ListTile(
                  key: const Key('force-refresh'),
                  title: const Text(Ko.forceRefresh),
                  subtitle: const Text(Ko.forceRefreshHint),
                  leading: const Icon(Icons.refresh),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(Ko.forceRefreshConfirmTitle),
                        content: const Text(Ko.forceRefreshConfirmBody),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text(Ko.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(Ko.refresh),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await controller.updater.forceRefresh();
                  },
                ),
              if (showDevOptions)
                ExpansionTile(
                  title: const Text(Ko.devOptions),
                  children: [
                    const ListTile(
                      subtitle: Text(Ko.speedNote),
                      title: Text(Ko.speed),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final v in speeds)
                          ChoiceChip(
                            label: Text('×$v'),
                            selected: controller.speed == v,
                            onSelected: (_) => controller.setSpeed(v),
                          ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
