import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/supabase_service.dart';

/// Service für das Quiz "Wie gut kenn ich mein Match".
///
/// Alle Zustandsänderungen (Cooldown, Freischaltungslevel, Antwort-Prüfung)
/// laufen über SECURITY DEFINER-RPCs - die Freischaltungslogik ist damit
/// serverseitig abgesichert und kann clientseitig nicht umgangen werden.
class QuizService {
  QuizService(this._client);

  final SupabaseClient _client;

  /// Aktuellen Quiz-Zustand laden.
  Future<QuizState?> getState(int matchId) async {
    try {
      final response = await _client.rpc(
        'get_match_quiz_state',
        params: {'p_match_id': matchId},
      );
      if (response == null) return null;
      return QuizState.fromJson(Map<String, dynamic>.from(response as Map));
    } catch (e) {
      debugPrint('[Quiz] getState fehlgeschlagen: $e');
      return null;
    }
  }

  /// Versuch starten. Liefert die Frage oder einen Cooldown-Hinweis.
  Future<QuizQuestion?> startAttempt(int matchId) async {
    try {
      final response = await _client.rpc(
        'start_quiz_attempt',
        params: {'p_match_id': matchId},
      );
      if (response == null) return null;
      final map = Map<String, dynamic>.from(response as Map);
      if (map['error'] == 'cooldown') {
        return QuizQuestion(
          id: '',
          prompt: '__cooldown__',
          options: [
            '${map['cooldownRemainingSeconds'] ?? 300}',
            map['nextAttemptAt']?.toString() ?? '',
          ],
        );
      }
      if (map['questionId'] == null) return null;
      return QuizQuestion.fromJson(map);
    } catch (e) {
      debugPrint('[Quiz] startAttempt fehlgeschlagen: $e');
      return null;
    }
  }

  /// Antwort abgeben (serverseitig geprüft).
  Future<QuizAnswerResult?> submitAnswer(
    int matchId,
    String questionId,
    int answerIndex,
  ) async {
    try {
      final response = await _client.rpc(
        'submit_quiz_answer',
        params: {
          'p_match_id': matchId,
          'p_question_id': questionId,
          'p_answer_index': answerIndex,
        },
      );
      if (response == null) return null;
      return QuizAnswerResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e) {
      debugPrint('[Quiz] submitAnswer fehlgeschlagen: $e');
      return null;
    }
  }

  /// Partner-Profil laden. Vollzugriff nur bei bestandenem Quiz (serverseitig
  /// erzwungen via get_match_partner_profile).
  Future<Map<String, dynamic>?> getPartnerProfile(int matchId) async {
    try {
      final response = await _client.rpc(
        'get_match_partner_profile',
        params: {'p_match_id': matchId},
      );
      if (response == null) return null;
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('[Quiz] getPartnerProfile fehlgeschlagen: $e');
      return null;
    }
  }

  /// Liefert das Partner-Profil. Bei unlock < 2 eingeschränkt (keine
  /// sensiblen Detailfelder), ab unlock 2 vollständig.
  Future<({UserProfile profile, bool unlocked, int unlockLevel})?>
      fetchPartnerProfile(int matchId) async {
    final data = await getPartnerProfile(matchId);
    if (data == null) return null;
    final unlocked = data['unlocked'] as bool? ?? false;
    final level = (data['unlockLevel'] as num?)?.toInt() ?? 0;
    final raw = Map<String, dynamic>.from(data['profile'] as Map? ?? {});

    final profile = unlocked ? _fullProfileFromRow(raw) : UserProfile.fromPublicView(raw);
    return (profile: profile, unlocked: unlocked, unlockLevel: level);
  }

  /// Mappt eine Zeile der profiles-Tabelle (snake_case) auf UserProfile.
  ///
  /// Audit M-3: Der Server liefert ab Freischaltstufe 2 kein exaktes
  /// birth_date mehr, sondern nur noch das Alter (`age`) - das Geburtsjahr
  /// wird daraus angenähert (wie in [UserProfile.fromPublicView]).
  /// `is_location_suspicious` wird serverseitig nicht mehr ausgeliefert.
  UserProfile _fullProfileFromRow(Map<String, dynamic> row) {
    DateTime? birthDate;
    final rawBirth = row['birth_date'];
    if (rawBirth != null) {
      birthDate = DateTime.tryParse(rawBirth as String);
    } else {
      final age = row['age'] as int?;
      if (age != null) {
        birthDate = DateTime(DateTime.now().year - age, 1, 1);
      }
    }
    return UserProfile(
      id: row['user_id'] as String,
      name: row['name'] as String,
      bio: row['bio'] as String? ?? '',
      interests: (row['interests'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      city: row['city'] as String? ?? '',
      gender: row['gender'] as String?,
      birthDate: birthDate,
      personalityType: row['personality_type'] as String?,
      introText: row['intro_text'] as String? ?? '',
      introAudioPath: row['intro_audio_path'] as String?,
      isVerified: row['is_verified'] as bool? ?? false,
    );
  }
}

/// Provider für den Quiz-Service.
final quizServiceProvider = Provider<QuizService>((ref) {
  return QuizService(SupabaseService.client);
});
