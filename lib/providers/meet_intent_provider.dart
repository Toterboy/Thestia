import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/meet_intent.dart';
import 'package:thestia/services/meet_intent_service.dart';

/// Verwaltet den "echtes Treffen"-Vorschlag eines einzelnen Matches.
class MeetIntentNotifier extends StateNotifier<MeetIntent?> {
  MeetIntentNotifier(this._service, this._matchId) : super(null) {
    _load();
  }

  final MeetIntentService _service;
  final String _matchId;

  Future<void> _load() async {
    try {
      state = await _service.get(_matchId);
    } catch (e) {
      // still null -> UI zeigt nichts an.
    }
  }

  /// Lädt den aktuellen Stand neu vom Server.
  Future<void> reload() => _load();

  /// Eigene Zustimmung setzen (true = will treffen, false = will nicht).
  Future<void> setWants(bool wants) async {
    final updated = await _service.set(_matchId, wants: wants);
    if (updated != null) state = updated;
  }

  /// Bestätigt, dass das Treffen stattgefunden hat.
  Future<void> confirmMet() async {
    final updated = await _service.set(_matchId, metConfirmed: true);
    if (updated != null) state = updated;
  }
}

/// Provider (Family) für den Meet-Intent eines Matches.
final meetIntentProvider =
    StateNotifierProvider.family<MeetIntentNotifier, MeetIntent?, String>(
  (ref, matchId) {
    return MeetIntentNotifier(
      ref.watch(meetIntentServiceProvider),
      matchId,
    );
  },
);
