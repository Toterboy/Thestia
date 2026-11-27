import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Lädt und ändert das Sync-Date eines Matches.
///
/// DER WEG: Der Zustand liegt serverseitig (sync_dates), damit beide
/// Seiten denselben Startzeitpunkt sehen und beide sehen, ob der andere
/// schon angenommen hat. Die RPCs prüfen selbst, dass der Aufrufer zu
/// dem Match gehört.
///
/// Lokale Kontakte (QR) haben keine Datenbank-Match-ID und werden
/// ignoriert (der Chat läuft dort ohne Server-Match).
class SyncDateService {
  SyncDateService(this._client);

  final SupabaseClient _client;

  /// Der Stand des Dates (null, wenn es keines gibt).
  Future<SyncDate?> get(String matchId) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return null;
    try {
      final res = await _client.rpc(
        'get_sync_date',
        params: {'p_match_id': id},
      );
      if (res == null) return null;
      return SyncDate.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      // Z. B. ein lokaler Kontakt ohne DB-Match-Zeile.
      return null;
    }
  }

  /// Schlägt ein Date vor (ersetzt ein altes).
  Future<SyncDate?> propose(
    String matchId, {
    required SyncDateIdee idee,
    required DateTime startAt,
  }) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return null;
    try {
      final res = await _client.rpc(
        'set_sync_date',
        params: {
          'p_match_id': id,
          'p_idea': idee.wert,
          'p_start_at': startAt.toUtc().toIso8601String(),
        },
      );
      if (res == null) return null;
      return SyncDate.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      return null;
    }
  }

  /// Nimmt das vorgeschlagene Date an.
  Future<SyncDate?> accept(String matchId) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return null;
    try {
      final res = await _client.rpc(
        'set_sync_date',
        params: {'p_match_id': id, 'p_accept': true},
      );
      if (res == null) return null;
      return SyncDate.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      return null;
    }
  }

  /// Sagt das Date ab (es verschwindet für beide).
  Future<void> decline(String matchId) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return;
    await bestEffort('syncDateService.decline', () async {
      await _client.rpc(
        'set_sync_date',
        params: {'p_match_id': id, 'p_decline': true},
      );
    });
  }
}

/// Provider für den [SyncDateService].
final syncDateServiceProvider = Provider<SyncDateService>((ref) {
  return SyncDateService(SupabaseService.client);
});
