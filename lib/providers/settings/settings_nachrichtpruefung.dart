// Die Schalter der Nachrichten-Prüfung (NUTZERWUNSCH 26.11.2026).
//
// DER WEG: Die Datei settings_provider.dart war über der Grenze von 1000
// Zeilen (test/code_datei_groessen_test.dart). Die Schalter stehen in
// einer Erweiterung - der Aufrufer merkt davon nichts (`notifier
// .setNachrichtPruefModus(...)`).
//
// DER ZUSTAND: `state` ist geschützt - die Erweiterung darf ihn nicht
// setzen. Deshalb gibt es in der Klasse drei Zugänge, die genau das
// eine tun, was hier gebraucht wird.
part of 'settings_provider.dart';

/// Die Schalter der Nachrichten-Prüfung.
extension NachrichtPruefSettings on SettingsNotifier {
  /// Der Modus für alle Kontakte.
  ///
  /// NUTZERWUNSCH (26.11.2026): Vor dem Senden fragen, wie der Nutzer
  /// die Nachricht selbst versteht - und ob sie so bleiben soll.
  Future<void> setNachrichtPruefModus(NachrichtPruefModus modus) async {
    await setzeNachrichtPruefModus(modus.wert);
  }

  /// Ab wie vielen Zeichen geprüft wird.
  ///
  /// Die Grenze liegt bei 50 bis 2000 Zeichen - darunter wäre die
  /// Prüfung sinnlos, darüber wäre sie unbenutzbar.
  Future<void> setNachrichtPruefSchwelle(int zeichen) async {
    await setzeNachrichtPruefSchwelle(zeichen);
  }

  /// Die Ausnahme für einen Kontakt (null = keine Ausnahme).
  ///
  /// DER WEG: `null` entfernt die Ausnahme - dann gilt wieder der
  /// globale Wert. So kann der Nutzer beides: global etwas setzen und
  /// für einzelne Kontakte etwas anderes.
  Future<void> setNachrichtPruefAusnahme(
    String kontaktId,
    NachrichtPruefModus? modus,
  ) async {
    await setzeNachrichtPruefAusnahme(kontaktId, modus?.wert);
  }
}
