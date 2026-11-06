import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/supabase_service.dart';

/// Das Ergebnis einer selektiven Datenloeschung.
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

/// Loescht einzelne Datenkategorien, OHNE das Konto zu loeschen.
///
/// Der Server macht die Arbeit (Edge Function `delete-user-data`, mit der
/// Service-Rolle). Der Client entscheidet nur, WAS geloescht wird -
/// und der Server prueft, dass er nur die Daten des angemeldeten
/// Kontos anfasst.
class DataDeletionService {
  DataDeletionService(this._client);

  final SupabaseClient _client;

  /// Die Kategorien, die der Bildschirm anbietet. Die Namen muessen mit
  /// denen in der Edge Function uebereinstimmen.
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

  /// Loescht die gewaehlten Kategorien.
  Future<DataDeletionResult> deleteCategories(List<String> kategorien) async {
    try {
      final response = await _client.functions.invoke(
        'delete-user-data',
        body: {'kategorien': kategorien},
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

/// Der Service fuer die selektive Datenloeschung.
final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(SupabaseService.client);
});
