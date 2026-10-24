import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  static Future<int?> fetchMinAppVersionBuild() async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', _minVersionKey)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (response == null) return null;
      return int.tryParse((response['value'] as String?) ?? '');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] min_app_version_build fehlgeschlagen: $e');
      }
      return null;
    }
  }
}

/// Prüft, ob das installierte Build (pubspec `+N`) unterhalb der
/// serverseitigen Mindestversion liegt. Fail-open bei allen Fehlern.
Future<bool> isAppUpdateRequired() async {
  try {
    final minBuild = await AppConfigService.fetchMinAppVersionBuild();
    if (minBuild == null || minBuild <= 0) return false;
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    return build > 0 && build < minBuild;
  } catch (_) {
    return false;
  }
}
