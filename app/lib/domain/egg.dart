import 'types.dart';

const int kEggTapsToHatch = 10;
const int kEggAutoHatchMinutes = 3;

/// 알 탭 1회 반영. 10번째 탭 시각을 기록한다.
Egg tapEggAt(Egg e, int now) {
  if (e.tenthTapAt != null) return e;
  final taps = e.taps + 1;
  return Egg(
    species: e.species,
    name: e.name,
    startedAt: e.startedAt,
    taps: taps,
    tenthTapAt: taps >= kEggTapsToHatch ? now : null,
  );
}

/// 부화 시각(분). 아직이면 null. 10탭 시각과 3분 자동 중 빠른 쪽이며,
/// 앱을 닫아 두었어도 3분 시점으로 소급된다.
int? hatchMinute(Egg e, int now) {
  final auto = e.startedAt + kEggAutoHatchMinutes;
  final tap = e.tenthTapAt;
  final at = (tap != null && tap < auto) ? tap : auto;
  return now >= at ? at : null;
}
