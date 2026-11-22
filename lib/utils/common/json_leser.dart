// Defensive Leser fuer JSON aus fremden Quellen.
//
// WOFUER (22.11.2026, Fuzzing): Die App bekommt Daten von aussen -
// vom Server und (ueber das Relay und den Peer-zu-Peer-Kanal) von der
// GEGENSEITE. Wer diese Daten bessaessigt, darf die App nicht zum
// Absturz bringen.
//
// DER BEFUND DES FUZZINGS: Ein Cast wie `json['photos'].map((e) => e
// as String)` wirft, sobald der Absender eine Zahl statt eines Textes
// liefert. Dasselbe gilt fuer `json['alter'] as int?` (ein 18.5 wirft),
// fuer `DateTime.parse(json['started_at'] as String)` (ein fehlendes
// Feld wirft) und fuer `json['timestamp'] as int`.
//
// DAS HIER: Ein Satz Leser, der niemals wirft. Jeder liefert null
// (oder eine leere Liste), wenn der Wert nicht passt. Die Modelle
// benutzen ihn statt der Casts.
//
// DIE REGEL: Ein Cast auf einen fremden Wert ist immer ein Fehler. Ein
// Cast auf einen WERT, den der eigene Code geschrieben hat, ist in
// Ordnung - dann ist es eine Internal-Assertion.
library;

/// Liest den ersten passenden Schluessel als Text.
///
/// [schluessel] werden in der Reihenfolge probiert (z. B. `['user_id',
/// 'id']` - der Server liefert mal das eine, mal das andere).
String? textOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert == null) continue;
    if (wert is String) return wert;
    // Zahlen und Wahrheitswerte als Text: das Serverformat wechselt
    // gelegentlich (Zahl als String). Ein Objekt oder eine Liste sind
    // aber KEIN Text - da waere das toString() eine Erfindung.
    if (wert is num || wert is bool) return wert.toString();
  }
  return null;
}

/// Liest den ersten passenden Schluessel als Ganzzahl.
///
/// BEFUND (22.11.2026, Fuzzing): `double.nan.toInt()` und
/// `double.infinity.toInt()` WERFEN ("Unsupported operation"). Ein
/// solcher Wert darf die App nicht abstuerzen lassen - er wird wie ein
/// fehlender Wert behandelt.
int? intOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert == null) continue;
    if (wert is int) return wert;
    if (wert is double) {
      if (!wert.isFinite) continue;
      return wert.toInt();
    }
    if (wert is num) {
      if (wert is double && !wert.isFinite) continue;
      return wert.toInt();
    }
    if (wert is String) return int.tryParse(wert);
  }
  return null;
}

/// Liest den ersten passenden Schluessel als Zahl.
///
/// NaN und Infinity sind keine Zahlen, mit denen man rechnen kann -
/// sie werden wie ein fehlender Wert behandelt.
num? numOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert == null) continue;
    if (wert is double) {
      if (!wert.isFinite) continue;
      return wert;
    }
    if (wert is num) return wert;
    if (wert is String) return num.tryParse(wert);
  }
  return null;
}

/// Liest den ersten passenden Schluessel als Wahrheitswert.
///
/// DAS WICHTIGE: `"true"` (Text) wird als WAHR gelesen - das kommt vor
/// (alte Cache-Dateien, manche Serverfelder). Aber `"ja"` oder `1` sind
/// KEIN Wahrheitswert: da liefert der Leser null, und der Aufrufer
/// entscheidet selbst (der Unterschied zwischen "nein" und "unbekannt"
/// ist wichtig - z. B. bei den Sichtbarkeits-Schaltern).
bool? boolOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert == null) continue;
    if (wert is bool) return wert;
    if (wert is String) {
      final klein = wert.toLowerCase();
      if (klein == 'true') return true;
      if (klein == 'false') return false;
    }
  }
  return null;
}

/// Liest den ersten passenden Schluessel als Liste von Texten.
///
/// DIE WICHTIGE EIGENSCHAFT: Elemente, die KEIN Text sind, werden
/// uebersprungen - nicht mit einem Cast erzwungen. Vorher stand hier
/// `.map((e) => e as String)`: eine Zahl in der Liste (oder eine
/// verschachtelte Liste) liess die App abstuerzen.
List<String> textListOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert is List) {
      return wert.whereType<String>().toList();
    }
  }
  return const <String>[];
}

/// Liest den ersten passenden Schluessel als Datum.
///
/// Gibt null zurueck, wenn der Wert kein brauchbares Datum ist - ein
/// `DateTime.parse` wirft bei jedem kaputten Text.
///
/// BEFUND (22.11.2026, Fuzzing): `DateTime.fromMillisecondsSinceEpoch`
/// wirft bei Werten ausserhalb des gueltigen Bereichs (RangeError). Ein
/// Zeitstempel aus der Zukunft um 500 Millionen Jahre ist kein Datum,
/// sondern Muell - er wird verworfen.
DateTime? dateOf(Map<String, dynamic> json, List<String> schluessel) {
  for (final name in schluessel) {
    final wert = json[name];
    if (wert == null) continue;
    if (wert is DateTime) return wert;
    if (wert is String) return DateTime.tryParse(wert);
    if (wert is int) {
      if (wert < _minEpochMs || wert > _maxEpochMs) continue;
      return DateTime.fromMillisecondsSinceEpoch(wert);
    }
    if (wert is double) {
      if (!wert.isFinite) continue;
      if (wert < _minEpochMs || wert > _maxEpochMs) continue;
      return DateTime.fromMillisecondsSinceEpoch(wert.toInt());
    }
  }
  return null;
}

/// Der kleinste Zeitstempel, den Dart darstellen kann.
const int _minEpochMs = -8640000000000000;

/// Der groesste Zeitstempel, den Dart darstellen kann.
const int _maxEpochMs = 8640000000000000;
