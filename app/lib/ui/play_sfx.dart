import '../app/game_controller.dart';
import '../data/sfx.dart';
import '../domain/domain.dart';

/// 설정에서 사운드가 켜져 있을 때만 효과음을 낸다.
void playSfx(GameController c, SfxKind kind) {
  if (c.settings.soundEnabled) sfx.play(kind);
}

/// 케어 종류에 맞는 효과음.
SfxKind sfxForCare(CareKind k) => switch (k) {
  CareKind.feed => SfxKind.feed,
  CareKind.snack => SfxKind.snack,
  CareKind.play || CareKind.minigame => SfxKind.play,
  CareKind.cleanPoop => SfxKind.clean,
  CareKind.sleep => SfxKind.sleep,
  CareKind.wake => SfxKind.wake,
  CareKind.medicine => SfxKind.medicine,
};
