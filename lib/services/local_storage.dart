import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraktion des lokalen, sicheren Speichers.
///
/// In dieser Demo wird [SharedPreferences] genutzt. Die Kapselung über
/// ein Interface erlaubt später einen einfachen Austausch (z. B. Encrypted
/// Storage / secure enclave) ohne Änderungen an den Providers.
abstract class LocalStorage {
  Future<void> saveString(String key, String value);
  Future<String?> getString(String key);
  Future<void> saveBool(String key, bool value);
  Future<bool?> getBool(String key);
  /// Speichert eine Ganzzahl (z. B. zuletzt gezeigter WhatsNew-Build).
  Future<void> saveInt(String key, int value);
  Future<int?> getInt(String key);
  Future<void> remove(String key);
}

/// Audit M-16: [LocalStorage]-Implementierung auf Basis von
/// [FlutterSecureStorage] (Keystore/Keychain).
///
/// Für sensible Präferenzen (Gender-/Beziehungsvorlieben = Art.-9-Daten,
/// Standort-Strings) ist der Klartext-[SharedPreferences] unzureichend.
class SecurePreferencesStorage implements LocalStorage {
  SecurePreferencesStorage();

  static const _androidOptions = AndroidOptions();
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  @override
  Future<void> saveString(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> getString(String key) => _storage.read(key: key);

  @override
  Future<void> saveBool(String key, bool value) =>
      _storage.write(key: key, value: value ? 'true' : 'false');

  @override
  Future<bool?> getBool(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    return raw == 'true';
  }

  @override
  Future<void> saveInt(String key, int value) =>
      _storage.write(key: key, value: '$value');

  @override
  Future<int?> getInt(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  @override
  Future<void> remove(String key) => _storage.delete(key: key);

  /// Migriert einen vorhandenen Klartext-Wert aus SharedPreferences in den
  /// sicheren Speicher und löscht die Klartext-Kopie.
  Future<void> migrateStringFrom(
    SharedPreferences prefs,
    String key,
  ) async {
    if (await getString(key) != null) return; // Bereits migriert.
    final legacy = prefs.getString(key);
    if (legacy != null && legacy.isNotEmpty) {
      await saveString(key, legacy);
      await prefs.remove(key);
      if (kDebugMode) debugPrint('[SecurePrefs] "$key" migriert.');
    }
  }
}

/// Standard-Implementierung auf Basis von SharedPreferences.
class SharedPreferencesStorage implements LocalStorage {
  SharedPreferencesStorage(this._prefs);
  final SharedPreferences _prefs;

  /// Ermöglicht Zugriff auf das zugrundeliegende [SharedPreferences]
  /// für Provider, die native Methoden benötigen (z. B. Mock-Auth).
  SharedPreferences get raw => _prefs;

  @override
  Future<void> saveString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<String?> getString(String key) => Future.value(_prefs.getString(key));

  @override
  Future<void> saveBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool?> getBool(String key) => Future.value(_prefs.getBool(key));

  @override
  Future<void> saveInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<int?> getInt(String key) => Future.value(_prefs.getInt(key));

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Provider für den lokalen Speicher (Singleton).
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError(
    'localStorageProvider muss vor Laufzeit mit override gesetzt werden.',
  );
});
