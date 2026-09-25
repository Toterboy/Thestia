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
