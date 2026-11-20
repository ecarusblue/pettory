import 'package:flutter/foundation.dart';

import 'app_updater_stub.dart'
    if (dart.library.js_interop) 'app_updater_web.dart'
    as impl;

/// 앱 셸(PWA) 새 버전 감지와 적용. 웹 구현은 index.html 의 `window.petoryUpdate` 를 쓴다.
abstract class AppUpdater {
  /// 새 버전이 내려받아져 적용을 기다리는가.
  ValueListenable<bool> get updateReady;

  /// 이 환경(설치형 웹앱)에서 업데이트/강제 새로고침을 쓸 수 있는가.
  bool get supported;

  /// 새 버전을 바로 적용하고 앱을 다시 불러온다.
  Future<void> applyUpdate();

  /// 앱 셸 캐시와 서비스 워커를 지우고 다시 불러온다. 저장된 펫 데이터와 알림 구독은 그대로다.
  Future<void> forceRefresh();
}

/// 현재 플랫폼의 구현을 만든다 (웹이 아니면 아무것도 지원하지 않음).
AppUpdater createAppUpdater() => impl.createAppUpdater();
