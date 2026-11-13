/// 순수 Dart 도메인 타입 (Flutter 의존 없음). 시각은 UTC epoch 분(int).
library;

enum Stage { egg, baby, child, teen, adult }

enum Species { eggA, eggB, eggC }

/// 성체 형태 등급.
enum Tier { excellent, normal, neglect }

enum SimEventKind {
  stageChanged,
  gotSick,
  poopSpawned,
  fellAsleep,
  woke,
  left,
  adultFormDecided,

  /// 배고픔이 1 이하로 내려간 순간 (알림 예약 투영용).
  hungerLow,

  /// 똥이 2개 이상이 된 순간 (알림 예약 투영용).
  poopPile,

  /// 설계서 목록용 예약 값. simulate는 발생시키지 않는다.
  notifyDue,
}

class SimEvent {
  const SimEvent(this.kind, this.at, {this.stage, this.tier});
  final SimEventKind kind;
  final int at;
  final Stage? stage;
  final Tier? tier;

  @override
  String toString() =>
      'SimEvent($kind@$at${stage != null ? ',$stage' : ''}'
      '${tier != null ? ',$tier' : ''})';
  @override
  bool operator ==(Object other) =>
      other is SimEvent &&
      other.kind == kind &&
      other.at == at &&
      other.stage == stage &&
      other.tier == tier;
  @override
  int get hashCode => Object.hash(kind, at, stage, tier);
}

class Settings {
  const Settings({
    this.sleepStart = 23 * 60,
    this.sleepEnd = 7 * 60,
    this.tzOffsetMinutes = 540,
    this.notifyEnabled = true,
    this.soundEnabled = true,
  });

  /// 취침 시작/종료: 로컬 시각의 분(0..1439). 같으면 취침 시간대 없음.
  final int sleepStart;
  final int sleepEnd;
  final int tzOffsetMinutes;
  final bool notifyEnabled;
  final bool soundEnabled;

  Settings copyWith({
    int? sleepStart,
    int? sleepEnd,
    int? tzOffsetMinutes,
    bool? notifyEnabled,
    bool? soundEnabled,
  }) => Settings(
    sleepStart: sleepStart ?? this.sleepStart,
    sleepEnd: sleepEnd ?? this.sleepEnd,
    tzOffsetMinutes: tzOffsetMinutes ?? this.tzOffsetMinutes,
    notifyEnabled: notifyEnabled ?? this.notifyEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
  );

  Map<String, Object?> toJson() => {
    'sleepStart': sleepStart,
    'sleepEnd': sleepEnd,
    'tzOffsetMinutes': tzOffsetMinutes,
    'notifyEnabled': notifyEnabled,
    'soundEnabled': soundEnabled,
  };

  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    return Settings(
      sleepStart: (j['sleepStart'] as num?)?.toInt() ?? d.sleepStart,
      sleepEnd: (j['sleepEnd'] as num?)?.toInt() ?? d.sleepEnd,
      tzOffsetMinutes:
          (j['tzOffsetMinutes'] as num?)?.toInt() ?? d.tzOffsetMinutes,
      notifyEnabled: j['notifyEnabled'] as bool? ?? d.notifyEnabled,
      soundEnabled: j['soundEnabled'] as bool? ?? d.soundEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.sleepStart == sleepStart &&
      other.sleepEnd == sleepEnd &&
      other.tzOffsetMinutes == tzOffsetMinutes &&
      other.notifyEnabled == notifyEnabled &&
      other.soundEnabled == soundEnabled;
  @override
  int get hashCode => Object.hash(
    sleepStart,
    sleepEnd,
    tzOffsetMinutes,
    notifyEnabled,
    soundEnabled,
  );
}

const Object _unset = Object();

/// 펫 상태 (불변). 누산기는 모두 정수.
///
/// 누산기 스케일: hungerAcc/happyAcc는 "감소율 0.5"를 2배 스케일한 정수.
/// 깨어 있으면 틱당 +2, 취침 시간대면 +1, 임계값은 배고픔 360(=180분),
/// 행복 480(=240분).
class PetState {
  const PetState({
    required this.name,
    required this.species,
    required this.stage,
    required this.birthAt,
    required this.lastUpdatedAt,
    this.adultTier,
    this.hunger = 4,
    this.happiness = 4,
    this.fatigue = 0,
    this.poop = 0,
    this.sick = false,
    this.sickSince,
    this.sleeping = false,
    this.asleep = false,
    this.awakeUntil,
    this.hungerAcc = 0,
    this.happyAcc = 0,
    this.fatigueAcc = 0,
    this.sleepAcc = 0,
    this.poopQueue = const [],
    this.hungerZeroSince,
    this.poop3Since,
    this.careSampleSum8 = 0,
    this.careSampleCount = 0,
    required this.lastSampleAt,
    this.left = false,
    this.leftAt,
    this.dailyDay = -1,
    this.playCount = 0,
    this.medicineCount = 0,
  });

