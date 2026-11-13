import 'types.dart';

/// 하루 분 수.
const int kMinutesPerDay = 1440;

/// 로컬 시각(분, 0..1439). [t]는 UTC epoch 분.
int localMinuteOfDay(int t, int tzOffsetMinutes) =>
    (t + tzOffsetMinutes) % kMinutesPerDay;

/// 로컬 날짜 번호(자정 기준 일일 리셋용).
int localDayOf(int t, int tzOffsetMinutes) =>
    (t + tzOffsetMinutes) ~/ kMinutesPerDay;

/// [t]가 취침 시간대 안인지. sleepStart == sleepEnd면 시간대 없음.
bool inSleepWindow(Settings s, int t) {
  if (s.sleepStart == s.sleepEnd) return false;
  final m = localMinuteOfDay(t, s.tzOffsetMinutes);
  if (s.sleepStart < s.sleepEnd) {
    return m >= s.sleepStart && m < s.sleepEnd;
  }
  return m >= s.sleepStart || m < s.sleepEnd;
}

/// [t]가 취침 시간대 안일 때, 그 시간대가 끝나는 절대 분(기상 시각).
int sleepWindowEnd(Settings s, int t) {
  final m = localMinuteOfDay(t, s.tzOffsetMinutes);
  if (s.sleepStart < s.sleepEnd || m < s.sleepEnd) {
    return t + (s.sleepEnd - m);
  }
  return t + (kMinutesPerDay - m + s.sleepEnd);
}
