import 'package:material_ui/material_ui.dart';

import 'app/game_controller.dart';
import 'data/pet_repository.dart';
import 'data/push_browser.dart';
import 'data/push_client.dart';
import 'data/push_config.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // --dart-define=PETORY_PUSH_BASE_URL=... --dart-define=PETORY_VAPID_PUBLIC_KEY=...
  // 둘 중 하나라도 비어 있으면 푸시 전체가 꺼지고 앱은 로컬로만 동작한다.
  final cfg = PushConfig.fromEnvironment();
  final controller = GameController(
    repo: SharedPrefsPetRepository(),
    push: cfg.enabled
        ? HttpPushScheduleClient(baseUrl: cfg.baseUrl)
        : const NoopPushScheduleClient(),
    browser: createPushBrowser(),
    pushEnabled: cfg.enabled,
    vapidPublicKey: cfg.vapidPublicKey,
  );
  await controller.init();
  runApp(PetoryApp(controller: controller));
}
