import 'simulate.dart';
import 'time_util.dart';
import 'types.dart';

const int kProjectionMinutes = 72 * 60;
const int kEvolveLeadMinutes = 10;
const int kWakeDelayMinutes = 30;

/// 알림 예약 목록 (PRD 6장 / 설계서 7장). `simulate`를 72시간 앞으로
/// 투영해 이벤트 시각을 찾으므로 규칙이 이중화되지 않는다.
///
/// 이미 조건이 참인 상태(예: 지금 배고픔 1)는 "도달"이 이미 일어났으므로
/// 예약하지 않고, 앞으로 새로 도달하는 시점만 예약한다.
/// 취침 시간대에 걸린 시각은 기상 시각 + 30분으로 미룬다.
List<Scheduled> nextNotifications(PetState s, Settings cfg, int now) {
  if (s.left || s.stage == Stage.egg || !cfg.notifyEnabled) return const [];
  final (cur, _) = simulate(s, cfg, now);
  if (cur.left) return const [];
  final (_, ev) = simulate(cur, cfg, now + kProjectionMinutes);

  SimEvent? first(bool Function(SimEvent) test) {
    for (final e in ev) {
      if (e.at > now && test(e)) return e;
    }
    return null;
  }

  final out = <Scheduled>[];
  void add(NotifyType type, int? at, [String? dedupeKey]) {
    if (at == null) return;
    var fire = at;
    if (inSleepWindow(cfg, fire)) {
      fire = sleepWindowEnd(cfg, fire) + kWakeDelayMinutes;
    }
    out.add(Scheduled(type, fire, dedupeKey: dedupeKey));
  }

  add(NotifyType.hunger, first((e) => e.kind == SimEventKind.hungerLow)?.at);
  add(NotifyType.poop, first((e) => e.kind == SimEventKind.poopPile)?.at);
  // dedupeKey (설계서 7장): 아픔은 "아픔이 시작되는 분"(sickSince 와 같은 값),
  // 진화는 "다음 단계 번호 + 태어난 분(36진수)". 같은 상태에서 다시 계산해도 같은 키이고,
  // 환생한 새 펫의 같은 단계와는 다른 키라 서버의 1회 발송 제한에 걸리지 않는다.
  final sick = first((e) => e.kind == SimEventKind.gotSick);
  if (sick != null) add(NotifyType.sick, sick.at, 'sick:${sick.at}');
  final evo = first((e) => e.kind == SimEventKind.stageChanged);
  if (evo != null) {
    final lead = evo.at - kEvolveLeadMinutes;
    add(
      NotifyType.evolve,
      lead > now ? lead : now + 1,
      'stage:${evo.stage!.index}:${cur.birthAt.toRadixString(36)}',
    );
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out;
}
