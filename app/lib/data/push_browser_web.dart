import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'push_browser.dart';
import 'push_client.dart';

PushBrowser createPushBrowser() => WebPushBrowser();

/// 실제 브라우저 구현 (package:web). 실브라우저 동작은 자동 테스트로 검증되지 않았다.
class WebPushBrowser implements PushBrowser {
  // Flutter 기본 SW(flutter_service_worker.js, 스코프 ./)와 충돌하지 않도록
  // 푸시 전용 SW 는 페이지를 제어하지 않는 별도 스코프에 등록한다(푸시 수신에는 스코프 일치가 필요 없음).
  static const _scriptUrl = 'push_sw.js';
  static const _scope = 'push-scope/';

  @override
  bool get supported {
    try {
      final w = web.window as JSObject;
      return w.has('Notification') &&
          w.has('PushManager') &&
          web.window.navigator.has('serviceWorker');
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isIos {
    final ua = web.window.navigator.userAgent;
    if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
    // iPadOS 는 Mac 으로 위장한다.
    return ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1;
  }

  @override
  bool get isStandalone {
    try {
      if (web.window.matchMedia('(display-mode: standalone)').matches) {
        return true;
      }
      final s = (web.window.navigator as JSObject).getProperty(
        'standalone'.toJS,
      );
      return s.isA<JSBoolean>() && (s as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  PushPermission get permission {
    if (!supported) return PushPermission.unsupported;
    return _map(web.Notification.permission);
  }

  PushPermission _map(String p) => switch (p) {
    'granted' => PushPermission.granted,
    'denied' => PushPermission.denied,
    _ => PushPermission.defaultState,
  };

  @override
  Future<PushPermission> requestPermission() async {
    if (!supported) return PushPermission.unsupported;
    final r = await web.Notification.requestPermission().toDart;
    return _map(r.toDart);
  }

  Future<web.ServiceWorkerRegistration> _register() async {
    final reg = await web.window.navigator.serviceWorker
        .register(_scriptUrl.toJS, web.RegistrationOptions(scope: _scope))
        .toDart;
    if (reg.active != null) return reg;
    // 설치/활성화 대기 (pushManager.subscribe 는 active 워커가 필요)
    final worker = reg.installing ?? reg.waiting;
    if (worker == null) return reg;
    final done = Completer<void>();
    void check(web.Event _) {
      if (worker.state == 'activated' && !done.isCompleted) done.complete();
    }

    worker.addEventListener('statechange', check.toJS);
    check(web.Event('statechange'));
    await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    return reg;
  }

  static Uint8List _b64urlDecode(String s) {
    final pad = '=' * ((4 - s.length % 4) % 4);
    return base64Url.decode(s + pad);
  }

  static String _b64url(JSArrayBuffer? buf) {
    if (buf == null) return '';
    return base64Url.encode(buf.toDart.asUint8List()).replaceAll('=', '');
  }

  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async {
    if (!supported || permission != PushPermission.granted) return null;
    final reg = await _register();
    var sub = await reg.pushManager.getSubscription().toDart;
    sub ??= await reg.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _b64urlDecode(vapidPublicKey).toJS,
          ),
        )
        .toDart;
    final p256dh = _b64url(sub.getKey('p256dh'));
    final auth = _b64url(sub.getKey('auth'));
    if (p256dh.isEmpty || auth.isEmpty) return null;
    return PushSubscriptionInfo(
      endpoint: sub.endpoint,
      p256dh: p256dh,
      auth: auth,
    );
  }

  @override
  Future<void> unsubscribe() async {
    if (!supported) return;
    final reg = await web.window.navigator.serviceWorker
        .getRegistration(_scope)
        .toDart;
    final sub = await reg?.pushManager.getSubscription().toDart;
    await sub?.unsubscribe().toDart;
  }
}
