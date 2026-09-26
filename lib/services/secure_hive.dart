import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:thestia/services/secure_storage_namespaces.dart';
import 'package:hive/hive.dart';

/// Öffnet Hive-Boxen AES-256-verschlüsselt (Audit K6/M11).
///
/// Der Schlüssel (32 Bytes) wird einmalig mit [Random.secure] erzeugt und
/// im Keystore/Keychain (flutter_secure_storage) verwahrt. Damit sind
/// private Signal-Keys, Session-States, Chat-Metadaten, GPS-Daten und
/// Reports at-rest verschlüsselt – ein Auslesen der Hive-Dateien (gerootetes
/// Gerät, Android-Backup) reicht nicht mehr aus.
///
/// Migration: Bestehende unverschlüsselte Boxen (Stand vor diesem Fix)
/// werden beim ersten Öffnen gelesen, anschließend wird die Box gelöscht
/// und verschlüsselt neu geschrieben. Ist eine Box nicht mehr lesbar
/// (Schlüssel verloren), wird sie sicherheitshalber zurückgesetzt.
///
/// Testbarkeit: Der Keystore-Zugriff ist über den Konstruktor injizierbar
/// ([SecureHive] mit eigener [FlutterSecureStorage]-Subklasse); Tests nutzen
/// [SecureHive.forTesting].
class SecureHive {
  SecureHive([FlutterSecureStorage? secureStorage])
      : _storage = secureStorage ?? const FlutterSecureStorage();

  /// App-weite Standardinstanz (Keystore/Keychain der Plattform).
  static final SecureHive instance = SecureHive();

  /// Instanz mit explizitem Storage-Backend (für Tests).
  @visibleForTesting
  SecureHive.forTesting(FlutterSecureStorage secureStorage)
      : _storage = secureStorage;

  static const String _keyName = 'hive_encryption_key';

  /// Meta-Box (verschlüsselt): registriert, welche Boxen von [SecureHive]
  /// AES-verschlüsselt angelegt wurden. Nötig, weil das Öffnen einer
  /// KLARTEXT-Box mit Cipher keine Exception wirft, sondern stillschweigend
  /// korrupte Werte liefert – der Marker ist der einzige zuverlässige
  /// Hinweis, ob eine Datei schon verschlüsselt ist.
  static const String _metaBoxName = 'secure_hive_meta';

  // Eigener Namespace (secure_storage_namespaces.dart): die E2EE-Keys
  // duerfen nicht im selben Keystore-Alias liegen wie Auth-Tokens - sonst
  // loescht ein Dekrypt-Fehler hier beides.
  static const _androidOptions = AndroidOptions(
    storageNamespace: SecureNamespaces.signals,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    accountName: SecureNamespaces.signals,
  );

  final FlutterSecureStorage _storage;

  HiveAesCipher? _cachedCipher;

  /// Liefert den Cipher (Key aus dem Keystore) oder `null`,
  /// wenn keine sichere Speicherung verfügbar ist (z. B. Web).
  Future<HiveAesCipher?> _cipher() async {
    if (kIsWeb) return null; // Web: kein Keystore → keine Hive-AES-Nutzung.
    if (_cachedCipher != null) return _cachedCipher;

    var b64 = await _storage.read(
      key: _keyName,
      aOptions: _androidOptions,
      iOptions: _iOSOptions,
    );

    var bytes = b64 != null ? _tryDecodeKey(b64) : null;
    if (bytes == null) {
      // Neuen 32-Byte-Schlüssel kryptografisch sicher erzeugen.
      final random = Random.secure();
      bytes =
          Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
      b64 = _encodeKey(bytes);
      await _storage.write(
        key: _keyName,
        value: b64,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );
    }

    _cachedCipher = HiveAesCipher(bytes);
    return _cachedCipher;
  }

  static Uint8List? _tryDecodeKey(String b64) {
    try {
      final decoded = base64Decode(b64);
      if (decoded.length != 32) return null;
      return Uint8List.fromList(decoded);
    } catch (_) {
      return null;
    }
  }

  static String _encodeKey(Uint8List bytes) => base64Encode(bytes);

  /// Öffnet (oder erstellt) eine AES-verschlüsselte Hive-Box.
  ///
  /// Ablauf:
  /// 1. Box existiert nicht ODER ist in der Meta-Box als verschlüsselt
  ///    registriert → direkt mit Cipher öffnen.
  /// 2. Box existiert ohne Registrierung (Klartext-Altbestand) → Inhalt
  ///    unverschlüsselt lesen, Box löschen, verschlüsselt neu anlegen.
  /// 3. Altbestand unlesbar (z. B. verschlüsselt mit verlorenem Schlüssel)
  ///    → sicher zurücksetzen (fail-closed).
  Future<Box<T>> openBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }

    final cipher = await _cipher();
    if (cipher == null) {
      // Web/Fallback: unverschlüsselt (kein Keystore verfügbar).
      return Hive.openBox<T>(name);
    }

    Box<String> meta;
    try {
      meta = await Hive.openBox<String>(_metaBoxName,
          encryptionCipher: cipher);
    } catch (e) {
      // Meta-Box unlesbar (Schlüsselwechsel/-verlust): zurücksetzen. Alle
      // Datenboxen laufen dann durch den Migrations-/Reset-Pfad.
      if (kDebugMode) {
        debugPrint('[SecureHive] Meta-Box unlesbar, wird zurückgesetzt: $e');
      }
      await Hive.deleteBoxFromDisk(_metaBoxName);
      meta = await Hive.openBox<String>(_metaBoxName, encryptionCipher: cipher);
    }
    final registered = meta.get(name) == 'v1';
    final exists = await Hive.boxExists(name);

    if (!exists || registered) {
      try {
        final box = await Hive.openBox<T>(name, encryptionCipher: cipher);
        await meta.put(name, 'v1');
        return box;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SecureHive] Box "$name" nicht verschlüsselt öffnbar '
              '($e). Versuche Migration von Klartext-Altbestand.');
        }
      }
    }

    // Altbestand unverschlüsselt lesen und in verschlüsselte Box migrieren.
    Map<dynamic, T> legacy = const {};
    try {
      final plain = await Hive.openBox<T>(name);
      legacy = Map.fromEntries(
        plain.keys.map((k) => MapEntry(k, plain.get(k) as T)),
      );
      await plain.close();
      await Hive.deleteBoxFromDisk(name);
    } catch (e) {
      // Box auch unverschlüsselt nicht lesbar (z. B. verschlüsselt mit
      // verlorenem Schlüssel) → sicher zurücksetzen (Datenverlust
      // akzeptiert: E2E-Keys dürfen niemals unverschlüsselt weiterverwendet
      // werden).
      if (kDebugMode) {
        debugPrint('[SecureHive] Box "$name" unlesbar, wird zurückgesetzt: $e');
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }

    final box = await Hive.openBox<T>(name, encryptionCipher: cipher);
    legacy.forEach(box.put);
    if (legacy.isNotEmpty) await box.flush();
    await meta.put(name, 'v1');
    if (kDebugMode && legacy.isNotEmpty) {
      debugPrint('[SecureHive] Box "$name" verschlüsselt migriert '
          '(${legacy.length} Einträge).');
    }
    return box;
  }
}
