import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'app_updater.dart';

AppUpdater createAppUpdater() => WebAppUpdater();

/// index.html 의 `window.petoryUpdate` 를 감싼 구현. 해당 객체가 없으면(서비스 워커 미지원 등)
/// 아무것도 지원하지 않는 것처럼 동작한다. 실브라우저 동작은 자동 테스트로 검증되지 않았다.
class WebAppUpdater implements AppUpdater {
  WebAppUpdater() {
    final api = _api;
    if (api == null) return;
    try {
      _ready.value = api.callMethod<JSBoolean>('isReady'.toJS).toDart;
      api.callMethod<JSAny?>('onReady'.toJS, (() => _ready.value = true).toJS);
    } catch (_) {}
  }

  final ValueNotifier<bool> _ready = ValueNotifier<bool>(false);

  JSObject? get _api {
    try {
      final v = (web.window as JSObject).getProperty<JSAny?>(
        'petoryUpdate'.toJS,
      );
      return v.isA<JSObject>() ? v as JSObject : null;
    } catch (_) {
      return null;
    }
  }

  @override
  ValueListenable<bool> get updateReady => _ready;

  @override
  bool get supported => _api != null;

  Future<void> _call(String name) async {
    final api = _api;
    if (api == null) return;
    try {
      final r = api.callMethod<JSAny?>(name.toJS);
      if (r.isA<JSPromise>()) await (r as JSPromise).toDart;
    } catch (_) {}
  }

  @override
  Future<void> applyUpdate() => _call('apply');

  @override
  Future<void> forceRefresh() => _call('force');
}
