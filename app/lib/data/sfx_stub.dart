import 'sfx.dart';

SfxPlayer createSfxPlayer() => RecordingSfxPlayer();

/// 웹이 아닌 환경용: 소리를 내지 않고 재생 요청만 기록한다 (테스트에서 확인).
class RecordingSfxPlayer implements SfxPlayer {
  final List<SfxKind> played = [];
  @override
  void play(SfxKind kind) => played.add(kind);
}
