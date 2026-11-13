import '../domain/domain.dart';

/// 디버그용 가속 시계 앵커. 가상 시각 = virtualMs + (실제ms - realMs) × speed.
class ClockAnchor {
  const ClockAnchor({this.realMs = 0, this.virtualMs = 0, this.speed = 1});
  final int realMs;
  final int virtualMs;
  final int speed;

  int virtualNowMs(int realNowMs) => virtualMs + (realNowMs - realMs) * speed;

  Map<String, Object?> toJson() => {
    'realMs': realMs,
    'virtualMs': virtualMs,
    'speed': speed,
  };
  factory ClockAnchor.fromJson(Map<String, Object?> j) => ClockAnchor(
    realMs: (j['realMs'] as num?)?.toInt() ?? 0,
    virtualMs: (j['virtualMs'] as num?)?.toInt() ?? 0,
    speed: (j['speed'] as num?)?.toInt() ?? 1,
  );
}

/// 도감 항목. key 예: `eggA_baby`, `eggA_adult_excellent`.
class DexEntry {
  const DexEntry(this.key, this.unlockedAt);
  final String key;
  final int unlockedAt; // epoch 분
  Map<String, Object?> toJson() => {'key': key, 'unlockedAt': unlockedAt};
  factory DexEntry.fromJson(Map<String, Object?> j) => DexEntry(
    j['key'] as String? ?? '',
    (j['unlockedAt'] as num?)?.toInt() ?? 0,
  );
}

/// 추억 상자 항목 (떠난 캐릭터 기록).
class MemoryEntry {
  const MemoryEntry({
    required this.name,
    required this.species,
    required this.maxStage,
    required this.bornAt,
    required this.leftAt,
  });
  final String name;
  final Species species;
  final Stage maxStage;
  final int bornAt;
  final int leftAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'species': species.name,
    'maxStage': maxStage.name,
    'bornAt': bornAt,
    'leftAt': leftAt,
  };
  factory MemoryEntry.fromJson(Map<String, Object?> j) => MemoryEntry(
    name: j['name'] as String? ?? '',
    species: Species.values.firstWhere(
      (s) => s.name == j['species'],
      orElse: () => Species.eggA,
    ),
    maxStage: Stage.values.firstWhere(
      (s) => s.name == j['maxStage'],
      orElse: () => Stage.baby,
    ),
    bornAt: (j['bornAt'] as num?)?.toInt() ?? 0,
    leftAt: (j['leftAt'] as num?)?.toInt() ?? 0,
  );
}

/// 기기에 저장되는 전체 게임 데이터.
class GameSave {
  const GameSave({
    this.settings = const Settings(),
    this.pet,
    this.egg,
    this.dex = const [],
    this.memories = const [],
    this.clock = const ClockAnchor(),
  });

  final Settings settings;
  final PetState? pet;
  final Egg? egg;
  final List<DexEntry> dex;
  final List<MemoryEntry> memories;
  final ClockAnchor clock;

  static const int schemaVersion = 1;

  GameSave copyWith({
    Settings? settings,
    Object? pet = _unset,
    Object? egg = _unset,
    List<DexEntry>? dex,
    List<MemoryEntry>? memories,
    ClockAnchor? clock,
  }) => GameSave(
    settings: settings ?? this.settings,
    pet: identical(pet, _unset) ? this.pet : pet as PetState?,
    egg: identical(egg, _unset) ? this.egg : egg as Egg?,
    dex: dex ?? this.dex,
    memories: memories ?? this.memories,
    clock: clock ?? this.clock,
  );

  Map<String, Object?> toJson() => {
    'v': schemaVersion,
    'settings': settings.toJson(),
    'pet': pet?.toJson(),
    'egg': egg?.toJson(),
    'dex': [for (final d in dex) d.toJson()],
    'memories': [for (final m in memories) m.toJson()],
    'clock': clock.toJson(),
  };

  factory GameSave.fromJson(Map<String, Object?> j) {
    Map<String, Object?>? m(String k) =>
        (j[k] as Map?)?.cast<String, Object?>();
    List<T> list<T>(String k, T Function(Map<String, Object?>) f) => [
      for (final e in (j[k] as List<Object?>? ?? const []))
        f((e as Map).cast<String, Object?>()),
    ];
    return GameSave(
      settings: m('settings') == null
          ? const Settings()
          : Settings.fromJson(m('settings')!),
      pet: m('pet') == null ? null : PetState.fromJson(m('pet')!),
      egg: m('egg') == null ? null : Egg.fromJson(m('egg')!),
      dex: list('dex', DexEntry.fromJson),
      memories: list('memories', MemoryEntry.fromJson),
      clock: m('clock') == null
          ? const ClockAnchor()
          : ClockAnchor.fromJson(m('clock')!),
    );
  }
}

const Object _unset = Object();
