import 'push_client.dart';
import 'push_browser_stub.dart'
    if (dart.library.js_interop) 'push_browser_web.dart'
    as impl;

/// 브라우저 알림 권한 상태.
enum PushPermission { unsupported, defaultState, granted, denied }

/// 브라우저 Push API 추상화. 웹 전용 구현은 조건부 import 로 분리돼
/// VM(flutter test)에서는 stub 이 쓰인다.
abstract class PushBrowser {
  /// Notification/PushManager/ServiceWorker 를 모두 쓸 수 있는가.
  bool get supported;

  /// iOS(홈 화면에 설치해야만 웹 푸시 가능)인가.
  bool get isIos;

  /// 홈 화면에 설치된(standalone) 실행인가.
  bool get isStandalone;

  PushPermission get permission;

  /// 알림 권한 요청. 반드시 사용자 제스처(탭) 안에서 호출한다.
  Future<PushPermission> requestPermission();

  /// push_sw.js 를 등록하고 VAPID 키로 구독(이미 있으면 기존 구독)한다.
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey);

  /// 브라우저 구독 해제.
  Future<void> unsubscribe();
}

/// 현재 플랫폼의 구현을 만든다 (웹이 아니면 항상 지원 안 함).
PushBrowser createPushBrowser() => impl.createPushBrowser();

/// iOS 이면서 홈 화면 설치가 아니면 권한 요청 대신 설치 안내가 필요하다.
extension PushBrowserX on PushBrowser {
  bool get needsInstall => isIos && !isStandalone;
}
