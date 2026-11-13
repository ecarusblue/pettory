import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'sfx.dart';

SfxPlayer createSfxPlayer() => WebSfxPlayer();

/// Web Audio 로 짧은 음을 합성해 재생한다. 브라우저의 자동 재생 제한 때문에
/// 컨텍스트는 첫 재생 요청(사용자 탭 안)에서 만들고 멈춰 있으면 다시 깨운다.
/// 실제 소리는 자동 테스트로 검증되지 않았다.
class WebSfxPlayer implements SfxPlayer {
  web.AudioContext? _ctx;
  bool _failed = false;
  web.HTMLAudioElement? _keepAlive;

  // 소리가 없는 아주 짧은 WAV. 아이폰의 무음 스위치를 우회하는 데 쓴다.
  static const _silentWav =
      'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA=';

  /// iOS 는 Web Audio 를 '벨소리' 채널로 취급해 무음 스위치가 켜져 있으면 소리가 안 난다.
  /// 오디오 세션을 '재생'으로 바꾸고(iOS 17+), 무음 <audio> 를 돌려(그 이전) 미디어 채널로 만든다.
  /// 사용자 탭 안에서 처음 한 번만 호출한다. 실기기 동작은 자동 테스트로 검증되지 않았다.
  void _unlockMediaChannel() {
    try {
      final session = (web.window.navigator as JSObject).getProperty(
        'audioSession'.toJS,
      );
      if (session != null && session.isA<JSObject>()) {
        (session as JSObject).setProperty('type'.toJS, 'playback'.toJS);
      }
    } catch (_) {}
    try {
      final a = web.document.createElement('audio') as web.HTMLAudioElement
        ..src = _silentWav
        ..loop = true;
      _keepAlive = a;
      a.play().toDart.catchError((_) => null);
    } catch (_) {}
  }

  static const _volume = 0.12; // 귀가 아프지 않게 낮게

  @override
  void play(SfxKind kind) {
    if (_failed) return;
    try {
      if (_ctx == null) _unlockMediaChannel();
      // 앱이 백그라운드에 갔다 오면 iOS 가 멈춰 둔 무음 재생을 다시 켠다.
      final keep = _keepAlive;
      if (keep != null && keep.paused) {
        keep.play().toDart.catchError((_) => null);
      }
      final ctx = _ctx ??= web.AudioContext();
      if (ctx.state == 'suspended') ctx.resume();
      final t0 = ctx.currentTime;
      for (final tone in tonesFor(kind)) {
        final osc = ctx.createOscillator()
          ..type = switch (tone.wave) {
            Wave.square => 'square',
            Wave.triangle => 'triangle',
            Wave.sawtooth => 'sawtooth',
          }
          ..frequency.value = tone.hz;
        final gain = ctx.createGain();
        final start = t0 + tone.at, end = start + tone.dur;
        // 짧게 올렸다가 끝에서 부드럽게 줄여 '틱' 소리를 막는다.
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(_volume, start + 0.008);
        gain.gain.linearRampToValueAtTime(0, end);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(start);
        osc.stop(end + 0.02);
      }
    } catch (_) {
      _failed = true; // 오디오를 못 쓰는 환경: 이후 요청은 조용히 무시
    }
  }
}
