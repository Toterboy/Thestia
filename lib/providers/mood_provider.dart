import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/user_mood.dart';
import 'package:thestia/services/mood_service.dart';

/// Verwaltet das eigene Mood of the Day.
class MoodNotifier extends StateNotifier<Mood?> {
  MoodNotifier(this._service) : super(null) {
    _load();
  }

  final MoodService _service;

  Future<void> _load() async {
    try {
      final mood = await _service.getTodayMood();
      // Der Provider ist autoDispose: verlässt der Nutzer den Screen vor
      // Ende des Server-Calls, ist der Notifier schon disposed. Eine
      // State-Zuweisung wirft dann "Bad state: Cannot use ... after dispose".
      if (!mounted) return;
      state = mood;
    } catch (e) {
      debugPrint('[MoodNotifier] Fehler beim Laden: $e');
      if (mounted) state = null;
    }
  }

  /// Setzt ein neues Mood und aktualisiert den lokalen Zustand.
  Future<void> setMood(Mood mood) async {
    await _service.setMood(mood);
    if (mounted) state = mood;
  }
}

/// Provider für den Mood-of-the-Day-Service (Singleton).
final moodServiceProvider = Provider<MoodService>((ref) {
  return MoodService();
});

/// Provider für das eigene heutige Mood.
///
/// `autoDispose`, damit er sich automatisch aufräumt, wenn kein Screen
/// mehr darauf zuhört. Beim erneuten Betreten wird das aktuelle Mood
/// frisch vom Server geladen.
final moodProvider = StateNotifierProvider.autoDispose<MoodNotifier, Mood?>(
  (ref) {
    final service = ref.watch(moodServiceProvider);
    return MoodNotifier(service);
  },
);
