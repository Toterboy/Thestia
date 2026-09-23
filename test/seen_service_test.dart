import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/seen_service.dart';

class _MemoryStorage implements LocalStorage {
  final _map = <String, Object>{};

  @override
  Future<String?> getString(String key) async => _map[key] as String?;

  @override
  Future<void> saveString(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => _map[key] as bool?;

  @override
  Future<void> saveBool(String key, bool value) async {
    _map[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _map.remove(key);
  }

  @override
  Future<void> saveInt(String key, int value) async {
    _map[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => _map[key] is int
      ? _map[key] as int
      : (int.tryParse('${_map[key]}'));
}

void main() {
  group('Seen-Tracking (v0.9.1)', () {
    test('markieren + laden übersteht Neustart', () async {
      final storage = _MemoryStorage();
      final seen = SeenNotifier(storage);
      await seen.load();
      await seen.markLikesSeen([1, 2]);
      await seen.markMatchesSeen([42]);
      await seen.markQrSeen(['match_abc']);

      final fresh = SeenNotifier(storage);
      await fresh.load();
      expect(fresh.likeIds, containsAll([1, 2]));
      expect(fresh.matchIds, contains(42));
      expect(fresh.qrIds, contains('match_abc'));
    });

    test('leere Eingaben sind No-Ops ohne Versionstick', () async {
      final seen = SeenNotifier(_MemoryStorage());
      await seen.load();
      // Konstruktor-Ladung abwarten (läuft unawaited im Hintergrund).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = seen.state;
      await seen.markLikesSeen([]);
      await Future<void>.delayed(Duration.zero);
      expect(seen.state, before);
    });
  });
}
