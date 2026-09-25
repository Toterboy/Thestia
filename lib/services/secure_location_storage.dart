import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Migriert den Klartext-Standort aus SharedPreferences in secure_storage.
///
/// Wird EINMAL beim App-Start ausgeführt. Nach erfolgreicher Migration liegen
/// die Werte in [FlutterSecureStorage] (Keystore/Keychain) und die Klartext-
/// Einträge in SharedPreferences sind gelöscht.
///
/// Wird der Helper nach erfolgreicher Migration erneut aufgerufen, ist er ein
/// No-Op (kein Hin-und-Her-Schreiben). Das verhindert unnötige Keystore-
/// Schreibvorgänge.
class SecureLocationStorage {
  /// Privater Named-Constructor — externe Aufrufer nutzen [instance].
  SecureLocationStorage._internal();

  /// Singleton-Instanz.
  static final SecureLocationStorage instance = SecureLocationStorage._internal();

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  /// Schlüssel im secure_storage (eigener Namespace, um Kollisionen zu
  /// vermeiden).
  static const _keyLat = 'thestia_loc_lat';
  static const _keyLng = 'thestia_loc_lng';
  static const _keyTs = 'thestia_loc_ts';
  static const _keyAcc = 'thestia_loc_acc';

  /// Alte SharedPreferences-Schlüssel (Klartext).
  static const _legacyKeyLat = 'verification_latitude';
  static const _legacyKeyLng = 'verification_longitude';
  static const _legacyKeyTs = 'verification_location_timestamp';
  static const _legacyKeyAcc = 'verification_location_accuracy';

  /// Marker, der signalisiert, dass die Migration durchgelaufen ist.
  static const _migrationMarker = 'thestia_loc_migrated_v1';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Liest einen Wert aus dem sicheren Speicher.
  Future<String?> read(String key) =>
      _secure.read(key: key, iOptions: _iosOptions);

  /// Schreibt einen Wert in den sicheren Speicher.
  Future<void> write(String key, String value) =>
      _secure.write(key: key, value: value, iOptions: _iosOptions);

  /// Löscht einen Wert im sicheren Speicher.
  Future<void> delete(String key) =>
      _secure.delete(key: key, iOptions: _iosOptions);

  /// Prüft, ob bereits ein Standort im sicheren Speicher liegt.
  Future<bool> hasLocation() async {
    final lat = await read(_keyLat);
    final lng = await read(_keyLng);
    return lat != null && lat.isNotEmpty && lng != null && lng.isNotEmpty;
  }

  /// Speichert den Verifizierungs-Standort im sicheren Speicher.
  Future<void> save({
    required String latitude,
    required String longitude,
    required String timestamp,
    required String accuracy,
  }) async {
    await write(_keyLat, latitude);
    await write(_keyLng, longitude);
    await write(_keyTs, timestamp);
    await write(_keyAcc, accuracy);
  }

  /// Liefert den gespeicherten Verifizierungs-Standort (oder null).
  Future<Map<String, String>?> readAll() async {
    final lat = await read(_keyLat);
    final lng = await read(_keyLng);
    if (lat == null || lng == null) return null;
    return {
      'latitude': lat,
      'longitude': lng,
      'timestamp': (await read(_keyTs)) ?? '',
      'accuracy': (await read(_keyAcc)) ?? '',
    };
  }

  /// Löscht den gespeicherten Verifizierungs-Standort.
  Future<void> clear() async {
    await delete(_keyLat);
    await delete(_keyLng);
    await delete(_keyTs);
    await delete(_keyAcc);
  }

  /// Führt die Migration Klartext → secure_storage einmalig durch.
  ///
  /// Idempotent: Nach erfolgreichem Lauf wird ein Marker gesetzt, weitere
  /// Aufrufe prüfen diesen Marker und sind dann No-Ops.
  ///
  /// Sollte VOR dem ersten Zugriff auf [read]/[hasLocation] aufgerufen werden.
  static Future<void> migrateFromSharedPreferences(SharedPreferences prefs) async {
    final storage = instance;

    // Bereits migriert? Dann nichts tun.
    if (prefs.getBool(_migrationMarker) == true) return;

    // Prüfe, ob Klartext-Werte existieren.
    final lat = prefs.getString(_legacyKeyLat);
    final lng = prefs.getString(_legacyKeyLng);

    if (lat != null && lng != null) {
      // Migration: Klartext in secure_storage übertragen.
      try {
        await storage.save(
          latitude: lat,
          longitude: lng,
          timestamp: prefs.getString(_legacyKeyTs) ?? '',
          accuracy: prefs.getString(_legacyKeyAcc) ?? '',
        );
        if (kDebugMode) {
          debugPrint('[SecureLocationStorage] Klartext-Standort erfolgreig migriert.');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SecureLocationStorage] Migration fehlgeschlagen: $e');
        }
        // Marker NICHT setzen, damit beim nächsten Start erneut versucht wird.
        return;
      }
    }

    // Alte Klartext-Einträge entfernen (immer, auch wenn keine vorhanden).
    await prefs.remove(_legacyKeyLat);
    await prefs.remove(_legacyKeyLng);
    await prefs.remove(_legacyKeyTs);
    await prefs.remove(_legacyKeyAcc);

    // Marker setzen, damit die Migration nicht erneut läuft.
    await prefs.setBool(_migrationMarker, true);
  }
}
