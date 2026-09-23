import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/find_your_match_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// Verwaltet die Kandidaten des Modus "Find your Match".
///
/// Kandidaten kommen serverseitig gefiltert (nur Profile mit Vorstellung,
/// keine bestehenden Likes/Matches, Filter des Betrachters). Ein Like wird
/// als gerichteter Like gespeichert - ein Match entsteht erst, wenn die
/// andere Person den Like bestätigt.
class FindYourMatchNotifier extends StateNotifier<List<UserProfile>> {
  FindYourMatchNotifier(this._service) : super(const []);

  final FindYourMatchService _service;

  bool _loading = false;
  bool get loading => _loading;

  bool get hasCandidates => state.isNotEmpty;

  UserProfile? get current => state.isEmpty ? null : state.first;

  /// Lädt (oder erneuert) die Kandidatenliste.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      if (!SupabaseService.isInitialized) {
        state = const [];
        return;
      }
      final candidates = await _service.getCandidates();
      state = candidates;
    } catch (e) {
      debugPrint('[FindYourMatch] Laden fehlgeschlagen: $e');
    } finally {
      _loading = false;
    }
  }

  /// Liked den aktuellen Kandidaten und entfernt ihn aus dem Deck.
  Future<bool> like() async {
    final candidate = current;
    if (candidate == null) return false;
    try {
      await _service.likeUser(candidate.id);
      state = List.of(state)..removeAt(0);
      return true;
    } catch (e) {
      debugPrint('[FindYourMatch] Like fehlgeschlagen: $e');
      return false;
    }
  }

  /// Überspringt den aktuellen Kandidaten (rein lokal).
  void skip() {
    if (state.isEmpty) return;
    state = List.of(state)..removeAt(0);
  }
}

/// Provider für den Find-your-Match-Notifier.
final findYourMatchProvider =
    StateNotifierProvider<FindYourMatchNotifier, List<UserProfile>>((ref) {
  return FindYourMatchNotifier(ref.watch(findYourMatchServiceProvider));
});

/// Anzahl offener Likes (eigene + erhaltene) für das Dashboard.
final pendingLikesCountProvider = FutureProvider<int>((ref) async {
  if (!SupabaseService.isInitialized) return 0;
  try {
    final service = ref.watch(findYourMatchServiceProvider);
    final mine = await service.listMyLikes();
    final received = await service.listReceivedLikes();
    return mine.length + received.length;
  } catch (e) {
    debugPrint('[PendingLikes] Zählen fehlgeschlagen: $e');
    return 0;
  }
});

/// Erhaltene Likes (Liste, für "Neue Likes"-Badge mit Seen-Abgleich).
final receivedLikesProvider =
    FutureProvider<List<ReceivedLike>>((ref) async {
  if (!SupabaseService.isInitialized) return const [];
  try {
    return await ref.watch(findYourMatchServiceProvider).listReceivedLikes();
  } catch (e) {
    debugPrint('[ReceivedLikes] Laden fehlgeschlagen: $e');
    return const [];
  }
});

/// Server-Funken mit Zustand (v0.9.1): für "Neue Funken"-Badge mit
/// Seen-Abgleich (unabhängig vom lokalen Chat-Cache).
final serverMatchesProvider =
    FutureProvider<List<MatchWithState>>((ref) async {
  if (!SupabaseService.isInitialized) return const [];
  try {
    return await ref
        .watch(findYourMatchServiceProvider)
        .listMatchesWithState();
  } catch (e) {
    debugPrint('[ServerMatches] Laden fehlgeschlagen: $e');
    return const [];
  }
});
