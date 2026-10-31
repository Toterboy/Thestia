import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/supabase_service.dart';

/// Liest Betriebs-Parameter aus der app_config-Tabelle (Migration 034/076).
///
/// Aktuell: `min_app_version_build` - die Mindest-Flutter-Build-Nummer
/// (pubspec `+N`). Liegt der installierte Build darunter, zeigt die App
/// beim Start einen Update-Hinweis. Fail-open: Bei Netz-/Schema-Fehlern
/// kommt `null` zurück und die App startet normal.
class AppConfigService {
  AppConfigService._();

  static const String _minVersionKey = 'min_app_version_build';
  static const String _transitEnabledKey = 'transit_spark_enabled';

  /// Schluessel des lokalen Caches fuer den Mindest-Build.
  ///
  /// PERFORMANCE (31.10.2026): Die Abfrage lief beim Start auf dem
  /// kritischen Pfad - der erste Frame der App wartete auf einen
  /// Server-Roundtrip (bis zu 6 s Timeout). Der Wert wird deshalb
  /// lokal gecacht: der Cache wird sofort ausgewertet, der frische
  /// Wert laeuft im Hintergrund nach.
  static const String minVersionCacheKey = 'app_min_app_version_build';

  /// Der gecachte Mindest-Build, oder `null` wenn noch keiner da ist.
  static int? cachedMinAppVersionBuild(SharedPreferences prefs) =>
      prefs.getInt(minVersionCacheKey);

  /// Legt den Mindest-Build im Cache ab.
  static Future<void> cacheMinAppVersionBuild(
    SharedPreferences prefs,
    int minBuild,
  ) async {
    await prefs.setInt(minVersionCacheKey, minBuild);
  }

  /// Ob Transit Spark serverseitig freigeschaltet ist.
  ///
  /// Der Server kann Transit Spark per `app_config`-Eintrag abschalten
  /// (Migration 159) - ohne Deploy und ohne App-Update. Das ist die
  /// Notbremse fuer den Fall, dass der BLE-Gerätetest nicht besteht
  /// (ROADMAP, Bedingung fuer das Release von 0.10.0).
  ///
  /// Fail-open: Bei Netz- oder Schema-Fehlern kommt `true` zurueck. Die
  /// App laesst den Nutzer den Radar starten - der Server entscheidet
  /// dann ohnehin. Ein Fehler beim Lesen des Schalters darf das Feature
  /// nicht ungefragt stilllegen.
  static Future<bool> fetchTransitSparkEnabled() async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final response = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', _transitEnabledKey)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (response == null) return true;
      final wert = ((response['value'] as String?) ?? '').trim().toLowerCase();
      return !const ['false', '0', 'off', 'no'].contains(wert);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] transit_spark_enabled fehlgeschlagen: $e');
      }
      return true;
    }
  }

  /// Mindest-Build-Nummer oder `null` (nicht gesetzt / Fehler).
  ///
  /// [timeout] ist der Grund, warum diese Methode einen Parameter
  /// braucht: der Aufruf auf dem kritischen Startpfad darf nicht
  /// sechs Sekunden dauern.
  static Future<int?> fetchMinAppVersionBuild({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', _minVersionKey)
          .maybeSingle()
          .timeout(timeout);
      if (response == null) return null;
      return int.tryParse((response['value'] as String?) ?? '');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] min_app_version_build fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Die Build-Nummer der installierten App (pubspec `+N`).
  ///
  /// Gecacht: der Wert aendert sich mit der Installation nicht, und
  /// [PackageInfo.fromPlatform] ist ein Plattform-Aufruf.
  static int? _buildNumberCache;

  static Future<int> currentBuildNumber() async {
    final cached = _buildNumberCache;
    if (cached != null) return cached;
    var build = 0;
    try {
      final info = await PackageInfo.fromPlatform();
      build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      build = 0;
    }
    _buildNumberCache = build;
    return build;
  }

  /// Liegt der installierte Build unter dem serverseitigen Mindest-Build?
  ///
  /// Fail-open: ein unbekannter Build (0) oder ein unbekannter
  /// Mindest-Build (0) sperrt niemanden.
  static bool isBuildBelowMinBuild(int build, int minBuild) =>
      build > 0 && minBuild > 0 && build < minBuild;
}

/// Prüft, ob das installierte Build (pubspec `+N`) unterhalb des
/// serverseitigen Mindest-Builds liegt. Fail-open bei allen Fehlern.
///
/// Fragt den SERVER - fuer den Startpfad ist [cachedMinAppVersionBuild]
/// die schnellere Variante (siehe main.dart).
Future<bool> isAppUpdateRequired() async {
  try {
    final minBuild = await AppConfigService.fetchMinAppVersionBuild();
    if (minBuild == null || minBuild <= 0) return false;
    final build = await AppConfigService.currentBuildNumber();
    return AppConfigService.isBuildBelowMinBuild(build, minBuild);
  } catch (_) {
    return false;
  }
}
