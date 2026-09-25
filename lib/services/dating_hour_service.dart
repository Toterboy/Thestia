import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/dating_hour_models.dart';
import 'package:thestia/services/server_time_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';

/// Service für die Dating-Hour-Logik.
///
/// Alle Business-Operationen (Opt-in/Opt-out, Matching, Entscheidungen) werden
/// serverseitig in Supabase durch SECURITY DEFINER-RPCs ausgeführt. Der Client
/// hält keinen lokalen State-Reset mehr vor (keine Hive-Boxen). Zeitprüfungen
/// verwenden ausschließlich [ServerTimeService.instance.getVerifiedNow()].
///
/// Siehe supabase/migrations/018-023_dating_hour_*.sql.
class DatingHourService {
  /// Liefert die verifizierte Serverzeit.
  ///
  /// V: Wird für alle clientseitigen Zeitberechnungen verwendet, damit eine
  /// verstellte Geräte-Uhr das Dating-Hour-Fenster nicht umgehen kann.
  DateTime getServerTime() => ServerTimeService.instance.getVerifiedNow();

  /// Exception-sicherer Wrapper für Supabase-Aufrufe.
  Future<T> _safeCall<T>(String operation, Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DatingHourService] $operation fehlgeschlagen: $e');
      }
      throw DatingHourException('$operation fehlgeschlagen: $e');
    }
  }

  /// Ruft das aktuelle oder nächste Dating-Hour-Event vom Server ab.
  Future<DatingHourEvent?> getCurrentOrNextEvent() async {
    return _safeCall('getCurrentOrNextEvent', () async {
      final response = await SupabaseService.client.rpc(
        'get_current_or_next_dating_hour',
      );
      final rows = response is List ? response : <dynamic>[];
      if (rows.isEmpty) return null;
      return DatingHourEvent.fromJson(rows.first as Map<String, dynamic>);
    });
  }

  /// Prüft, ob der aktuelle User für das Event opt-in hat.
  ///
  /// V: RLS erlaubt nur das Lesen der eigenen Teilnehmerzeile, daher kann der
  /// Client hier keine fremden Teilnahmen sehen.
  Future<bool> isUserParticipating(String eventId) async {
    return _safeCall('isUserParticipating', () async {
      final rows = await SupabaseService.client
          .from('dating_hour_participant')
          .select('left_at')
          .eq('event_id', eventId)
          .eq('user_id', AppConstants.currentUserId)
          .limit(1);
      if (rows.isEmpty) return false;
      return rows.first['left_at'] == null;
    });
  }

  /// Opt-in für das aktuelle/nächste Event.
  ///
  /// [userId] wird aus Kompatibilitätsgründen akzeptiert, die eigentliche
  /// Autorisierung läuft serverseitig über `auth.uid()` in der RPC.
  Future<void> joinEvent(String userId, DatingHourPreferences preferences) async {
    final event = await getCurrentOrNextEvent();
    if (event == null) throw DatingHourException('Kein Event verfügbar');
    if (!event.canJoin) throw DatingHourException('Event ist nicht beitretbar');

    return _safeCall('joinEvent', () async {
      await SupabaseService.client.rpc(
        'join_dating_hour',
        params: {
          'p_event_id': event.id,
          'p_preferences': preferences.toJson(),
        },
      );
    });
  }

  /// Speichert NUR die Präferenzen - ohne beizutreten.
  ///
  /// Wichtig: Vorher wurde dafür join_dating_hour verwendet, wodurch das
  /// bloße Speichern automatisch zum Opt-in führte. Die neue RPC ändert nur
  /// die Präferenzen; die Teilnahme bleibt unverändert.
  Future<void> savePreferences(
    String eventId,
    DatingHourPreferences preferences,
  ) async {
    return _safeCall('savePreferences', () async {
      await SupabaseService.client.rpc(
        'save_dating_hour_preferences',
        params: {
          'p_event_id': eventId,
          'p_preferences': preferences.toJson(),
        },
      );
    });
  }

  /// Anzahl aktiver Teilnehmer eines Events (für die "X von N"-Anzeige).
  /// Liefert 0 bei Fehlern (Best effort - die Anzeige darf nicht hängen).
  Future<int> getParticipantCount(String eventId) async {
    try {
      final result = await SupabaseService.client.rpc(
        'get_dating_hour_participant_count',
        params: {'p_event_id': eventId},
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DatingHourService] Teilnehmer-Zähler fehlgeschlagen: $e');
      }
      return 0;
    }
  }

  /// Lädt die zuletzt gespeicherten Dating-Hour-Präferenzen (Migration 067).
  ///
  /// Diese bleiben über Events und Neuinstallationen hinweg erhalten und
  /// vorbelegen den Präferenzen-Screen. `null`/leere Map = keine gespeicherten.
  Future<Map<String, dynamic>?> getMyLastPreferences() async {
    return _safeCall('getMyLastPreferences', () async {
      final result = await SupabaseService.client.rpc(
        'get_last_dating_hour_preferences',
      );
      if (result is Map<String, dynamic>) return result;
      if (result is Map && result.isNotEmpty) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    });
  }

  /// Opt-out für das aktuelle/nächste Event.
  Future<void> leaveEvent(String userId) async {
    final event = await getCurrentOrNextEvent();
    if (event == null) throw DatingHourException('Kein Event verfügbar');

    return _safeCall('leaveEvent', () async {
      await SupabaseService.client.rpc(
        'leave_dating_hour',
        params: {'p_event_id': event.id},
      );
    });
  }

  /// Liefert die aktive Session des aktuellen Users für ein Event.
  Future<DatingHourSession?> getMyActiveSession(String eventId) async {
    return _safeCall('getMyActiveSession', () async {
      final response = await SupabaseService.client.rpc(
        'get_my_active_dating_hour_session',
        params: {'p_event_id': eventId},
      );
      final rows = response is List ? response : <dynamic>[];
      if (rows.isEmpty) return null;
      return DatingHourSession.fromJson(rows.first as Map<String, dynamic>);
    });
  }

  /// Lädt eine Session anhand ihrer ID.
  Future<DatingHourSession?> getSession(String sessionId) async {
    return _safeCall('getSession', () async {
      final rows = await SupabaseService.client
          .from('dating_hour_session')
          .select()
          .eq('id', sessionId)
          .limit(1);
      if (rows.isEmpty) return null;
      return DatingHourSession.fromJson(rows.first);
    });
  }

  /// Speichert die Entscheidung (Annehmen/Ablehnen) für eine Session.
  ///
  /// [userId] wird aus Kompatibilitätsgründen akzeptiert; die RPC verwendet
  /// `auth.uid()` um sicherzustellen, dass nur der eigene Entscheidungswert
  /// geschrieben wird.
  Future<DatingHourSession?> recordDecision(
    String sessionId,
    String userId,
    bool accepted,
  ) async {
    return _safeCall('recordDecision', () async {
      final decision = accepted ? 'accept' : 'reject';
      final result = await SupabaseService.client.rpc(
        'record_dating_hour_decision',
        params: {
          'p_session_id': sessionId,
          'p_decision': decision,
        },
      );

      if (kDebugMode) {
        debugPrint('[DatingHourService] recordDecision result: $result');
      }

      // Aktuellen Session-Status vom Server holen.
      return getSession(sessionId);
    });
  }

  /// Hilfsmethode: Prüft, ob der 5-Minuten-Chat einer Session abgelaufen ist.
  bool isSessionExpired(DatingHourSession session) => session.isExpired;

  /// Hilfsmethode: Verbleibende Sekunden einer Session.
  int remainingSeconds(DatingHourSession session) => session.remainingSeconds;
}

/// Provider für den [DatingHourService].
final datingHourServiceProvider = Provider<DatingHourService>((ref) {
  return DatingHourService();
});

/// Spezifische Exception für Dating-Hour-Fehler.
class DatingHourException implements Exception {
  final String message;
  DatingHourException(this.message);

  @override
  String toString() => 'DatingHourException: $message';
}
