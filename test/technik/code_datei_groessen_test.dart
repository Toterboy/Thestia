// Die Groesse der Codedateien.
//
// ANLASS (18.11.2026): Wunsch des Betreibers: "Diese sind einfach zu
// lang und sollten entsprechend in verschiedene Dateien unterteilt
// werden (Sinnvoll)."
//
// WAS HIER GEPRUEFT WIRD:
//   * keine Datei im App-Code (lib/) und in den Tests ist laenger als
//     1000 Zeilen,
//   * jede Ausnahme ist mit einem GRUND dokumentiert - sie wird also
//     nicht einfach "weil so".
//
// WARUM DIE GRENZE: Eine Datei, die laenger als 1000 Zeilen hat, ist
// schwer zu lesen: Man muss bei jeder Aenderung den ganzen Block
// lesen, Merge-Konflikte sind unausloeslich und die Aenderung wird
// riskant (man fasst die falsche Stelle an). Wer teilt, hat kleinere
// Schritte und kann sie einzeln pruefen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Grenze: eine Datei ueber dieser Zeilenzahl gilt als zu lang.
const int maxZeilen = 1000;

/// Die Dateien, die laenger sein DUERFEN - mit dem Grund.
///
/// DER GRUND FUER DIE AUSNAHMEN: Manche Dateien lassen sich nicht
/// sinnvoll teilen (ein Zustand, der ueber tausend Zeilen geht, laesst
/// sich nur schwer in getrennte Teilstuecke zerlegen, ohne das
/// Verhalten zu aendern). Fuer diese Dateien gilt: beim naechsten
/// Umbau wird geteilt - der Grund hier sagt, warum es noch nicht
/// passiert ist.
const Map<String, String> ausnahmen = <String, String>{
  // Die drei Bildschirme (Chat, Profil-Editor, Einrichtung) sind
  // geteilt: Der AUFBAU liegt in einer Erweiterung (parts/...aufbau.dart),
  // der Rest der Datei (Felder, Methoden, Hilfs-Widgets) in der
  // Hauptdatei. So bleibt keine Datei ueber der Grenze.
  //
  // Die zwei Dienste: Sie sind eine OEFFENTLICHE API (die App ruft die
  // Methoden von aussen auf). Eine Erweiterung ist von aussen nur
  // sichtbar, wenn sie dort im Sichtbereich ist - die Aufrufer kennen
  // sie nicht. Eine Aufteilung in mehrere Klassen waere ein grosser
  // Umbau der Schnittstelle.
  'lib/services/supabase_database_service.dart':
      'Oeffentliche API mit 35 Methoden (Profil, Einrichtung, Verwaltung, '
      'Geraete, Likes, Funken, Transit) - eine Aufteilung in mehrere '
      'Klassen waere ein grosser Umbau der Schnittstelle.',
  'lib/services/webrtc_service.dart':
      'Oeffentliche API des WebRTC-Dienstes (Verbindung, Datenkanal, '
      'Signalisierung) - eine Aufteilung in mehrere Klassen waere ein '
      'grosser Umbau der Schnittstelle.',
  // Die Testdateien sind alle geteilt: Jede geteilte Suite liegt in
  // einem eigenen Unterordner (test/<name>/) mit den Teilen und
  // hilfen.dart. Deshalb braucht hier keine Testdatei eine Ausnahme.
};

/// Die relativen Pfade aller Dart-Dateien unter [wurzel].
List<String> _dateien(String wurzel) {
  final ergebnis = <String>[];
  for (final eintrag in Directory(wurzel).listSync(recursive: true)) {
    if (eintrag is! File) continue;
    if (!eintrag.path.endsWith('.dart')) continue;
    // Der erzeugte Code (Hive-Adapter, die Privacy-Texte) ist Maschinen-
    // text - den teilt man nicht.
    if (eintrag.path.contains(
      '${Platform.pathSeparator}generated${Platform.pathSeparator}',
    )) {
      continue;
    }
    ergebnis.add(eintrag.path.replaceAll('\\', '/'));
  }
  return ergebnis;
}

void main() {
  group('Die Groesse der Codedateien', () {
    test('keine Datei im App-Code ist laenger als 1000 Zeilen', () {
      final zuLang = <String>[];
      for (final pfad in _dateien('lib')) {
        final zeilen = File(pfad).readAsLinesSync().length;
        if (zeilen <= maxZeilen) continue;
        if (ausnahmen.containsKey(pfad)) continue;
        zuLang.add('$pfad ($zeilen Zeilen)');
      }
      zuLang.sort();
      expect(
        zuLang,
        isEmpty,
        reason:
            'Diese Dateien sind zu lang (Grenze: $maxZeilen Zeilen). Bitte '
            'teile sie nach Themen auf - eine Datei, die man nicht mehr '
            'ueberblickt, wird zur Fehlerquelle. Ein Grund fuer eine '
            'Ausnahme steht in der Liste "ausnahmen" (test/'
            'code_datei_groessen_test.dart).',
      );
    });

    test('keine Testdatei ist laenger als 1000 Zeilen', () {
      final zuLang = <String>[];
      for (final pfad in _dateien('test')) {
        final zeilen = File(pfad).readAsLinesSync().length;
        if (zeilen <= maxZeilen) continue;
        if (ausnahmen.containsKey(pfad)) continue;
        zuLang.add('$pfad ($zeilen Zeilen)');
      }
      zuLang.sort();
      expect(
        zuLang,
        isEmpty,
        reason:
            'Diese Testdateien sind zu lang (Grenze: $maxZeilen Zeilen). '
            'Bitte teile sie nach Themen auf.',
      );
    });

    test('die Ausnahmen sind alle noetig', () {
      // Eine Ausnahme, die nicht mehr noetig ist, wird zum Ballast: sie
      // erlaubt wieder zu lange Dateien.
      final ueberfluessig = <String>[];
      for (final pfad in ausnahmen.keys) {
        final datei = File(pfad);
        if (!datei.existsSync()) {
          ueberfluessig.add('$pfad (die Datei gibt es nicht mehr)');
          continue;
        }
        final zeilen = datei.readAsLinesSync().length;
        if (zeilen <= maxZeilen) {
          ueberfluessig.add(
            '$pfad ($zeilen Zeilen - laesst sich nicht mehr '
            'als zu lang bezeichnen)',
          );
        }
      }
      expect(
        ueberfluessig,
        isEmpty,
        reason:
            'Diese Ausnahmen werden nicht mehr gebraucht - bitte entfernen '
            'und die Datei normal pruefen.',
      );
    });
  });
}
