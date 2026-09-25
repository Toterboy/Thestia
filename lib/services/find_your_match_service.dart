import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/supabase_service.dart';

/// Service für "Find your Match": Kandidaten, gerichtete Likes und der
/// Antwort-Flow (Match bestätigen / ablehnen) über SECURITY DEFINER-RPCs.
class FindYourMatchService {
  FindYourMatchService(this._client);

  final SupabaseClient _client;

  /// Kandidaten mit Vorstellung (ohne Foto) laden.
  Future<List<UserProfile>> getCandidates({int limit = 20}) async {
    final response = await _client.rpc(
      'get_find_match_candidates',
      params: {'p_limit': limit},
    );
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) => UserProfile.fromPublicView(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  /// Eigenen Like setzen (kein Auto-Match).
  Future<void> likeUser(String targetUserId) async {
    await _client.rpc('like_user', params: {'p_target': targetUserId});
  }

  /// Erhaltenen Like annehmen (=> Match) oder ablehnen.
  Future<void> respondToLike(int likeId, {required bool accept}) async {
    await _client.rpc('respond_to_like', params: {
      'p_like_id': likeId,
      'p_accept': accept,
    });
  }

  /// Eigene offene Likes.
  Future<List<ReceivedLike>> listMyLikes() => _listLikes('list_my_likes_pending');

  /// Erhaltene offene Likes.
  Future<List<ReceivedLike>> listReceivedLikes() =>
      _listLikes('list_received_likes_pending');

  Future<List<ReceivedLike>> _listLikes(String rpcName) async {
    final response = await _client.rpc(rpcName);
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) => ReceivedLike.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Matches inklusive Quiz-Freischaltungsstand.
  Future<List<MatchWithState>> listMatchesWithState() async {
    final response = await _client.rpc('list_my_matches_with_state');
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) =>
            MatchWithState.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  // -- v0.8.0: Match-Status-RPCs (Migration 074) ---------------------------

  /// "Ruhig enden lassen": Funke wird gekühlt (active -> cooled). Er
  /// erscheint bei BEIDEN unter "Erschlossene Funken" ohne Countdown.
  Future<void> coolMatch(int matchId) async {
    await _client.rpc('cool_match', params: {'p_match_id': matchId});
  }

  /// "Re-Funke ohne Druck": gekühlte Verbindung mit einem Tap reaktivieren
  /// (cooled -> active).
  Future<void> resparkMatch(int matchId) async {
    await _client.rpc('respark_match', params: {'p_match_id': matchId});
  }

  /// Endgültig beenden (für beide Seiten): status -> ended.
  Future<void> endMatch(int matchId) async {
    await _client.rpc('end_match', params: {'p_match_id': matchId});
  }

  /// "Chats verwalten": Chat nur für mich aus der Liste nehmen.
  Future<void> hideMatch(int matchId) async {
    await _client.rpc('hide_match', params: {'p_match_id': matchId});
  }

  // -- v0.9.2: Herzensstärken (Ideen 3 + 5) -------------------------------

  /// Funken-Typ umschalten: romantisch (spark) <-> Freundschaft (friends).
  /// Nur der eigene Stand wird geändert; die Gegenseite sieht denselben
  /// Typ (kann ihn ebenfalls umschalten - letzer Schreibzugriff gewinnt).
  Future<void> setMatchKind(int matchId, {required bool friends}) async {
    await _client.rpc('set_match_kind', params: {
      'p_match_id': matchId,
      'p_kind': friends ? 'friends' : 'spark',
    });
  }

  /// Erinnerungsliste (Idee 5): Einträge eines Funkens lesen.
  Future<List<BucketItem>> bucketItems(int matchId) async {
    try {
      final response = await _client.rpc('match_bucket_items',
          params: {'p_match_id': matchId});
      final rows = response is List ? response : const <dynamic>[];
      return rows
          .map((row) => BucketItem.fromJson(
              Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      debugPrint('[Bucket] Lesen fehlgeschlagen: $e');
      return const [];
    }
  }

  /// Erinnerungsliste: Eintrag hinzufügen (max. 200 Zeichen).
  Future<int?> bucketAdd(int matchId, String text) async {
    try {
      final response = await _client.rpc('match_bucket_add', params: {
        'p_match_id': matchId,
        'p_text': text,
      });
      return (response as num?)?.toInt();
    } catch (e) {
      debugPrint('[Bucket] Hinzufügen fehlgeschlagen: $e');
      return null;
    }
  }

  /// Erinnerungsliste: Eintrag abhaken/zurücksetzen (Toggle).
  Future<bool> bucketToggle(int itemId) async {
    try {
      final response = await _client.rpc('match_bucket_toggle',
          params: {'p_item_id': itemId});
      return response is Map && response['done'] == true;
    } catch (e) {
      debugPrint('[Bucket] Abhaken fehlgeschlagen: $e');
      return false;
    }
  }

  /// Erinnerungsliste: eigenen Eintrag löschen.
  Future<void> bucketDelete(int itemId) async {
    try {
      await _client.rpc('match_bucket_delete',
          params: {'p_item_id': itemId});
    } catch (e) {
      debugPrint('[Bucket] Löschen fehlgeschlagen: $e');
    }
  }

  /// Signierte URL für die Intro-Audio-Datei eines Nutzers.
  ///
  /// Die match-media-Edge-Function prüft serverseitig, ob eine Berechtigung
  /// besteht (Like in beliebiger Richtung oder Match).
  Future<String?> getIntroAudioUrl(String targetUserId) async {
    try {
      final response = await _client.functions.invoke(
        'match-media',
        body: {'targetUserId': targetUserId, 'kind': 'intro'},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['url'] as String?;
    } catch (e) {
      debugPrint('[FindYourMatch] Intro-URL fehlgeschlagen: $e');
      return null;
    }
  }

  /// Signierte URL für das Avatar-Bild eines Match-Partners.
  /// Nur mit bestehendem Match erlaubt (serverseitig geprüft).
  Future<String?> getAvatarUrl(String targetUserId) async {
    try {
      final response = await _client.functions.invoke(
        'match-media',
        body: {'targetUserId': targetUserId, 'kind': 'avatar'},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['url'] as String?;
    } catch (e) {
      debugPrint('[FindYourMatch] Avatar-URL fehlgeschlagen: $e');
      return null;
    }
  }
}

/// Provider für den Find-your-Match-Service.
final findYourMatchServiceProvider = Provider<FindYourMatchService>((ref) {
  return FindYourMatchService(SupabaseService.client);
});
