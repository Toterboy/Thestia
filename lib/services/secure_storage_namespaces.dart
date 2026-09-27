/// Zentrale Keystore-Namespaces (Security-Audit 2026-09-26).
///
/// BEFUND: Sechs `FlutterSecureStorage`-Instanzen teilten sich denselben
/// Default-Namespace - also denselben Keystore-Alias und dieselbe
/// verschlüsselte Datei. In v11 ist `resetOnError: true` der Default: der
/// ERSTE Dekrypt-Fehler (z. B. `BadPaddingException` nach einem
/// OS-Schlüssel-Reset, siehe flutter_secure_storage#933) löscht dann den
/// GESAMTEN Namespace - also Auth-Tokens UND Supabase-Session UND Profil
/// UND Standort UND Signal-Schlüssel. Ein unbedachter Gerätewechsel war
/// damit ein globaler Logout.
///
/// LÖSUNG: eigener Namespace pro Store. Ein Fehler in einem Store
/// entleert nur noch diesen.
///
/// WICHTIG - MIGRATION: Ein anderer Namespace bedeutet anderer
/// Speicherort. Ohne die Migration hier unten wuerden alle bereits
/// gespeicherten Tokens beim Update unlesbar (Massen-Logout).
/// [migrateLegacyNamespaces] ist idempotent und verschiebt die Werte
/// einmalig aus dem Legacy-Namespace.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Namespaces (je Store genau einer).
class SecureNamespaces {
  SecureNamespaces._();

  /// Auth-Tokens (Access/Refresh/User-ID, Demo-Credentials).
  static const String tokens = 'thestia.tokens';

  /// Supabase-Session (inkl. Refresh-Token).
  static const String session = 'thestia.session';

  /// Gecachtes Nutzerprofil (PII: Geburtsdatum, Koordinaten, Bio).
  static const String profile = 'thestia.profile';

  /// Verifizierungs-Standort (Art. 9 DSGVO).
  static const String location = 'thestia.location';

  /// Hive-Schlüssel für die E2EE-Boxen (Signal-Keys, Ratchets).
  static const String signals = 'thestia.signals';

  /// Geräte-/sonstige Metadaten.
  static const String device = 'thestia.device';
}

/// Schlüssel je Legacy-Namespace (für die Migration).
const Map<String, List<String>> _legacyKeys = {
  SecureNamespaces.tokens: [
    'auth_access_token',
    'auth_refresh_token',
    'auth_user_id',
    'demo_auth_credentials',
    'auth_device_id',
  ],
  SecureNamespaces.profile: [
    'user_profile_secure',
    'seen_like_ids',
    'seen_match_ids',
    'seen_qr_ids',
  ],
  // v0.9.2 (Release-Blocker): Beide Namespaces wurden bei der Umstellung
// vergessen. `hive_encryption_key` ohne Migration bedeutet einen NEUEN
// Verschluesselungsschluessel - jede verschluesselte Box waere danach nicht
// mehr lesbar, bei Signal-Keys also Verlust der E2E-Identitaet.
// `session` bleibt hier leer, weil der Key projektabhaengig ist
// (`sb-<host-prefix>-auth-token`); er wird ueber `extraSessionKeys`
// dazugefuegt.
SecureNamespaces.session: [],
SecureNamespaces.signals: [
  'hive_encryption_key',
],
SecureNamespaces.location: [
    'thestia_loc_lat',
    'thestia_loc_lng',
    'thestia_loc_ts',
    'thestia_loc_acc',
    'verification_latitude',
    'verification_longitude',
    'verification_location_timestamp',
    'verification_location_accuracy',
    'thestia_loc_migrated_v1',
  ],
};

/// Migriert Werte aus dem Default-Namespace in die neuen Namespaces.
///
/// Idempotent: läuft nur, wenn der Ziel-Namespace LEER ist und im
/// Legacy-Namespace noch Werte liegen. Danach wird der Legacy-Eintrag
/// gelöscht, damit kein Klartext-Duplikat zurückbleibt.
///
/// Sicherheits-Fail-closed: Kopieren und Löschen passieren einzeln pro
/// Schlüssel; ein Fehler bricht ab, ohne etwas zu verlieren (der
/// Legacy-Wert bleibt dann noch da und der nächste Start versucht es
/// erneut).
///
/// Aufruf: VOR der ersten Nutzung der umgestellten Stores, z. B. direkt
/// nach `FlutterSecureStorage`-Initialisierung im Bootstrap.
Future<void> migrateLegacyNamespaces({
  /// Legacy-Keys, die nicht statisch in [_legacyKeys] stehen.
  ///
  /// Nötig für den Supabase-Session-Key: er folgt der SDK-Konvention
  /// `sb-<host-prefix>-auth-token` und ist damit projektabhängig. Ohne
  /// Übergabe wird die Session nicht migriert und jeder Bestandsnutzer
  /// wird beim Update abgemeldet.
  List<String> extraSessionKeys = const [],
  FlutterSecureStorage? storage,
  AndroidOptions legacyAndroid = const AndroidOptions(),
  IOSOptions legacyIOS = const IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
}) async {
  final store = storage ?? const FlutterSecureStorage();

  for (final entry in _legacyKeys.entries) {
    final namespace = entry.key;
    final keys = [
      ...entry.value,
      if (entry.key == SecureNamespaces.session) ...extraSessionKeys,
    ];
    final target = AndroidOptions(storageNamespace: namespace);
    final targetIOS = IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: namespace,
    );

    try {
      // Ist der Ziel-Namespace bereits gefuellt? Dann ist nichts zu tun -
      // die App hat die Werte schon in der neuen Struktur.
      var targetHasData = false;
      for (final key in keys) {
        if (await store.read(
              key: key,
              aOptions: target,
              iOptions: targetIOS,
            ) !=
            null) {
          targetHasData = true;
          break;
        }
      }
      if (targetHasData) continue;

      for (final key in keys) {
        final legacy = await store.read(
          key: key,
          aOptions: legacyAndroid,
          iOptions: legacyIOS,
        );
        if (legacy == null) continue;

        await store.write(
          key: key,
          value: legacy,
          aOptions: target,
          iOptions: targetIOS,
        );
        // Erst NACH erfolgreichem Schreiben loeschen.
        await store.delete(
          key: key,
          aOptions: legacyAndroid,
          iOptions: legacyIOS,
        );
        if (kDebugMode) {
          debugPrint('[SecureNamespaces] $namespace/$key migriert');
        }
      }
    } catch (e) {
      // Fail-closed: kein Datenverlust. Der Legacy-Wert bleibt erhalten,
      // der Versuch wird beim naechsten Start wiederholt.
      debugPrint('[SecureNamespaces] Migration $namespace fehlgeschlagen: $e');
    }
  }
}
