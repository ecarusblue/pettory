import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/game_save.dart';
import '../data/pet_repository.dart';
import '../data/push_browser.dart';
import '../data/push_browser_stub.dart';
import '../data/push_client.dart';
import '../domain/domain.dart';

enum GamePhase { loading, onboarding, hatching, home, left }

/// 푸시 알림 사용 가능 상태 (UI 분기용).
enum PushStatus {
  /// 빌드에 서버 URL/VAPID 키가 없거나 브라우저가 지원하지 않음. 푸시 기능 전체 꺼짐.
  disabled,

  /// iOS 인데 홈 화면에 설치하지 않음: 권한 요청 대신 설치 안내.
  needsInstall,

  /// 권한을 아직 묻지 않음.
  canAsk,

  /// 사용자가 권한을 거부함(브라우저 설정에서만 바꿀 수 있음).
  denied,

  /// 권한 허용됨(구독/예약 전송 가능).
  active,
}

/// 화면과 도메인을 잇는 컨트롤러. 시각은 [now] 함수로만 얻는다(주입 가능).
class GameController extends ChangeNotifier {
  GameController({
    required this.repo,
    required this.push,
    this.pushSubscription,
    this.browser = const UnsupportedPushBrowser(),
    this.pushEnabled = false,
    this.vapidPublicKey = '',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PetRepository repo;
  final PushScheduleClient push;
  PushSubscriptionInfo? pushSubscription;

  /// 브라우저 Push API (웹 전용 구현은 조건부 import).
  final PushBrowser browser;

  /// 서버 URL 과 VAPID 키가 모두 설정돼 푸시를 쓸 수 있는 빌드인가.
  final bool pushEnabled;
  final String vapidPublicKey;
  final DateTime Function() _now;

  // 서버 시각(BUG-7): 받은 시점의 서버 시각 + 이후 경과(단조 시계, 기기 시계 조작 영향 없음).
  int? _serverMsAtFetch;
  final Stopwatch _sinceFetch = Stopwatch();
  int _ticks = 0;
  bool _scheduleDirty = false;
  int _retryAtTick = 0; // 429 백오프: 이 틱 전에는 재시도하지 않는다

  GameSave _save = const GameSave();
  GameSave get data => _save;
  bool _loaded = false;
  Timer? _timer;
  final List<SimEvent> _pending = [];
  AwaySummary? _away;

  /// 확인 전의 복귀 요약(FR-9). 없으면 null. 시간 가속 중에는 만들지 않는다.
  AwaySummary? get away => _away;

  /// 복귀 화면 확인. 이후 홈에서 대기 중인 진화 연출이 이어진다.
  void dismissAway() {
    if (_away == null) return;
    _away = null;
    notifyListeners();
  }

  GamePhase get phase {
    if (!_loaded) return GamePhase.loading;
    final pet = _save.pet;
    if (pet != null) return pet.left ? GamePhase.left : GamePhase.home;
    return _save.egg != null ? GamePhase.hatching : GamePhase.onboarding;
  }

  PetState? get pet => _save.pet;
  Egg? get egg => _save.egg;
  Settings get settings => _save.settings;
  int get speed => _save.clock.speed;

  /// 현재 가상 시각(분).
  int get nowMinute {
    final realMs = _now().millisecondsSinceEpoch;
    final v = _save.clock.virtualNowMs(realMs) ~/ 60000;
    final last = _save.pet?.lastUpdatedAt;
    // 시간 가속(개발자 옵션) 중에는 기기-서버 비교가 의미 없으므로 생략
    final sn = (_serverMsAtFetch != null && speed == 1)
        ? (_serverMsAtFetch! + _sinceFetch.elapsedMilliseconds) ~/ 60000
        : null;
    final r = checkClock(last ?? 0, v, serverNow: sn);
    return (last != null && r < last) ? last : r;
  }

  /// GET /time 으로 서버 시각을 받아 둔다. 실패/오프라인이면 기존 값을 유지한다.
  Future<void> checkServerTime() async {
    if (!pushEnabled) return;
    try {
      final ms = await push.serverTimeMs();
      if (ms == null) return;
      _serverMsAtFetch = ms;
      _sinceFetch
        ..reset()
        ..start();
    } catch (_) {}
  }

  Future<void> init() async {
    final loaded = await repo.load();
    // 미래 시계 방어: 시작 시 서버 시각을 먼저 받는다(느리면 건너뛴다).
    try {
      await checkServerTime().timeout(const Duration(seconds: 2));
    } catch (_) {}
    final realMs = _now().millisecondsSinceEpoch;
    var save = loaded ?? const GameSave();
    if (loaded == null) {
      save = save.copyWith(
        clock: ClockAnchor(realMs: realMs, virtualMs: realMs, speed: 1),
      );
    }
    // 기기의 현재 시간대로 취침 시간대 해석을 갱신
    final tz = _now().timeZoneOffset.inMinutes;
    save = save.copyWith(settings: save.settings.copyWith(tzOffsetMinutes: tz));
    _save = save;
    _loaded = true;
    _advance();
    await _persist();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    notifyListeners();
    // 앱 실행마다 구독 재등록(서버가 만료로 지운 구독 복구)
    if (settings.notifyEnabled && pushStatus == PushStatus.active) {
      unawaited(_ensureSubscription());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 1초마다 호출: 시간 경과를 반영하고 변경 시 저장/알림.
  void refresh() {
    if (!_loaded) return;
    _ticks++;
    // 30분마다 서버 시각 재확인, 전송 실패는 1분마다 재시도
    if (pushEnabled && _ticks % 1800 == 0) unawaited(checkServerTime());
    if (_scheduleDirty && _ticks >= _retryAtTick && _ticks % 60 == 0) {
      unawaited(syncSchedule());
    }
    final changed = _advance();
    if (changed) {
      unawaited(_persist());
      notifyListeners();
    }
  }

  bool _advance() {
    final now = nowMinute;
    var changed = false;
    var egg = _save.egg;
    var pet = _save.pet;
    if (pet == null && egg != null) {
      final at = hatchMinute(egg, now);
      if (at != null) {
        pet = PetState.newborn(
          name: egg.name,
          species: egg.species,
          birthAt: at,
        );
        _save = _save.copyWith(
          egg: null,
          pet: pet,
          dex: _unlock(_save.dex, pet, at, Stage.baby),
        );
        changed = true;
      }
    }
    if (pet != null && !pet.left && now > pet.lastUpdatedAt) {
      final (next, events) = simulate(pet, settings, now);
      // 복귀 요약: 임계값 이상 비웠을 때만, 가속 모드가 아닐 때만 (시계 역행은 위 조건에서 제외)
      if (speed == 1 && isAwayLongEnough(now - pet.lastUpdatedAt)) {
        _away = buildAwaySummary(pet, next, events, nowMinute: now);
      }
      _save = _save.copyWith(pet: next);
      _handleEvents(next, events);
      changed = true;
    }
    return changed;
  }

  List<DexEntry> _unlock(
    List<DexEntry> dex,
    PetState p,
    int at,
    Stage st, [
    Tier? tier,
  ]) {
    final key = tier != null
        ? '${p.species.name}_${st.name}_${tier.name}'
        : '${p.species.name}_${st.name}';
    if (dex.any((d) => d.key == key)) return dex;
    return [...dex, DexEntry(key, at)];
  }

  void _handleEvents(PetState pet, List<SimEvent> events) {
    var dex = _save.dex;
    var memories = _save.memories;
    for (final e in events) {
      switch (e.kind) {
        case SimEventKind.stageChanged:
          if (e.stage != Stage.adult) dex = _unlock(dex, pet, e.at, e.stage!);
          _pending.add(e);
        case SimEventKind.adultFormDecided:
          dex = _unlock(dex, pet, e.at, Stage.adult, e.tier);
          _pending.add(e);
        case SimEventKind.left:
          if (!memories.any(
            (m) => m.leftAt == e.at && m.bornAt == pet.birthAt,
          )) {
            memories = [
              ...memories,
              MemoryEntry(
                name: pet.name,
                species: pet.species,
                maxStage: pet.stage,
                bornAt: pet.birthAt,
                leftAt: e.at,
              ),
            ];
          }
        default:
          break;
      }
    }
    _save = _save.copyWith(dex: dex, memories: memories);
  }

  /// 앱 종료 중 포함, 아직 연출하지 않은 진화 이벤트를 꺼낸다 (FR-6).
  List<SimEvent> takePendingEvolutions() {
    final out = List<SimEvent>.of(_pending);
    _pending.clear();
    return out;
  }

  bool get hasPendingEvolutions => _pending.isNotEmpty;

  // ---- 온보딩/부화 ----

  void startEgg(Species species, String name) {
    final n = name.trim().isEmpty ? '이름없음' : name.trim();
    _save = _save.copyWith(
      egg: Egg(species: species, name: n, startedAt: nowMinute),
    );
    unawaited(_persist());
    notifyListeners();
  }

  void tapEgg() {
    final e = _save.egg;
    if (e == null) return;
    _save = _save.copyWith(egg: tapEggAt(e, nowMinute));
    _advance();
    unawaited(_persist());
    notifyListeners();
  }

  // ---- 케어 ----

  /// 오늘(로컬 날짜) 놀아주기 횟수. 날짜가 바뀌었으면 0.
  int get playsToday {
    final p = _save.pet;
    if (p == null) return 0;
    final day = localDayOf(nowMinute, settings.tzOffsetMinutes);
    return p.dailyDay == day ? p.playCount : 0;
  }

  /// 하루 놀아주기 한도(기본 + 미니게임 합산)에 도달했는가.
  bool get playLimitReached => playsToday >= kDailyPlayLimit;

  CareResult care(CareAction action) {
    final p = _save.pet;
    if (p == null) return const CareResult.err(CareError.left, null, []);
    final now = nowMinute;
    final r = applyCare(p, settings, action, now);
    final st = r.state;
    if (st != null) {
      _save = _save.copyWith(pet: st);
      _handleEvents(st, r.events);
      unawaited(_persist());
      unawaited(syncSchedule());
      notifyListeners();
    }
    return r;
  }

  // ---- 설정 ----

  void updateSettings(Settings s) {
    // 설정 변경 전까지의 경과를 이전 설정으로 확정
    _advance();
    _save = _save.copyWith(settings: s);
    unawaited(_persist());
    unawaited(syncSchedule());
    notifyListeners();
  }

  /// 디버그 시간 가속. 현재 가상 시각에서 앵커를 다시 잡는다.
  void setSpeed(int speed) {
    final realMs = _now().millisecondsSinceEpoch;
    final virtualMs = _save.clock.virtualNowMs(realMs);
    _save = _save.copyWith(
      clock: ClockAnchor(realMs: realMs, virtualMs: virtualMs, speed: speed),
    );
    unawaited(_persist());
    notifyListeners();
  }

  /// 떠난 뒤 새 알로 다시 시작 (추억/도감은 유지).
  void restartAfterLeft() {
    _away = null;
    _save = _save.copyWith(pet: null, egg: null);
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _dropSubscription();
    final realMs = _now().millisecondsSinceEpoch;
    _save = GameSave(
      settings: _save.settings.copyWith(),
      clock: ClockAnchor(realMs: realMs, virtualMs: realMs, speed: 1),
    );
    _pending.clear();
    _away = null;
    await repo.clear();
    notifyListeners();
  }

  /// 앱이 백그라운드로 갈 때 등: 최신화 후 저장하고 알림 예약 재전송.
  Future<void> onBackground() async {
    _advance();
    await _persist();
    await syncSchedule();
  }

  /// 알림 예약 목록을 계산해 푸시 서버에 전체 교체 전송.
  Future<void> syncSchedule() async {
    final sub = pushSubscription;
    final p = _save.pet;
    if (sub == null || p == null) return;
    final list = nextNotifications(p, settings, nowMinute);
    try {
      await push.replaceSchedule(sub, list, settings: settings);
      _scheduleDirty = false;
    } catch (e) {
      // 네트워크 실패는 1분 뒤 또는 다음 재계산 시점에 다시 시도
      _scheduleDirty = true;
      _noteFailure(e);
    }
  }

  // ---- 푸시 권한/구독 ----

  PushStatus get pushStatus {
    if (!pushEnabled) return PushStatus.disabled;
    if (browser.needsInstall) return PushStatus.needsInstall;
    return switch (browser.permission) {
      PushPermission.unsupported => PushStatus.disabled,
      PushPermission.defaultState => PushStatus.canAsk,
      PushPermission.denied => PushStatus.denied,
      PushPermission.granted => PushStatus.active,
    };
  }

  /// 권한 요청(필요 시) 후 구독 + 서버 등록 + 예약 전송. 사용자 탭 안에서 호출한다.
  Future<PushStatus> enablePush() async {
    if (pushStatus == PushStatus.canAsk) {
      await browser.requestPermission();
    }
    if (pushStatus == PushStatus.active) await _ensureSubscription();
    notifyListeners();
    return pushStatus;
  }

  /// 429(rate_limited)면 5분 동안 재시도를 미룬다.
  void _noteFailure(Object e) {
    if (e is PushHttpException && e.statusCode == 429) {
      _retryAtTick = _ticks + 300;
    }
  }

  Future<void> _ensureSubscription() async {
    try {
      var sub = await browser.subscribe(vapidPublicKey);
      if (sub == null) return;
      pushSubscription = sub;
      try {
        await push.subscribe(sub, settings);
      } on PushHttpException catch (e) {
        if (e.statusCode != 409) rethrow;
        // subscription_conflict: 같은 endpoint 에 다른 auth. 브라우저 구독을 풀고 새로 구독해 재시도
        await browser.unsubscribe();
        sub = await browser.subscribe(vapidPublicKey);
        if (sub == null) {
          pushSubscription = null;
          return;
        }
        pushSubscription = sub;
        await push.subscribe(sub, settings);
      }
      await syncSchedule();
    } catch (e) {
      _scheduleDirty = true;
      _noteFailure(e);
    }
  }

  Future<void> _dropSubscription() async {
    final sub = pushSubscription;
    pushSubscription = null;
    _scheduleDirty = false;
    if (sub == null) return;
    try {
      await push.unsubscribe(sub);
    } catch (_) {}
    try {
      await browser.unsubscribe();
    } catch (_) {}
  }

  /// 설정의 '알림' 토글. 끄면 서버 구독 해제(DELETE), 켜면 권한/구독 재등록.
  /// 켤 수 없는 상태(설치 필요/거부)면 설정을 바꾸지 않고 그 상태를 돌려준다.
  Future<PushStatus> setNotifyEnabled(bool on) async {
    if (!on) {
      // 구독 참조를 먼저 비워 둬야 설정 변경이 일으키는 PUT 이 DELETE 뒤에 끼어들지 않는다.
      final dropping = _dropSubscription();
      updateSettings(settings.copyWith(notifyEnabled: false));
      await dropping;
      return pushStatus;
    }
    final st = pushStatus;
    if (st == PushStatus.needsInstall || st == PushStatus.denied) return st;
    updateSettings(settings.copyWith(notifyEnabled: true));
    if (st == PushStatus.disabled) return st;
    final r = await enablePush();
    if (r != PushStatus.active) {
      updateSettings(settings.copyWith(notifyEnabled: false)); // 권한을 못 받음
    }
    return r;
  }

  Future<void> _persist() => repo.save(_save);
}
