import 'package:flutter/foundation.dart';

import 'app_updater.dart';

AppUpdater createAppUpdater() => const UnsupportedAppUpdater();

/// 웹이 아닌 환경(VM 테스트, 모바일 앱 등)용: 새 버전이 생기지 않고 새로고침도 없다.
class UnsupportedAppUpdater implements AppUpdater {
  const UnsupportedAppUpdater();
  static final _never = ValueNotifier<bool>(false);
  @override
  ValueListenable<bool> get updateReady => _never;
  @override
  bool get supported => false;
  @override
  Future<void> applyUpdate() async {}
  @override
  Future<void> forceRefresh() async {}
}
