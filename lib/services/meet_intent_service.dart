import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/meet_intent.dart';
import 'package:thestia/services/supabase_service.dart';

/// Lädt und aktualisiert den "echtes Treffen"-Vorschlag eines Matches.
///
/// Lokale Kontakte (QR) haben keine Datenbank-Match-ID und werden
/// ignoriert (der Chat läuft dort ohne Server-Match).
class MeetIntentService {
  MeetIntentService(this._client);

  final SupabaseClient _client;

  /// Aktuellen Stand für ein Match laden (null bei lokalem Kontakt/Fehler).
  Future<MeetIntent?> get(String matchId) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return null;
    try {
      final res = await _client.rpc(
        'get_meet_intent',
        params: {'p_match_id': id},
      );
      if (res == null) return null;
      return MeetIntent.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      // z. B. lokaler Kontakt ohne DB-Match-Zeile.
      return null;
    }
  }

  /// Zustimmung (wants) und/oder "getroffen"-Bestätigung setzen.
  /// Einzelne Felder können null sein (= nicht ändern).
  Future<MeetIntent?> set(
    String matchId, {
    bool? wants,
    bool? metConfirmed,
  }) async {
    final id = int.tryParse(matchId);
    if (id == null || !SupabaseService.isInitialized) return null;
    try {
      final res = await _client.rpc(
        'set_meet_intent',
        params: {
          'p_match_id': id,
          'p_wants': wants,
          'p_met_confirmed': metConfirmed,
        },
      );
      if (res == null) return null;
      return MeetIntent.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      return null;
    }
  }
}

/// Provider für den [MeetIntentService].
final meetIntentServiceProvider = Provider<MeetIntentService>((ref) {
  return MeetIntentService(SupabaseService.client);
});
