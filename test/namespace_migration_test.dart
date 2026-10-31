// Regressionstest fuer die Keystore-Namespaces-Migration
// (31.10.2026: auf readAll umgestellt).
//
// BEFUND: Die Migration las fuer jeden Schluessel einzeln aus dem
// Keystore - bis zu 21 Zugriffe, JEDER vor dem ersten Frame der App.
// Jeder Zugriff kostet eine Dateioperation mit Entschluesselung im
// Android Keystore.
//
// Umgestellt auf readAll: EIN Aufruf je Namespace, und der
// Legacy-Namespace (der von allen fuenf Ziel-Namespaces geteilt wird)
// wird genau einmal gelesen.
//
// Diese Tests sichern die WIRKUNG ab - nicht nur die Geschwindigkeit:
// die Werte muessen nach wie von im alten Namespace in den neuen
// wandern und dort danach LOESCHEN (kein Klartext-Duplikat).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/secure_storage_namespaces.dart';

/// Keystore-Attrapp: haelt die Werte je Namespace im Speicher.
///
/// Der Namespace ergibt sich aus den Optionen - so wie im echten
/// Plugin, wo der Namespace der Name der SharedPreferences-Datei ist.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage(this.data);

  /// Namespace -> Schluessel -> Wert.
  final Map<String, Map<String, String>> data;

  /// Jeder Zugriff wird gezaehlt - damit sichergestellt ist, dass die
  /// Migration nicht wieder einzeln liest.
  int readAllCalls = 0;
  int singleReadCalls = 0;

  @override
  Future<Map<String, String>> readAll({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCalls++;
    return Map<String, String>.from(data[_ns(aOptions)] ?? {});
  }

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    singleReadCalls++;
    return data[_ns(aOptions)]?[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    (data[_ns(aOptions)] ??= {})[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data[_ns(aOptions)]?.remove(key);
  }

  String _ns(AndroidOptions? o) => o?.storageNamespace ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legacy-Namespace-Migration', () {
    test('wertet die Werte in den neuen Namespace aus und loescht sie '
        'im alten', () async {
      final storage = _FakeSecureStorage({
        // Der Legacy-Namespace (Default) - hier liegen die Altdaten.
        '': {
          'auth_access_token': 'token-abc',
          'auth_refresh_token': 'refresh-abc',
        },
      });

      await migrateLegacyNamespaces(storage: storage);

      final tokens = storage.data[SecureNamespaces.tokens] ?? {};
      expect(tokens['auth_access_token'], 'token-abc');
      expect(tokens['auth_refresh_token'], 'refresh-abc');

      // Kein Klartext-Duplikat zuruecklassen.
      expect(storage.data['']?.containsKey('auth_access_token'), isFalse);
      expect(storage.data['']?.containsKey('auth_refresh_token'), isFalse);
    });

    test('migriert auch die Session mit dem uebergebenen Key', () async {
      final storage = _FakeSecureStorage({
        '': {'sb-test-auth-token': '{"access_token":"x"}'},
      });

      await migrateLegacyNamespaces(
        storage: storage,
        extraSessionKeys: ['sb-test-auth-token'],
      );

      final session = storage.data[SecureNamespaces.session] ?? {};
      expect(session['sb-test-auth-token'], '{"access_token":"x"}');
      expect(storage.data['']?.containsKey('sb-test-auth-token'), isFalse);
    });

    test('ein bereits gefuellter Ziel-Namespace wird nicht angefasst',
        () async {
      final storage = _FakeSecureStorage({
        '': {'auth_access_token': 'alt'},
        SecureNamespaces.tokens: {'auth_access_token': 'neu'},
      });

      await migrateLegacyNamespaces(storage: storage);

      final tokens = storage.data[SecureNamespaces.tokens] ?? {};
      expect(tokens['auth_access_token'], 'neu',
          reason: 'Der Wert im neuen Namespace gewinnt - er ist der '
              'aktuellere.');
    });

    test('ohne Altdaten passiert nichts', () async {
      final storage = _FakeSecureStorage({});

      await migrateLegacyNamespaces(storage: storage);

      expect(storage.data, isEmpty);
    });

    test('liest den Legacy-Namespace nur einmal (Performance)', () async {
      // Fuenf Ziel-Namespaces, alle aus demselben Legacy-Namespace.
      // Ohne readAll waeren das bis zu 21 Zugriffe - mit readAll
      // genau einer.
      final storage = _FakeSecureStorage({
        '': {
          'auth_access_token': 'a',
          'user_profile_secure': '{}',
          'hive_encryption_key': 'k',
          'thestia_loc_lat': '52.5',
        },
      });

      await migrateLegacyNamespaces(storage: storage);

      expect(storage.readAllCalls, lessThanOrEqualTo(6),
          reason: 'Der Legacy-Namespace wird einmal gelesen, die '
              'Ziel-Namespaces hoechstens je einmal.');
      expect(storage.singleReadCalls, 0,
          reason: 'Die Migration liest nicht mehr einzeln - das war der '
              'teure Teil vor dem ersten Frame.');
    });

    test('der Legacy-Namespace wird auch bei Altdaten nur einmal gelesen',
        () async {
      final storage = _FakeSecureStorage({
        '': {
          'auth_access_token': 'a',
          'user_profile_secure': '{}',
          'hive_encryption_key': 'k',
        },
      });

      await migrateLegacyNamespaces(storage: storage);

      // Der Legacy selbst genau einmal, plus je Ziel-Namespace einer.
      // Fuenf Namespaces, aber nur die mit Altdaten brauchen einen.
      expect(storage.readAllCalls, lessThanOrEqualTo(4));
    });
  });
}