  /// 부화 직후 상태. [birthAt]은 부화 시각(분).
  factory PetState.newborn({
    required String name,
    required Species species,
    required int birthAt,
  }) => PetState(
    name: name,
    species: species,
    stage: Stage.baby,
    birthAt: birthAt,
    lastUpdatedAt: birthAt,
    lastSampleAt: birthAt,
  );

  final String name;
  final Species species;
  final Stage stage;
  final Tier? adultTier; // 7일 시점에 확정
  final int birthAt;
  final int lastUpdatedAt;

  final int hunger; // 0..4
  final int happiness; // 0..4
  final int fatigue; // 0..4
  final int poop; // 0..3
  final bool sick;
  final int? sickSince;

  /// 수동 수면 플래그 (재우기). 피로 0이 되면 자동으로 false.
  final bool sleeping;

  /// 실효 수면 상태 (수동 수면 또는 취침 시간대). 이벤트 발생용 캐시.
  final bool asleep;

  /// 취침 시간대 중 수동 기상했을 때, 이 시각까지 시간대를 무시(정상 속도).
  final int? awakeUntil;

  final int hungerAcc;
  final int happyAcc;
  final int fatigueAcc;
  final int sleepAcc;
  final List<int> poopQueue; // 오름차순
  final int? hungerZeroSince;
  final int? poop3Since;

  /// careScore 샘플 합계 ×8 (정수), 개수.
  final int careSampleSum8;
  final int careSampleCount;
  final int lastSampleAt;

  final bool left;
  final int? leftAt;

  final int dailyDay; // 로컬 날짜 번호
  final int playCount;
  final int medicineCount;

  /// 파생 값: 청결은 별도 스탯 없이 똥 개수에서 계산한다.
  double get hygiene => 1 - poop / 3;

