// Die Schalter der eigenen Tastatur (0.11.0).
//
// DER WEG: Die eigene Tastatur (Build 54, v0.10.1) war an zwei Stellen
// fest verdrahtet: die Belegung folgte der Sprache der App, die Farben
// kamen aus dem App-Thema. Beides ist jetzt einstellbar.
//
// Die Datei ist ein eigener Teil, weil die Hauptdatei sonst über der
// Grenze von 1000 Zeilen läge (test/code_datei_groessen_test.dart).
part of 'settings_provider.dart';

/// Die Schalter der eigenen Tastatur.
extension TastaturSettings on SettingsNotifier {
  /// Die Belegung: QWERTZ, QWERTY oder "wie die App".
  ///
  /// DER WEG: Die Belegung war ein Nebenprodukt des Sprachumschalters.
  /// Wer auf Deutsch schreibt, aber in einer englischen Umgebung
  /// arbeitet, will die App-Sprache ändern, ohne dass sich die Tasten
  /// verschieben - und umgekehrt.
  Future<void> setTastaturBelegung(TastaturBelegung belegung) async {
    await setzeTastaturWerte(belegung: belegung.wert);
  }

  /// Der Stil: wie die App, in der Farbe der App oder eine eigene Farbe.
  Future<void> setTastaturStil(TastaturStil stil) async {
    await setzeTastaturWerte(stil: stil.wert);
  }

  /// Die eigene Farbe; null = keine eigene Farbe (wieder der App-Thema).
  Future<void> setTastaturFarbe(int? farbe) async {
    await setzeTastaturWerte(farbe: farbe, farbeSetzen: true);
  }
}
