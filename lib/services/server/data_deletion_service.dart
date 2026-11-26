import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/auth/supabase_service.dart';

/// Das Ergebnis einer selektiven Datenlöschung.
class DataDeletionResult {
  const DataDeletionResult({
    required this.ok,
    this.deleted = const {},
    this.warnings = const [],
  });

  /// Ohne Warnung durchgelaufen.
  final bool ok;

  /// Wie viele Zeilen je Tabelle entfernt wurden.
  final Map<String, dynamic> deleted;

  /// Was nicht geklappt hat.
  final List<String> warnings;
}

/// Löscht einzelne Datenkategorien, OHNE das Konto zu löschen.
///
/// Der Server macht die Arbeit (Edge Function `delete-user-data`, mit der
/// Service-Rolle). Der Client entscheidet nur, WAS gelöscht wird -
/// und der Server prüft, dass er nur die Daten des angemeldeten
/// Kontos anfasst.
class DataDeletionService {
  DataDeletionService(this._client);

  final SupabaseClient _client;

  /// Die Kategorien, die der Bildschirm anbietet. Die Namen müssen mit
  /// denen in der Edge Function übereinstimmen.
  static const List<String> kategorien = [
    'fotos',
    'standort',
    'profil',
    'likes',
    'funken',
    'nachrichten',
    'geraete',
    'stimmung',
    'meldungen',
    'transit',
    'elternaufsicht',
  ];

  /// Löscht die gewählten Kategorien.
  Future<DataDeletionResult> deleteCategories(List<String> kategorien) async {
    try {
      // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der Aufruf
      // stehen (die Löschung schien dann nicht zu passieren).
      final response = await SupabaseService.rufeEdgeFunktion(
        'delete-user-data',
        body: {'kategorien': kategorien},
        client: _client,
      );
      final data = response.data;
      if (data is Map) {
        final geloescht = data['geloescht'];
        final warnungen = data['warnungen'];
        return DataDeletionResult(
          ok: data['ok'] == true,
          deleted: geloescht is Map
              ? Map<String, dynamic>.from(geloescht)
              : const {},
          warnings: warnungen is List
              ? warnungen.map((w) => '$w').toList()
              : const [],
        );
      }
      return const DataDeletionResult(ok: false);
    } catch (e) {
      debugPrint('[DataDeletion] fehlgeschlagen: $e');
      return DataDeletionResult(ok: false, warnings: ['$e']);
    }
  }
}

/// Der Service für die selektive Datenlöschung.
final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(SupabaseService.client);
});
