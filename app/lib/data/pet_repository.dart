import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'game_save.dart';

/// 게임 데이터 저장소. 구현체를 바꿔도 UI/로직은 영향 없음.
abstract class PetRepository {
  /// 저장된 데이터가 없거나 손상됐으면 null.
  Future<GameSave?> load();
  Future<void> save(GameSave data);
  Future<void> clear();
}

/// shared_preferences 구현: 웹에서는 localStorage에 JSON 한 덩어리로 저장.
// 선택 이유: IndexedDB 래퍼(Hive/Isar) 의존성 없이 웹/모바일 모두 동작하고, 저장량이 수 KB라 충분.
class SharedPrefsPetRepository implements PetRepository {
  SharedPrefsPetRepository([SharedPreferences? prefs]) : _prefs = prefs;
  static const storageKey = 'petory.save.v1';
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<GameSave?> load() async {
    final raw = (await _p).getString(storageKey);
    if (raw == null) return null;
    try {
      return GameSave.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(GameSave data) async =>
      (await _p).setString(storageKey, jsonEncode(data.toJson()));

  @override
  Future<void> clear() async => (await _p).remove(storageKey);
}

/// 테스트/미리보기용 메모리 구현.
class InMemoryPetRepository implements PetRepository {
  GameSave? _data;
  @override
  Future<GameSave?> load() async => _data;
  @override
  Future<void> save(GameSave data) async {
    // 직렬화 왕복으로 실제 저장과 같은 제약을 보장
    _data = GameSave.fromJson(
      (jsonDecode(jsonEncode(data.toJson())) as Map).cast<String, Object?>(),
    );
  }

  @override
  Future<void> clear() async => _data = null;
}