  PetState copyWith({
    String? name,
    Species? species,
    Stage? stage,
    Object? adultTier = _unset,
    int? birthAt,
    int? lastUpdatedAt,
    int? hunger,
    int? happiness,
    int? fatigue,
    int? poop,
    bool? sick,
    Object? sickSince = _unset,
    bool? sleeping,
    bool? asleep,
    Object? awakeUntil = _unset,
    int? hungerAcc,
    int? happyAcc,
    int? fatigueAcc,
    int? sleepAcc,
    List<int>? poopQueue,
    Object? hungerZeroSince = _unset,
    Object? poop3Since = _unset,
    int? careSampleSum8,
    int? careSampleCount,
    int? lastSampleAt,
    bool? left,
    Object? leftAt = _unset,
    int? dailyDay,
    int? playCount,
    int? medicineCount,
  }) => PetState(
    name: name ?? this.name,
    species: species ?? this.species,
    stage: stage ?? this.stage,
    adultTier: identical(adultTier, _unset)
        ? this.adultTier
        : adultTier as Tier?,
    birthAt: birthAt ?? this.birthAt,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    hunger: hunger ?? this.hunger,
    happiness: happiness ?? this.happiness,
    fatigue: fatigue ?? this.fatigue,
    poop: poop ?? this.poop,
    sick: sick ?? this.sick,
    sickSince: identical(sickSince, _unset)
        ? this.sickSince
        : sickSince as int?,
    sleeping: sleeping ?? this.sleeping,
    asleep: asleep ?? this.asleep,
    awakeUntil: identical(awakeUntil, _unset)
        ? this.awakeUntil
        : awakeUntil as int?,
    hungerAcc: hungerAcc ?? this.hungerAcc,
    happyAcc: happyAcc ?? this.happyAcc,
    fatigueAcc: fatigueAcc ?? this.fatigueAcc,
    sleepAcc: sleepAcc ?? this.sleepAcc,
    poopQueue: poopQueue ?? this.poopQueue,
    hungerZeroSince: identical(hungerZeroSince, _unset)
        ? this.hungerZeroSince
        : hungerZeroSince as int?,
    poop3Since: identical(poop3Since, _unset)
        ? this.poop3Since
        : poop3Since as int?,
    careSampleSum8: careSampleSum8 ?? this.careSampleSum8,
    careSampleCount: careSampleCount ?? this.careSampleCount,
    lastSampleAt: lastSampleAt ?? this.lastSampleAt,
    left: left ?? this.left,
    leftAt: identical(leftAt, _unset) ? this.leftAt : leftAt as int?,
    dailyDay: dailyDay ?? this.dailyDay,
    playCount: playCount ?? this.playCount,
    medicineCount: medicineCount ?? this.medicineCount,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'species': species.name,
    'stage': stage.name,
    'adultTier': adultTier?.name,
    'birthAt': birthAt,
    'lastUpdatedAt': lastUpdatedAt,
    'hunger': hunger,
    'happiness': happiness,
    'fatigue': fatigue,
    'poop': poop,
    'sick': sick,
    'sickSince': sickSince,
    'sleeping': sleeping,
    'asleep': asleep,
    'awakeUntil': awakeUntil,
    'hungerAcc': hungerAcc,
    'happyAcc': happyAcc,
    'fatigueAcc': fatigueAcc,
    'sleepAcc': sleepAcc,
    'poopQueue': poopQueue,
    'hungerZeroSince': hungerZeroSince,
    'poop3Since': poop3Since,
    'careSampleSum8': careSampleSum8,
    'careSampleCount': careSampleCount,
    'lastSampleAt': lastSampleAt,
    'left': left,
    'leftAt': leftAt,
    'dailyDay': dailyDay,
    'playCount': playCount,
    'medicineCount': medicineCount,
  };

