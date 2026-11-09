import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/age_safety_rules.dart';

/// Der Zustand des Kategorie-Browsens ("Find your Spark nach
/// Kategorien").
class FindYourMatchBrowseState {
  const FindYourMatchBrowseState({
    this.kategorie,
    this.alterMin = 18,
    this.alterMax = 99,
    this.kategorien = const [],
    this.kandidaten = const [],
    this.laedt = false,
  });

  /// Die gerade gewaehlte Kategorie (null = noch keine).
  final String? kategorie;

  /// Die Altersspanne des Browsers (serverseitig begrenzt).
  final int alterMin;
  final int alterMax;

  /// Die Kategorien mit ihren Zahlen.
  final List<CategoryCount> kategorien;

  /// Die Kandidaten der gewaehlten Kategorie.
  final List<UserProfile> kandidaten;

  final bool laedt;

  FindYourMatchBrowseState copyWith({
    String? kategorie,
    int? alterMin,
    int? alterMax,
    List<CategoryCount>? kategorien,
    List<UserProfile>? kandidaten,
    bool? laedt,
  }) {
    return FindYourMatchBrowseState(
      kategorie: kategorie ?? this.kategorie,
      alterMin: alterMin ?? this.alterMin,
      alterMax: alterMax ?? this.alterMax,
      kategorien: kategorien ?? this.kategorien,
      kandidaten: kandidaten ?? this.kandidaten,
      laedt: laedt ?? this.laedt,
    );
  }
}

/// Verwaltet das Stoebern nach Interessens-Kategorien.
///
/// BEFUND (09.11.2026, Betreiber): "Der Modus Find your Spark soll
/// erweitert werden ... dann entweder Zufallsvorstellung oder
/// Vorstellungen anderer nach Kategorien ansehen."
///
/// DIE ALTERSSGRENZE: Die Grenzen kommen aus `AgeSafetyRules` (die
/// App-seitige Spiegelung der Server-Regel) - 16/17 fuer
/// Minderjaehrige, 18-99 fuer Erwachsene. Der Server begrenzt sie
/// zusaetzlich (`max_age_range_min`, die Obergrenze 17/99) - ein
/// manipulierter Client kann sie also nicht weiten.
class FindYourMatchBrowseNotifier
    extends StateNotifier<FindYourMatchBrowseState> {
  FindYourMatchBrowseNotifier(this._service, int blickAlter)
    : super(
        FindYourMatchBrowseState(
          alterMin: AgeSafetyRules.minFilterAge(blickAlter),
          alterMax: AgeSafetyRules.maxFilterAge(blickAlter),
        ),
      );

  final FindYourMatchService _service;

  /// Laedt die Kategorien (mit ihren Zahlen) fuer die aktuelle
  /// Altersspanne.
  Future<void> loadKategorien() async {
    if (!SupabaseService.isInitialized) return;
    state = state.copyWith(laedt: true);
    try {
      final kategorien = await _service.getCategoryCounts(
        ageMin: state.alterMin,
        ageMax: state.alterMax,
      );
      state = state.copyWith(kategorien: kategorien, laedt: false);
      // Die erste Kategorie mit Treffern gleich auswaehlen - das
      // spart einen Klick und zeigt sofort, dass es funktioniert.
      if (state.kategorie == null) {
        for (final k in kategorien) {
          if (k.count > 0) {
            await waehleKategorie(k.category);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[FindYourMatchBrowse] Kategorien laden fehlgeschlagen: $e');
      state = state.copyWith(laedt: false);
    }
  }

  /// Setzt die Altersspanne des Browsers und laedt neu.
  Future<void> setzeAltersspanne(int min, int max) async {
    if (min == state.alterMin && max == state.alterMax) return;
    state = state.copyWith(alterMin: min, alterMax: max, kandidaten: const []);
    await loadKategorien();
  }

  /// Waehlt eine Kategorie und laedt ihre Kandidaten.
  Future<void> waehleKategorie(String kategorie) async {
    state = state.copyWith(
      kategorie: kategorie,
      kandidaten: const [],
      laedt: true,
    );
    if (!SupabaseService.isInitialized) {
      state = state.copyWith(laedt: false);
      return;
    }
    try {
      final kandidaten = await _service.getCandidatesByCategory(
        kategorie,
        ageMin: state.alterMin,
        ageMax: state.alterMax,
      );
      state = state.copyWith(kandidaten: kandidaten, laedt: false);
    } catch (e) {
      debugPrint('[FindYourMatchBrowse] Kandidaten laden fehlgeschlagen: $e');
      state = state.copyWith(laedt: false);
    }
  }

  /// Liked einen Kandidaten und nimmt ihn aus der Liste.
  ///
  /// Das Ergebnis des Servers wird durchgereicht (Migration 197):
  /// `is_match` (es ist ein Funke entstanden) und `already_matched`
  /// (es gab schon einen Funke).
  Future<({bool ok, bool isMatch, bool alreadyMatched})> like(
    UserProfile profil,
  ) async {
    try {
      final res = await _service.likeUser(profil.id);
      state = state.copyWith(
        kandidaten: state.kandidaten.where((k) => k.id != profil.id).toList(),
      );
      return (
        ok: true,
        isMatch: res?['is_match'] == true,
        alreadyMatched: res?['already_matched'] == true,
      );
    } catch (e) {
      debugPrint('[FindYourMatchBrowse] Like fehlgeschlagen: $e');
      return (ok: false, isMatch: false, alreadyMatched: false);
    }
  }

  /// Laedt die aktuelle Kategorie neu.
  Future<void> neuLaden() async {
    final kategorie = state.kategorie;
    if (kategorie == null) {
      await loadKategorien();
      return;
    }
    await waehleKategorie(kategorie);
  }
}

/// Der Provider fuer den Kategorie-Browser.
final findYourMatchBrowseProvider =
    StateNotifierProvider<
      FindYourMatchBrowseNotifier,
      FindYourMatchBrowseState
    >((ref) {
      final blickAlter = ref.watch(profileProvider).age ?? 18;
      return FindYourMatchBrowseNotifier(
        ref.watch(findYourMatchServiceProvider),
        blickAlter,
      );
    });
