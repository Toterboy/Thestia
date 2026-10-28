import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/services/local_storage.dart';

/// Schluessel der angepinnten Funken in der lokalen Speicherung.
const pinnedMatchesPrefsKey = 'pinned_matches';

/// Die angepinnten Funken (NUTZERWUNSCH, 28.10.2026: "sowie Einstellungen
/// haben, wie Funke löschen, fixieren, archivieren").
///
/// LOKAL und nicht auf dem Server - mit Absicht:
///
///   * "Fixieren" ist eine Anordnung, keine Datenbeziehung. Sie gehoert
///     dem Geraet, auf dem man sie macht - wie eine Merkliste im
///     Telefonbuch.
///   * Es braucht keine Migration, keine neue Spalte in `matches` und
///     keinen neuen RPC. Ein Server-Feld waere hier eine
///     Ueberdimensionierung: es aendert sich nie fuer andere und
///     braucht Regeln, wer es setzen darf.
///
/// Gespeichert wird die Liste der Match-IDs als JSON-Array.
class PinnedMatchesNotifier extends StateNotifier<Set<int>> {
  PinnedMatchesNotifier(this._ref) : super(<int>{}) {
    _lade();
  }

  final Ref _ref;

  /// Setzt oder entfernt die Pinnung eines Funken.
  ///
  /// Gibt zurueck, ob der Funke jetzt angepinnt ist (true) oder nicht
  /// (false) - der Aufrufer kann das fuer eine Meldung nutzen.
  Future<bool> umschalten(int matchId) async {
    final neu = {...state};
    if (!neu.remove(matchId)) {
      neu.add(matchId);
    }
    state = neu;
    await _speichere();
    return neu.contains(matchId);
  }

  /// Laedt die Liste aus der lokalen Speicherung.
  Future<void> _lade() async {
    try {
      final wert = await _ref
          .read(localStorageProvider)
          .getString(pinnedMatchesPrefsKey);
      if (wert == null || wert.isEmpty) return;
      final liste = jsonDecode(wert);
      if (liste is! List) return;
      state = liste.whereType<int>().toSet();
    } catch (e) {
      // Der Pin ist eine Bequemlichkeit - wenn die Speicherung nicht
      // klappt, darf die App daran nicht scheitern.
      debugPrint('[PinnedMatches] Laden fehlgeschlagen: $e');
    }
  }

  /// Schreibt die Liste in die lokale Speicherung.
  Future<void> _speichere() async {
    try {
      await _ref
          .read(localStorageProvider)
          .saveString(pinnedMatchesPrefsKey, jsonEncode(state.toList()));
    } catch (e) {
      debugPrint('[PinnedMatches] Speichern fehlgeschlagen: $e');
    }
  }
}

/// Die angepinnten Funken (IDs der Matches).
final pinnedMatchesProvider =
    StateNotifierProvider<PinnedMatchesNotifier, Set<int>>((ref) {
  return PinnedMatchesNotifier(ref);
});
