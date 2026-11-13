import 'sfx_stub.dart' if (dart.library.js_interop) 'sfx_web.dart' as impl;

/// 효과음 종류. 소리는 음원 파일 없이 짧은 음 몇 개를 합성해서 낸다.
enum SfxKind {
  tap,
  feed,
  snack,
  play,
  clean,
  sleep,
  wake,
  medicine,
  error,
  eggTap,
  hatch,
  evolve,
  mgHit,
  mgMiss,
  mgWin,
}

/// 음 하나: 높이(Hz), 시작 시각(초), 길이(초), 파형.
class Tone {
  const Tone(this.hz, this.at, this.dur, [this.wave = Wave.square]);
  final double hz;
  final double at;
  final double dur;
  final Wave wave;
}

enum Wave { square, triangle, sawtooth }

// 음높이 (옥타브 4~6)
const _g4 = 392.0, _a4 = 440.0, _c5 = 523.0, _d5 = 587.0, _e5 = 659.0;
const _g5 = 784.0, _a5 = 880.0, _c6 = 1047.0, _e6 = 1319.0;

/// 종류별 음 목록. 모두 0.5초 안팎으로 짧게, 졸린 소리는 삼각파로 부드럽게.
List<Tone> tonesFor(SfxKind k) => switch (k) {
  SfxKind.tap => const [
    Tone(_g5, 0, .07, Wave.triangle),
    Tone(_c6, .07, .1, Wave.triangle),
  ],
  SfxKind.feed => const [
    Tone(_c5, 0, .07),
    Tone(_a4, .09, .07),
    Tone(_c5, .18, .07),
    Tone(_a4, .27, .1),
  ],
  SfxKind.snack => const [
    Tone(_e6, 0, .05),
    Tone(988, .06, .05),
    Tone(_e6, .12, .07),
  ],
  SfxKind.play => const [
    Tone(_c5, 0, .08),
    Tone(_e5, .08, .08),
    Tone(_g5, .16, .08),
    Tone(_c6, .24, .16),
  ],
  SfxKind.clean => const [
    Tone(_c6, 0, .05, Wave.triangle),
    Tone(_a5, .05, .05, Wave.triangle),
    Tone(698, .1, .05, Wave.triangle),
    Tone(_c5, .15, .09, Wave.triangle),
  ],
  SfxKind.sleep => const [
    Tone(_e5, 0, .18, Wave.triangle),
    Tone(_c5, .2, .18, Wave.triangle),
    Tone(_g4, .4, .32, Wave.triangle),
  ],
  SfxKind.wake => const [
    Tone(_g4, 0, .1, Wave.triangle),
    Tone(_c5, .11, .1, Wave.triangle),
    Tone(_e5, .22, .2, Wave.triangle),
  ],
  SfxKind.medicine => const [
    Tone(_e5, 0, .1, Wave.triangle),
    Tone(_a5, .12, .2, Wave.triangle),
  ],
  SfxKind.error => const [
    Tone(196, 0, .12, Wave.sawtooth),
    Tone(147, .12, .18, Wave.sawtooth),
  ],
  SfxKind.eggTap => const [Tone(1175, 0, .04)],
  SfxKind.hatch => const [
    Tone(_c5, 0, .1),
    Tone(_e5, .1, .1),
    Tone(_g5, .2, .1),
    Tone(_c6, .3, .32),
  ],
  SfxKind.evolve => const [
    Tone(_g4, 0, .1),
    Tone(_c5, .1, .1),
    Tone(_e5, .2, .1),
    Tone(_g5, .3, .1),
    Tone(_c6, .4, .4),
  ],
  SfxKind.mgHit => const [Tone(_c6, 0, .06), Tone(_e6, .06, .1)],
  SfxKind.mgMiss => const [Tone(196, 0, .18, Wave.sawtooth)],
  SfxKind.mgWin => const [
    Tone(_d5, 0, .09),
    Tone(_g5, .1, .09),
    Tone(_c6, .2, .09),
    Tone(_e6, .3, .3),
  ],
};

/// 효과음 재생기. 웹에서는 Web Audio, 그 밖(테스트 등)에서는 재생 기록만 남긴다.
abstract class SfxPlayer {
  void play(SfxKind kind);
}

/// 앱 전체에서 쓰는 재생기.
final SfxPlayer sfx = impl.createSfxPlayer();
