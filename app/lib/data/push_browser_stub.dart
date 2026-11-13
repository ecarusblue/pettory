import 'push_browser.dart';
import 'push_client.dart';

PushBrowser createPushBrowser() => const UnsupportedPushBrowser();

/// 웹이 아닌 환경(VM 테스트, 모바일 앱 등)용: 아무것도 지원하지 않는다.
class UnsupportedPushBrowser implements PushBrowser {
  const UnsupportedPushBrowser();
  @override
  bool get supported => false;
  @override
  bool get isIos => false;
  @override
  bool get isStandalone => false;
  @override
  PushPermission get permission => PushPermission.unsupported;
  @override
  Future<PushPermission> requestPermission() async =>
      PushPermission.unsupported;
  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async => null;
  @override
  Future<void> unsubscribe() async {}
}
