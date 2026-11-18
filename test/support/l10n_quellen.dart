/// Die Texte der App (alle Dateien unter `lib/l10n/strings/`).
///
/// DIE TEXTE LIEGEN NACH THEMEN GETRENNT: `lib/l10n/app_strings.dart` ist
/// nur noch die Zusammenfuehrung. Tests, die die Texte statisch lesen
/// (z. B. um zu pruefen, ob ein Schluessel in beiden Sprachen da ist),
/// brauchen beide Sprachen getrennt - deshalb gibt es hier beides.
///
/// Die Reihenfolge ist nach dem Namen sortiert - damit sind die Zeilen
/// stabil und ein Test, der auf eine Zeilennummer zeigt, meint dieselbe.
library;

import 'dart:io';

/// Die Dateien mit den Texten (nach dem Namen sortiert).
List<File> _textDateien() {
  final ordner = Directory('lib/l10n/strings');
  if (!ordner.existsSync()) {
    throw StateError(
      'Der Ordner lib/l10n/strings/ fehlt - die Texte wurden verschoben?',
    );
  }
  final dateien =
      ordner
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return dateien;
}

/// Die schliessende Klammer der Karte (und der Datei) wegnehmen.
///
/// DER WEG: Nur die Klammer am ENDE einer Zeile wegnehmen - eine Zeile
/// mit Text (z. B. `'x': '}'`) darf nicht beschädigt werden.
String _ohneSchluss(String text) {
  var rest = text.trimRight();
  // zweimal: einmal die Karte ("},") und einmal die Datei ("};").
  for (var i = 0; i < 2; i++) {
    rest = rest.replaceFirst(RegExp(r'\n\s*\};?,?\s*$'), '');
  }
  return rest;
}

/// Die Sprachbloecke je Datei (ohne die schliessenden Klammern).
List<({String de, String en})> _bloecke() {
  final ergebnis = <({String de, String en})>[];
  for (final datei in _textDateien()) {
    final src = datei.readAsStringSync();
    final deStart = src.indexOf("  'de': {");
    final enStart = src.indexOf("  'en': {");
    if (deStart < 0 || enStart < 0) continue;
    ergebnis.add((
      de: _ohneSchluss(src.substring(deStart + "  'de': {".length, enStart)),
      en: _ohneSchluss(src.substring(enStart + "  'en': {".length)),
    ));
  }
  return ergebnis;
}

/// Alle Texte der App als eine Datei: erst der deutsche Teil (alle
/// Themen), dann der englische (alle Themen).
///
/// So findet ein Test mit `indexOf("'de': {")` und `indexOf("'en': {")`
/// wieder beide Sprachen - genau wie es vor der Aufteilung war.
String liesL10nQuellen() {
  final bloecke = _bloecke();
  final de = bloecke.map((b) => b.de).join('\n');
  final en = bloecke.map((b) => b.en).join('\n');
  return "  'de': {\n$de\n  },\n  'en': {\n$en\n  },\n";
}

/// Nur der deutsche Teil der Texte.
String liesL10nQuellenDe() {
  final de = _bloecke().map((b) => b.de).join('\n');
  return "  'de': {\n$de\n";
}

/// Nur der englische Teil der Texte.
String liesL10nQuellenEn() {
  final en = _bloecke().map((b) => b.en).join('\n');
  return "  'en': {\n$en\n";
}