  factory PetState.fromJson(Map<String, Object?> j) {
    int i(String k, [int d = 0]) => (j[k] as num?)?.toInt() ?? d;
    int? ni(String k) => (j[k] as num?)?.toInt();
    T byName<T extends Enum>(List<T> values, String? n, T d) {
      for (final v in values) {
        if (v.name == n) return v;
      }
      return d;
    }

    final tierName = j['adultTier'] as String?;
    return PetState(
      name: j['name'] as String? ?? '',
      species: byName(Species.values, j['species'] as String?, Species.eggA),
      stage: byName(Stage.values, j['stage'] as String?, Stage.baby),
      adultTier: tierName == null
          ? null
          : byName(Tier.values, tierName, Tier.normal),
      birthAt: i('birthAt'),
      lastUpdatedAt: i('lastUpdatedAt'),
      hunger: i('hunger', 4),
      happiness: i('happiness', 4),
      fatigue: i('fatigue'),
      poop: i('poop'),
      sick: j['sick'] as bool? ?? false,
      sickSince: ni('sickSince'),
      sleeping: j['sleeping'] as bool? ?? false,
      asleep: j['asleep'] as bool? ?? false,
      awakeUntil: ni('awakeUntil'),
      hungerAcc: i('hungerAcc'),
      happyAcc: i('happyAcc'),
      fatigueAcc: i('fatigueAcc'),
      sleepAcc: i('sleepAcc'),
      poopQueue: [
        for (final v in (j['poopQueue'] as List<Object?>? ?? const []))
          (v as num).toInt(),
      ],
      hungerZeroSince: ni('hungerZeroSince'),
      poop3Since: ni('poop3Since'),
      careSampleSum8: i('careSampleSum8'),
      careSampleCount: i('careSampleCount'),
      lastSampleAt: i('lastSampleAt', i('birthAt')),
      left: j['left'] as bool? ?? false,
      leftAt: ni('leftAt'),
      dailyDay: i('dailyDay', -1),
      playCount: i('playCount'),
      medicineCount: i('medicineCount'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PetState && _eq(other.toJson(), toJson());
  @override
  int get hashCode => Object.hashAll(
    toJson().values.map((v) => v is List ? Object.hashAll(v) : v),
  );

  static bool _eq(Map<String, Object?> a, Map<String, Object?> b) {
    for (final k in a.keys) {
      final x = a[k], y = b[k];
      if (x is List && y is List) {
        if (x.length != y.length) return false;
        for (var n = 0; n < x.length; n++) {
          if (x[n] != y[n]) return false;
        }
      } else if (x != y) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'PetState(${toJson()})';
}

/// 알림 종류. 이름은 서버 API(server/API.md)의 type 값과 같다.
enum NotifyType { hunger, poop, sick, evolve }

/// 푸시 서버에 보낼 예약 1건. fireAt은 UTC epoch 분.
///
/// [dedupeKey]는 sick/evolve 에서 필수(서버가 같은 키를 한 번만 발송).
/// 형식 `[A-Za-z0-9:_-]{1,32}`, 상태에서 결정적으로 만들며 이름 등 개인 정보 금지.
class Scheduled {
  const Scheduled(this.type, this.fireAt, {this.dedupeKey});
  final NotifyType type;
  final int fireAt;
  final String? dedupeKey;

  /// server/API.md (b) PUT /schedule 의 items 원소.
  /// fireAt 은 오프셋 포함 ISO-8601(UTC, `...Z`).
  Map<String, Object?> toJson() => {
    'type': type.name,
    'fireAt': DateTime.fromMillisecondsSinceEpoch(
      fireAt * 60000,
      isUtc: true,
    ).toIso8601String(),
    if (dedupeKey != null) 'dedupeKey': dedupeKey,
  };

  @override
  bool operator ==(Object other) =>
      other is Scheduled &&
      other.type == type &&
      other.fireAt == fireAt &&
      other.dedupeKey == dedupeKey;
  @override
  int get hashCode => Object.hash(type, fireAt, dedupeKey);
  @override
  String toString() =>
      'Scheduled(${type.name}@$fireAt${dedupeKey != null ? ',$dedupeKey' : ''})';
}

/// 알 단계 (부화 전). 로직 모듈은 부화 이후만 다루므로 별도 타입.
class Egg {
  const Egg({
    required this.species,
    required this.name,
    required this.startedAt,
    this.taps = 0,
    this.tenthTapAt,
  });
  final Species species;
  final String name;
  final int startedAt;
  final int taps;

  /// 10번째 탭 시각(분). 있으면 그 시각에 부화.
  final int? tenthTapAt;

  Map<String, Object?> toJson() => {
    'species': species.name,
    'name': name,
    'startedAt': startedAt,
    'taps': taps,
    'tenthTapAt': tenthTapAt,
  };

  factory Egg.fromJson(Map<String, Object?> j) => Egg(
    species: Species.values.firstWhere(
      (s) => s.name == j['species'],
      orElse: () => Species.eggA,
    ),
    name: j['name'] as String? ?? '',
    startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
    taps: (j['taps'] as num?)?.toInt() ?? 0,
    tenthTapAt: (j['tenthTapAt'] as num?)?.toInt(),
  );
}
