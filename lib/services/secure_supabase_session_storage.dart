import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:thestia/services/secure_storage_namespaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Audit H-6: Sichere Session-Persistenz für Supabase.
///
/// Das Supabase-SDK persistiert die Session (inkl. langlebigem
/// Refresh-Token) standardmäßig in KLARTEXT über SharedPreferences
/// (XML-Datei im App-Sandbox). Dieser Adapter ersetzt den Default durch
/// [FlutterSecureStorage] (Android Keystore / iOS Keychain), sodass
/// Access-/Refresh-Token nicht mehr im Klartext auf der Platte liegen.
///
/// Verwendung:
/// ```dart
/// Supabase.initialize(
///   ...
///   authOptions: FlutterAuthClientOptions(
///     localStorage: SecureSupabaseLocalStorage(),
///   ),
/// );
/// ```
class SecureSupabaseLocalStorage implements LocalStorage {
  SecureSupabaseLocalStorage({this.sessionKey});

  /// Schlüssel unter dem die Serialisierte Session abgelegt wird. Muss pro
  /// Supabase-Projekt eindeutig sein; das SDK nutzt konventionsgemäß
  /// `sb-<projekt-ref>-auth-token`. Wenn leer, wird dieser Konvention
  /// gefolgt (aus der Supabase-URL abgeleitet).
  final String? sessionKey;

  // flutter_secure_storage verschlüsselt über den Keystore; der Parameter
  // encryptedSharedPreferences ist veraltet und wird ignoriert (siehe
  // secure_storage.dart).
  // Eigener Namespace (secure_storage_namespaces.dart): die Session darf
  // nicht im selben Keystore-Alias wie die Token-Credentials liegen -
  // `resetOnError: true` (v11-Default) wuerde sonst beides loeschen.
  static const _platformOptions = AndroidOptions(
    storageNamespace: SecureNamespaces.session,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _platformOptions,
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: SecureNamespaces.session,
    ),
  );

  String? _key;
  bool? _hasSession;

  String get _sessionKey {
    if (_key != null) return _key!;
    if (sessionKey != null && sessionKey!.isNotEmpty) {
      _key = sessionKey;
      return _key!;
    }
    // Konvention des SDKs nachbilden: sb-<host-prefix>-auth-token.
    try {
      final host = Uri.parse(Supabase.instance.client.rest.url).host;
      _key = 'sb-${host.split('.').first}-auth-token';
    } catch (_) {
      _key = 'sb-auth-token';
    }
    return _key!;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    _hasSession ??= await _storage.read(key: _sessionKey) != null;
    return _hasSession ?? false;
  }

  @override
  Future<String?> accessToken() async {
    final value = await _storage.read(key: _sessionKey);
    _hasSession = value != null;
    return value;
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _sessionKey);
    _hasSession = false;
    if (kDebugMode) debugPrint('[SECURE_SESSION] Session entfernt.');
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _sessionKey, value: persistSessionString);
    _hasSession = true;
  }

  /// Löscht zusätzlich verwaiste PKCE-Code-Verifier-Einträge (Aufräumen).
  Future<void> purgeAll() async {
    await _storage.deleteAll();
    _hasSession = false;
  }
}
