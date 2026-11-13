/// 시간 무결성 (설계서 6장). 모든 값은 UTC epoch 분.
///
/// 과거로 돌린 경우 마지막 저장 시각을 반환(경과 0), 서버 시각이 있고
/// 기기 시각이 서버보다 [toleranceMinutes] 넘게 앞서면 서버 시각을 반환.
int checkClock(
  int lastSavedAt,
  int deviceNow, {
  int? serverNow,
  int toleranceMinutes = 60,
}) {
  if (deviceNow < lastSavedAt) return lastSavedAt;
  if (serverNow != null && deviceNow - serverNow > toleranceMinutes) {
    return serverNow;
  }
  return deviceNow;
}
