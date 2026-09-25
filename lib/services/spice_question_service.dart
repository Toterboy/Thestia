import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/spice_question.dart';
import 'package:thestia/services/supabase_service.dart';

/// Service für "Spice Questions" (Eisbrecher-Fragen, Feature A).
///
/// Alle Zustandslogik (Teilnahme-Prüfung, Aufdeckung der Partner-Antwort)
/// läuft über SECURITY DEFINER-RPCs — die Aufdeckungslogik ist damit
/// serverseitig abgesichert und kann clientseitig nicht umgangen werden.
class SpiceQuestionService {
  SpiceQuestionService(this._client);

  final SupabaseClient _client;

  /// Lädt bis zu 5 Fragen für ein Match inkl. Antwort-Status.
  Future<List<SpiceQuestion>> getQuestions(int matchId) async {
    try {
      final response = await _client.rpc(
        'get_spice_questions',
        params: {'p_match_id': matchId},
      );
      if (response == null) return <SpiceQuestion>[];
      final list = response as List<dynamic>;
      return list
          .map((e) => SpiceQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[SpiceQuestions] getQuestions fehlgeschlagen: $e');
      return <SpiceQuestion>[];
    }
  }

  /// Gibt eine Antwort ab. Liefert die Partner-Antwort, sobald beide
  /// geantwortet haben.
  Future<SpiceAnswerResult?> answer(
    int matchId,
    int questionId,
    String answer,
  ) async {
    try {
      final response = await _client.rpc(
        'answer_spice_question',
        params: {
          'p_match_id': matchId,
          'p_question_id': questionId,
          'p_answer': answer,
        },
      );
      if (response == null) return null;
      return SpiceAnswerResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e) {
      debugPrint('[SpiceQuestions] answer fehlgeschlagen: $e');
      return null;
    }
  }
}

/// Provider für den [SpiceQuestionService].
final spiceQuestionServiceProvider = Provider<SpiceQuestionService>((ref) {
  return SpiceQuestionService(SupabaseService.client);
});