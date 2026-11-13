/// 푸시 설정. 빌드 때 `--dart-define` 으로 주입하며, 하나라도 비어 있으면
/// 푸시 기능 전체가 꺼지고 앱은 로컬로만 정상 동작한다.
class PushConfig {
  const PushConfig({this.baseUrl = '', this.vapidPublicKey = ''});

  factory PushConfig.fromEnvironment() => const PushConfig(
    baseUrl: String.fromEnvironment('PETORY_PUSH_BASE_URL'),
    vapidPublicKey: String.fromEnvironment('PETORY_VAPID_PUBLIC_KEY'),
  );

  final String baseUrl;
  final String vapidPublicKey;

  bool get enabled =>
      baseUrl.trim().isNotEmpty && vapidPublicKey.trim().isNotEmpty;
}
