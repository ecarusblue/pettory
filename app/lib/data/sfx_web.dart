import 'package:web/web.dart' as web;

import 'sfx.dart';

SfxPlayer createSfxPlayer() => WebSfxPlayer();

/// Web Audio 로 짧은 음을 합성해 재생한다. 브라우저의 자동 재생 제한 때문에
/// 컨텍스트는 첫 재생 요청(사용자 탭 안)에서 만들고 멈춰 있으면 다시 깨운다.
/// 실제 소리는 자동 테스트로 검증되지 않았다.
class WebSfxPlayer implements SfxPlayer {
  web.AudioContext? _ctx;
  bool _failed = false;

  static const _volume = 0.12; // 귀가 아프지 않게 낮게

  @override
  void play(SfxKind kind) {
    if (_failed) return;
    try {
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
