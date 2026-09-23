import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/random_chat_session.dart';
import 'package:wisp/services/supabase_service.dart';

/// Vermittelt das serverseitige Matching für den Zufallschat.
///
/// Die Supabase-RPCs (`join_random_chat`, `get_random_chat_session`,
/// `leave_random_chat`) verwalten ausschließlich die Paarung (wer spricht
/// mit wem). Nachrichten laufen E2E-verschlüsselt über den P2P-DataChannel -
/// der Server sieht keine Inhalte.
class RandomChatService {
  RandomChatService(this._client);

  final SupabaseClient _client;

  /// Tritt der Warteschlange bei bzw. stellt eine bestehende Session wieder
  /// her (Reconnect). Liefert Session mit Partner, falls direkt gematcht.
  Future<RandomChatSession?> join() async {
    try {
      final response = await _client.rpc('join_random_chat');
      if (response == null) return null;
      return RandomChatSession.fromJson(Map<String, dynamic>.from(response as Map));
    } catch (e) {
      debugPrint('[RandomChat] join fehlgeschlagen: $e');
      return null;
    }
  }

  /// Fragt den aktuellen Status einer Session ab (Polling auf den Partner).
  Future<RandomChatSession?> getSession(String sessionId) async {
    try {
      final response = await _client.rpc(
        'get_random_chat_session',
        params: {'p_session_id': sessionId},
      );
      if (response == null) return null;
      return RandomChatSession.fromJson(Map<String, dynamic>.from(response as Map));
    } catch (e) {
      debugPrint('[RandomChat] getSession fehlgeschlagen: $e');
      return null;
    }
  }

  /// Aktive Session DES Aufrufers (globaler Relay-Eingang, Migration 111):
  /// Session-ID + Partner, ohne dass der Client die ID kennen muss.
  Future<RandomChatSession?> getMyActiveSession() async {
    try {
      final response = await _client.rpc('get_my_active_random_chat');
      if (response == null) return null;
      final map = Map<String, dynamic>.from(response as Map);
      if ((map['sessionId'] as String?) == null) return null;
      return RandomChatSession.fromJson(map);
    } catch (e) {
      debugPrint('[RandomChat] getMyActiveSession fehlgeschlagen: $e');
      return null;
    }
  }

  /// Beendet die Session (Idempotent, serverseitig).
  Future<void> leave(String sessionId) async {
    try {
      await _client.rpc(
        'leave_random_chat',
        params: {'p_session_id': sessionId},
      );
    } catch (e) {
      debugPrint('[RandomChat] leave fehlgeschlagen: $e');
    }
  }
}

/// Provider für den Random-Chat-Service (aktiv nur mit Supabase).
final randomChatServiceProvider = Provider<RandomChatService?>((ref) {
  if (!SupabaseService.isInitialized) return null;
  return RandomChatService(SupabaseService.client);
});
