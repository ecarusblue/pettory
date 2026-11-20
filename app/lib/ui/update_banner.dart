import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../l10n/ko.dart';
import 'theme.dart';

/// 새 버전이 내려받아졌을 때 홈 맨 위에 나오는 안내. '다시 시작'을 누르면 새 버전으로 바뀐다.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.controller});
  final GameController controller;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _busy = false;

  Future<void> _restart() async {
    setState(() => _busy = true);
    await widget.controller.updater.applyUpdate();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.updater.updateReady,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: PetoryColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PetoryColors.text, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.system_update_alt, color: PetoryColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Ko.updateReadyTitle, style: t.titleSmall),
                      Text(Ko.updateReadyBody, style: t.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('update-restart'),
                  onPressed: _busy ? null : _restart,
                  child: const Text(Ko.updateRestart),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
