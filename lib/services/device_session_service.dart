import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Ein Gerät, auf dem das Konto aktuell (oder zuletzt) eingeloggt ist.
class DeviceSession {
  const DeviceSession({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastSeenAt,
    required this.createdAt,
    this.appVersion,
    this.deviceModel,
    this.isCurrent = false,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String? appVersion;
  final String? deviceModel;
  final DateTime lastSeenAt;
  final DateTime createdAt;
  final bool isCurrent;

  factory DeviceSession.fromMap(
    Map<String, dynamic> map, {
    String? currentDeviceId,
  }) {
    return DeviceSession(
      deviceId: map['device_id'] as String? ?? '',
      deviceName: map['device_name'] as String? ?? '',
      platform: map['platform'] as String? ?? '',
      appVersion: map['app_version'] as String?,
      deviceModel: map['device_model'] as String?,
      lastSeenAt:
          DateTime.tryParse(map['last_seen_at'] as String? ?? '') ??
              DateTime.now(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      isCurrent:
          currentDeviceId != null && map['device_id'] == currentDeviceId,
    );
  }

  /// Freundliches Label für die Liste. Das echte Gerätemodell (v0.8.1)
  /// gewinnt - "Samsung SM-S921B" sagt mehr als "Android (SDK 34)".
  String get label {
    final model = deviceModel?.trim();
    if (model != null && model.isNotEmpty) return model;
    final name = deviceName.trim();
    if (name.isNotEmpty) return name;
    return platform.isNotEmpty ? platform : 'Unbekanntes Gerät';
  }
}

/// Verwaltet die Geräte-Registrierung ("Wo bin ich eingeloggt?").
///
/// Jede App-Instanz erzeugt beim ersten Start eine zufällige Geräte-ID
/// und hält sie lokal vor. Beim Login/App-Start wird sie serverseitig in
/// `auth_devices` (Migration 071) registriert bzw. deren last_seen_at
/// aktualisiert. RLS stellt sicher, dass jeder nur seine eigenen Zeilen
/// sieht und löschen kann.
class DeviceSessionService {
  DeviceSessionService(this._storage);

  static const _deviceIdKey = 'auth_device_id';

  final LocalStorage _storage;

  SupabaseDatabaseService get _db => SupabaseDatabaseService(
        SupabaseService.client,
      );

  /// Stabile Geräte-ID dieser Installation (lazy erzeugt).
  Future<String> getDeviceId() async {
    var id = await _storage.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = _generateId();
      await _storage.saveString(_deviceIdKey, id);
    }
    return id;
  }

  /// Kollisionsarme Zufalls-ID (kein Crypto-Bedarf: nur Anzeige-Zuordnung).
  String _generateId() {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final rand = (rnd * 7919) ^ identityHashCode(this);
    return 'dev-$rnd-$rand';
  }

  /// Lesbarer Gerätename (Plattform + Version), z. B. "Android 14".
  static String describeDevice() {
    try {
      final os = Platform.operatingSystem;
      final osLabel = switch (os) {
        'android' => 'Android',
        'ios' => 'iOS',
        'macos' => 'macOS',
        'windows' => 'Windows',
        'linux' => 'Linux',
        _ => os,
      };
      // Android liefert z. B. "Version 14 (SDK 34)" - Hauptversion raus-
      // ziehen, wenn erkennbar; sonst reicht das OS-Label.
      final version = Platform.operatingSystemVersion;
      final sdkMatch = RegExp(r'SDK\s*(\d+)').firstMatch(version);
      if (os == 'android' && sdkMatch != null) {
        return 'Android (SDK ${sdkMatch.group(1)})';
      }
      final mainVersion = version.split(' ').first.split('.').first;
      final numeric = int.tryParse(mainVersion);
      return numeric != null ? '$osLabel $mainVersion' : osLabel;
    } catch (_) {
      return 'Gerät';
    }
  }

  /// Registriert das aktuelle Gerät serverseitig (Best-Effort-Aufrufer).
  ///
  /// Wirft bei Fehlern - der Aufrufer entscheidet (beim Sync: still,
  /// auf dem Geräte-Screen: Hinweis).
  Future<void> enrollCurrentDevice() async {
    if (!SupabaseService.isInitialized) return;
    final info = await PackageInfo.fromPlatform();
    await _db.upsertOwnDevice(
      deviceId: await getDeviceId(),
      deviceName: describeDevice(),
      platform: Platform.operatingSystem,
      appVersion: '${info.version} (${info.buildNumber})',
      deviceModel: await readDeviceModel(),
    );
  }

  /// Echtes Gerätemodell (v0.8.1): Hersteller + Modellkennung, z. B.
  /// "Samsung SM-S921B" oder "Nothing A063" - macht "Angemeldete Geräte"
  /// nach Neuinstallation eindeutig statt "Android (SDK 34)".
  static Future<String?> readDeviceModel() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        final manufacturer = android.manufacturer.trim();
        final model = android.model.trim();
        if (model.isEmpty) return null;
        final m = manufacturer.isEmpty
            ? model
            : '${manufacturer[0].toUpperCase()}'
                '${manufacturer.substring(1)} $model';
        return m.length > 80 ? m.substring(0, 80) : m;
      }
      if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        final machine = ios.utsname.machine.trim();
        if (machine.isEmpty) return null;
        return machine.length > 80 ? machine.substring(0, 80) : machine;
      }
    } catch (e) {
      debugPrint('[DeviceSession] Gerätemodell nicht lesbar: $e');
    }
    return null;
  }

  /// Liste aller Geräte des Kontos, das aktuelle zuerst markiert.
  Future<List<DeviceSession>> listDevices() async {
    final rows = await _db.fetchOwnDevices();
    final currentId = await getDeviceId();
    return rows
        .map((r) => DeviceSession.fromMap(r, currentDeviceId: currentId))
        .toList();
  }

  /// Meldet ALLE ANDEREN Sitzungen ab (GoTrue `signOut(scope: others)`)
  /// und entfernt deren Geräte-Zeilen aus der Liste. Die aktuelle
  /// Sitzung bleibt unverändert.
  Future<void> logoutEverywhereExceptCurrent() async {
    if (!SupabaseService.isInitialized) return;
    // WICHTIG: Erst die Server-Sessions invalidieren, dann die Liste
    // aufräumen - schlägt der Logout fehl, bleibt alles wie es war.
    await SupabaseService.client.auth
        .signOut(scope: SignOutScope.others);
    await _db.deleteOtherOwnDevices(await getDeviceId());
  }

  /// Entfernt den eigenen Eintrag (beim Ausloggen dieses Geräts).
  Future<void> deregisterCurrentDevice() async {
    if (!SupabaseService.isInitialized) return;
    try {
      await _db.deleteOwnDevice(await getDeviceId());
    } catch (e) {
      // Best-Effort: Ohne Netz bleibt der Eintrag liegen und verschwindet
      // spätestens beim "Überall abmelden" bzw. wenn die Session abläuft.
      debugPrint('[DeviceSession] Deregistrierung fehlgeschlagen: $e');
    }
  }
}

/// Provider für den Geräte-Service.
final deviceSessionServiceProvider = Provider<DeviceSessionService>((ref) {
  return DeviceSessionService(ref.watch(localStorageProvider));
});
