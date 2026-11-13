import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../l10n/ko.dart';

/// 부화 직후: 권한을 물을 수 있으면 안내 후 요청, iOS 미설치면 설치 안내.
Future<void> showPushPrompt(BuildContext context, GameController c) async {
  switch (c.pushStatus) {
    case PushStatus.canAsk:
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(Ko.pushAskTitle),
          content: const Text(Ko.pushAskBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(Ko.pushLater),
            ),
            // 이 버튼 탭이 브라우저가 요구하는 사용자 제스처
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(Ko.pushAllow),
            ),
          ],
        ),
      );
      if (ok == true) await c.enablePush();
    case PushStatus.needsInstall:
      await _installGuide(context);
    case PushStatus.disabled:
    case PushStatus.denied:
    case PushStatus.active:
      break;
  }
}

/// 설정에서 알림을 켰을 때 결과가 안내를 필요로 하면 보여 준다.
Future<void> explainPushStatus(BuildContext context, PushStatus st) async {
  switch (st) {
    case PushStatus.needsInstall:
      await _installGuide(context);
    case PushStatus.denied:
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text(Ko.pushDeniedNote),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(Ko.ok),
            ),
          ],
        ),
      );
    default:
      break;
  }
}

Future<void> _installGuide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text(Ko.pushInstallTitle),
    content: const Text(Ko.pushInstallBody),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(Ko.ok)),
    ],
  ),
);
