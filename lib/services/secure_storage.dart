import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:thestia/services/secure_storage_namespaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sichere, verschlüsselte Speicherung von Authentifizierungs-Tokens.
///
/// DATENSCHUTZ/SICHERHEIT (Punkt 4):
/// Tokens (Access/Refresh) und andere Geheimnisse gehören NICHT in
/// [SharedPreferences] (Klartext, leicht auslesbar bei kompromittiertem
/// Gerät / unverschlüsseltem Backup). Wir nutzen [FlutterSecureStorage],
/// das unter Android auf den Keystore und unter iOS auf die Keychain
/// zurückgreift. Nicht-geheime UI-Einstellungen bleiben in
/// `local_storage.dart` (SharedPreferences).
///
/// Die Schlüssel liegen im verschlüsselten Keystore/Keychain.
/// `encryptedSharedPreferences: true` erzwingt zusätzlich AES-256 in der
/// Android-Keystore-gesicherten SharedPreferences-Datei.
class SecureTokenStore {
  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _userIdKey = 'auth_user_id';
  static const _demoCredentialsKey = 'demo_auth_credentials';

  // Security (Audit 2026-09-26): eigener Keystore-Namespace. Ohne ihn
  // teilten sich sechs Stores denselben Alias - und `resetOnError: true`
  // (v11-Default) loeschte beim ersten Dekrypt-Fehler ALLES (globaler
  // Logout). Werte werden einmalig per migrateLegacyNamespaces() verschoben.
  static const _androidOptions = AndroidOptions(
    // flutter_secure_storage verschlüsselt automatisch über den Keystore.
    // Der Parameter encryptedSharedPreferences ist veraltet und wird ignoriert.
    storageNamespace: SecureNamespaces.tokens,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    accountName: SecureNamespaces.tokens,
  );

  final FlutterSecureStorage _storage;

  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken, aOptions: _androidOptions, iOptions: _iOSOptions);
    await _storage.write(key: _refreshKey, value: refreshToken, aOptions: _androidOptions, iOptions: _iOSOptions);
    await _storage.write(key: _userIdKey, value: userId, aOptions: _androidOptions, iOptions: _iOSOptions);
  }

  Future<String?> get accessToken =>
      _storage.read(key: _accessKey, aOptions: _androidOptions, iOptions: _iOSOptions);
  Future<String?> get refreshToken =>
      _storage.read(key: _refreshKey, aOptions: _androidOptions, iOptions: _iOSOptions);
  Future<String?> get userId =>
      _storage.read(key: _userIdKey, aOptions: _androidOptions, iOptions: _iOSOptions);

  /// Demo-Modus: gesalzener Credential-Hash (`salt$hash`, siehe AuthService).
  /// Liegt bewusst IM Keystore/Keychain statt in SharedPreferences (M10).
  Future<String?> readDemoCredentials() => _storage.read(
        key: _demoCredentialsKey,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );

  Future<void> writeDemoCredentials(String value) => _storage.write(
        key: _demoCredentialsKey,
        value: value,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );

  Future<void> deleteDemoCredentials() => _storage.delete(
        key: _demoCredentialsKey,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );

  /// Löscht alle Tokens (Logout / Account-Löschung). Bewusst "best-effort":
  /// Bei Fehlern (z. B. gesperrtes Gerät) wird geloggt, aber nicht abgestürzt.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _accessKey, aOptions: _androidOptions, iOptions: _iOSOptions);
      await _storage.delete(key: _refreshKey, aOptions: _androidOptions, iOptions: _iOSOptions);
      await _storage.delete(key: _userIdKey, aOptions: _androidOptions, iOptions: _iOSOptions);
    } catch (e) {
      debugPrint('[SecureTokenStore] Löschen fehlgeschlagen: $e');
    }
  }
}

/// Provider für den [SecureTokenStore] (Singleton, direkt nutzbar).
final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore();
});

/// Verschlüsselte Speicherung des eigenen Profils (Audit M-Storage).
///
/// Das Profil enthält PII (Geburtsdatum, GPS-Koordinaten, Bio,
/// Persönlichkeitsergebnis) und gehört daher NICHT in den Klartext-
/// [SharedPreferences]. Derselbe Keystore-/Keychain-Weg wie
/// [SecureTokenStore].
class SecureProfileStore {
  static const _profileKey = 'user_profile_secure';

  // Eigener Namespace (siehe SecureTokenStore / secure_storage_namespaces.dart).
  static const _androidOptions = AndroidOptions(
    storageNamespace: SecureNamespaces.profile,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    accountName: SecureNamespaces.profile,
  );

  final FlutterSecureStorage _storage;

  SecureProfileStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> read() => _storage.read(
        key: _profileKey,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );

  Future<void> write(String json) => _storage.write(
        key: _profileKey,
        value: json,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );

  Future<void> delete() => _storage.delete(
        key: _profileKey,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );
}

/// Provider für den [SecureProfileStore].
final secureProfileStoreProvider = Provider<SecureProfileStore>((ref) {
  return SecureProfileStore();
});
