import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/services/local_storage.dart';

/// Merkt sich, welche Likes/Funken der Nutzer bereits ANGESEHEN hat
/// (v0.9.1): Die Badges auf Aktuelles ("Neue Likes", "Neue Funken")
/// verschwinden dadurch beim Ansehen, statt ewig stehen zu bleiben.
///
/// Persistiert als JSON-Listen (max. 500 Einträge je Sorte, älteste
/// fliegen raus). Version (`state`) bump bei jeder Änderung, damit
/// Zähler neu berechnen.
class SeenNotifier extends StateNotifier<int> {
  SeenNotifier(this._storage) : super(0) {
    unawaited(load());
  }

  final LocalStorage _storage;

  static const _likesKey = 'seen_like_ids';
  static const _matchesKey = 'seen_match_ids';
  static const _qrKey = 'seen_qr_ids';
  static const _maxEntries = 500;

  final Set<int> likeIds = {};
  final Set<int> matchIds = {};
  final Set<String> qrIds = {};

  Future<void> load() async {
    try {
      likeIds
        ..clear()
        ..addAll(await _readInts(_likesKey));
      matchIds
        ..clear()
        ..addAll(await _readInts(_matchesKey));
      qrIds
        ..clear()
        ..addAll(await _readStrings(_qrKey));
    } catch (e) {
      debugPrint('[Seen] Laden fehlgeschlagen: $e');
    }
    state++;
  }

  Future<List<int>> _readInts(String key) async {
    final raw = await _storage.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => (e as num).toInt())
        .toList();
  }

  Future<List<String>> _readStrings(String key) async {
    final raw = await _storage.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).map((e) => '$e').toList();
  }

  Future<void> _persist(String key, Iterable<dynamic> values) async {
    final trimmed = values.toList();
    while (trimmed.length > _maxEntries) {
      trimmed.removeAt(0);
    }
    try {
      await _storage.saveString(key, jsonEncode(trimmed));
    } catch (e) {
      debugPrint('[Seen] Speichern fehlgeschlagen: $e');
    }
  }

  bool _bump = false;

  void _touch() {
    // Gleiche-Frame-Mehrfach-Bumps vermeiden (ein Rebuild genügt).
    if (_bump) return;
    _bump = true;
    scheduleMicrotask(() {
      _bump = false;
      state++;
    });
  }

  /// Erhaltene Likes als gesehen markieren.
  Future<void> markLikesSeen(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    likeIds.addAll(ids);
    await _persist(_likesKey, likeIds);
    _touch();
  }

  /// Server-Funken als gesehen markieren.
  Future<void> markMatchesSeen(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    matchIds.addAll(ids);
    await _persist(_matchesKey, matchIds);
    _touch();
  }

  /// Lokale QR-Kontakte als gesehen markieren (Match-String-IDs).
  Future<void> markQrSeen(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    qrIds.addAll(ids);
    await _persist(_qrKey, qrIds);
    _touch();
  }
}

/// Versions-Tick + Zugriff auf die Seen-Sets (`ref.watch` triggert Rebuild).
final seenProvider = StateNotifierProvider<SeenNotifier, int>((ref) {
  return SeenNotifier(ref.watch(localStorageProvider));
});
