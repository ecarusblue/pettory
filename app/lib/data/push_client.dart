import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/domain.dart';

/// Web Push 구독 정보 (브라우저 PushSubscription 의 서버 전송용 사본).
/// 캐릭터 이름 등 개인정보는 절대 담지 않는다.
class PushSubscriptionInfo {
  const PushSubscriptionInfo({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });
  final String endpoint;
  final String p256dh;
  final String auth;
}

/// 서버 오류 응답.
class PushHttpException implements Exception {
  PushHttpException(this.statusCode, [this.error]);
  final int statusCode;
  final String? error;
  @override
  String toString() => 'PushHttpException($statusCode, $error)';
}

/// 푸시 서버(server/API.md) 클라이언트. 모든 호출은 멱등.
abstract class PushScheduleClient {
  /// POST /subscribe. 앱 실행 때마다 호출해도 된다(만료 복구).
  Future<void> subscribe(PushSubscriptionInfo subscription, Settings settings);

  /// PUT /schedule. 미발송 예약 목록 전체 교체.
  Future<void> replaceSchedule(
    PushSubscriptionInfo subscription,
    List<Scheduled> schedule, {
    Settings? settings,
  });

  /// DELETE /subscribe. 알림을 끄거나 초기화할 때.
  Future<void> unsubscribe(PushSubscriptionInfo subscription);

  /// GET /time. 서버 UTC epoch 밀리초. 실패/오프라인이면 null.
  Future<int?> serverTimeMs();
}

/// 푸시가 설정되지 않았을 때(빌드에 URL/키가 없음) 쓰는 아무것도 안 하는 구현.
class NoopPushScheduleClient implements PushScheduleClient {
  const NoopPushScheduleClient();
  @override
  Future<void> subscribe(PushSubscriptionInfo s, Settings c) async {}
  @override
  Future<void> replaceSchedule(
    PushSubscriptionInfo s,
    List<Scheduled> l, {
    Settings? settings,
  }) async {}
  @override
  Future<void> unsubscribe(PushSubscriptionInfo s) async {}
  @override
  Future<int?> serverTimeMs() async => null;
}

/// 실제 HTTP 구현. [baseUrl] 예: `https://<project>.supabase.co/functions/v1`.
class HttpPushScheduleClient implements PushScheduleClient {
  HttpPushScheduleClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _base;
  final http.Client _client;
  final Duration timeout;

  Uri _u(String path) => Uri.parse('$_base$path');
  static const _json = {'content-type': 'application/json'};

  /// POST /subscribe 본문 (테스트에서 계약 확인용으로 공개).
  static Map<String, Object?> subscribeBody(
    PushSubscriptionInfo s,
    Settings c,
  ) => {
    'endpoint': s.endpoint,
    'keys': {'p256dh': s.p256dh, 'auth': s.auth},
    'sleepStart': c.sleepStart,
    'sleepEnd': c.sleepEnd,
    'tzOffsetMinutes': c.tzOffsetMinutes,
  };

  /// PUT /schedule 본문.
  static Map<String, Object?> scheduleBody(
    PushSubscriptionInfo s,
    List<Scheduled> list,
    Settings? c,
  ) => {
    'endpoint': s.endpoint,
    'auth': s.auth,
    if (c != null) ...{
      'sleepStart': c.sleepStart,
      'sleepEnd': c.sleepEnd,
      'tzOffsetMinutes': c.tzOffsetMinutes,
    },
    'items': [for (final e in list) e.toJson()],
  };

  Never _fail(http.Response r) {
    String? err;
    try {
      err = (jsonDecode(r.body) as Map)['error'] as String?;
    } catch (_) {}
    throw PushHttpException(r.statusCode, err);
  }

  @override
  Future<void> subscribe(PushSubscriptionInfo s, Settings c) async {
    final r = await _client
        .post(
          _u('/subscribe'),
          headers: _json,
          body: jsonEncode(subscribeBody(s, c)),
        )
        .timeout(timeout);
    if (r.statusCode != 200) _fail(r);
  }

  @override
  Future<void> replaceSchedule(
    PushSubscriptionInfo s,
    List<Scheduled> list, {
    Settings? settings,
  }) async {
    Future<http.Response> put() => _client
        .put(
          _u('/schedule'),
          headers: _json,
          body: jsonEncode(scheduleBody(s, list, settings)),
        )
        .timeout(timeout);
    var r = await put();
    if (r.statusCode == 404 && settings != null) {
      // 서버에서 구독이 사라짐(만료 등): 재등록 후 한 번 재시도
      await subscribe(s, settings);
      r = await put();
    }
    if (r.statusCode != 200) _fail(r);
  }

  @override
  Future<void> unsubscribe(PushSubscriptionInfo s) async {
    final r = await _client
        .delete(
          _u('/subscribe'),
          headers: _json,
          body: jsonEncode({'endpoint': s.endpoint, 'auth': s.auth}),
        )
        .timeout(timeout);
    if (r.statusCode != 200) _fail(r);
  }

  @override
  Future<int?> serverTimeMs() async {
    try {
      final r = await _client
          .get(_u('/time'), headers: const {'cache-control': 'no-store'})
          .timeout(timeout);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final ms = j['epochMs'];
      if (ms is int) return ms;
      if (ms is num) return ms.toInt();
      final now = j['now'];
      if (now is String) return DateTime.parse(now).millisecondsSinceEpoch;
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// 호출을 메모리에 기록하는 Fake (개발/테스트용).
class FakePushScheduleClient implements PushScheduleClient {
  final List<({PushSubscriptionInfo subscription, List<Scheduled> schedule})>
  calls = [];
  final List<PushSubscriptionInfo> subscribeCalls = [];
  final List<PushSubscriptionInfo> unsubscribeCalls = [];

  /// 서버 시각(밀리초) 제공자. null 이면 오프라인(실패)처럼 동작.
  int? Function()? serverTime;

  /// true 면 replaceSchedule 이 예외를 던진다(재시도 테스트용).
  bool failSchedule = false;

  /// 설정하면 subscribe/replaceSchedule 이 이 상태 코드로 실패(429 등).
  int? failStatus;

  /// 이 endpoint 로 subscribe 하면 409(subscription_conflict).
  final Set<String> conflictOnEndpoints = {};

  List<Scheduled>? get lastSchedule =>
      calls.isEmpty ? null : calls.last.schedule;

  @override
  Future<void> subscribe(PushSubscriptionInfo s, Settings c) async {
    if (failStatus != null) throw PushHttpException(failStatus!);
    if (conflictOnEndpoints.contains(s.endpoint)) {
      throw PushHttpException(409, 'subscription_conflict');
    }
    subscribeCalls.add(s);
  }

  @override
  Future<void> replaceSchedule(
    PushSubscriptionInfo subscription,
    List<Scheduled> schedule, {
    Settings? settings,
  }) async {
    if (failSchedule) throw PushHttpException(500);
    if (failStatus != null) throw PushHttpException(failStatus!);
    calls.add((subscription: subscription, schedule: List.of(schedule)));
  }

  @override
  Future<void> unsubscribe(PushSubscriptionInfo s) async {
    unsubscribeCalls.add(s);
  }

  @override
  Future<int?> serverTimeMs() async => serverTime?.call();
}
