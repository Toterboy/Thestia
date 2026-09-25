import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/user_mood.dart';
import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/supabase_service.dart';

/// Service für das Mood-of-the-Day-Feature.
///
/// Kommuniziert mit den Supabase-RPCs `set_user_mood` und `get_user_mood`.
/// Fehler werden als [AppException] geworfen, damit das UI konsistent
/// reagieren kann.
class MoodService {
  MoodService([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Setzt oder aktualisiert den Mood des aktuellen Tages für den
  /// eingeloggten Nutzer.
  Future<void> setMood(Mood mood) async {
    try {
      await _client.rpc(
        'set_user_mood',
        params: {'p_mood': mood.value},
      );
    } on PostgrestException catch (e) {
      debugPrint('[MoodService] setMood RPC-Fehler: ${e.message}');
      throw AppException('Mood konnte nicht gespeichert werden.');
    } catch (e) {
      debugPrint('[MoodService] setMood unerwarteter Fehler: $e');
      throw AppException('Ein unerwarteter Fehler ist aufgetreten.');
    }
  }

  /// Gibt den eigenen Mood des aktuellen Tages zurück (oder null).
  Future<Mood?> getTodayMood() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    return getMoodForUser(userId);
  }

  /// Gibt den Mood des aktuellen Tages für einen beliebigen Nutzer zurück.
  Future<Mood?> getMoodForUser(String userId) async {
    try {
      final result = await _client.rpc(
        'get_user_mood',
        params: {'p_user_id': userId},
      );
      return (result as String?).toMood();
    } on PostgrestException catch (e) {
      debugPrint('[MoodService] getMoodForUser RPC-Fehler: ${e.message}');
      throw AppException('Mood konnte nicht geladen werden.');
    } catch (e) {
      debugPrint('[MoodService] getMoodForUser unerwarteter Fehler: $e');
      throw AppException('Ein unerwarteter Fehler ist aufgetreten.');
    }
  }
}
