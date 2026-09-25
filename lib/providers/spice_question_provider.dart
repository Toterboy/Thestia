import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/spice_question.dart';
import 'package:thestia/services/spice_question_service.dart';

/// Lädt die Spice Questions eines Matches (autoDispose: nur solange die
/// Fragen-Seite offen ist).
final spiceQuestionsProvider =
    FutureProvider.autoDispose.family<List<SpiceQuestion>, int>((ref, matchId) {
  return ref.watch(spiceQuestionServiceProvider).getQuestions(matchId);
});