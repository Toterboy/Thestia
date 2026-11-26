/// Die Einstellungen der eigenen Tastatur (0.11.0).
///
/// NUTZERWUNSCH (23.11.2026, 0.11.0): "Die eigene Tastatur wird
/// einstellbar" - der Hintergrund und die Belegung.
///
/// DER WEG: Die App-Tastatur (Build 54, v0.10.1) war an zwei Stellen
/// fest verdrahtet: die **Belegung** folgte der Sprache der App
/// (`L10n.localeOf(context)`), und die **Farben** kamen aus dem
/// App-Thema. Beides wird jetzt einstellbar.
///
/// WARUM ZWEI EINSTELLUNGEN: Die App-Sprache ist ein **Inhaltsthema**,
/// die Tastatur ein **Werkzeug** - sie gehören nicht zusammen. Wer auf
/// Deutsch schreibt, aber in einer englischen Umgebung arbeitet, will
/// die App-Sprache ändern, ohne dass sich die Tasten verschieben.
///
/// DIE DATEN: Beide Schalter stehen in `profiles.ui_prefs` (jsonb) - es
/// kommen zwei Schlüssel dazu, keine neue Spalte, keine Migration.
library;

/// Wie die eigene Tastatur belegt ist.
enum TastaturBelegung {
  /// Wie die Sprache der App (Voreinstellung).
  ///
  /// Deutsch → QWERTZ mit ä, ö, ü, ß; Englisch → QWERTY.
  wieApp,

  /// Immer deutsch (QWERTZ), auch wenn die App auf Englisch steht.
  deutsch,

  /// Immer englisch (QWERTY), auch wenn die App auf Deutsch steht.
  englisch,
}

/// Wie die eigene Tastatur gefärbt ist.
enum TastaturStil {
  /// Wie die App (Voreinstellung): die Tasten nehmen die Flächenfarben
  /// des App-Themas.
  wieApp,

  /// In der Farbe der App: die Tasten und die Aktionstasten bekommen
  /// die Akzentfarbe der gewählten Farbwelt. Der Text darauf muss in
  /// beiden Helligkeiten lesbar bleiben.
  appFarbe,

  /// In einer eigenen Farbe (ein selbst gewählter Farbton).
  eigeneFarbe,
}

/// Der Text in der eigenen Sprachform - für die Speicherung.
extension TastaturBelegungWert on TastaturBelegung {
  /// Der Wert, der in den Einstellungen steht.
  String get wert => switch (this) {
    TastaturBelegung.wieApp => 'wieApp',
    TastaturBelegung.deutsch => 'deutsch',
    TastaturBelegung.englisch => 'englisch',
  };

  /// Liest die Belegung aus dem gespeicherten Text.
  ///
  /// Unbekanntes wird zu [TastaturBelegung.wieApp] - ein kaputter Wert
  /// darf die Tastatur nicht verschieben.
  static TastaturBelegung ausWert(String? wert) {
    return TastaturBelegung.values.firstWhere(
      (b) => b.wert == wert,
      orElse: () => TastaturBelegung.wieApp,
    );
  }
}

/// Der Text in der eigenen Sprachform - für die Speicherung.
extension TastaturStilWert on TastaturStil {
  /// Der Wert, der in den Einstellungen steht.
  String get wert => switch (this) {
    TastaturStil.wieApp => 'wieApp',
    TastaturStil.appFarbe => 'appFarbe',
    TastaturStil.eigeneFarbe => 'eigeneFarbe',
  };

  /// Liest den Stil aus dem gespeicherten Text.
  static TastaturStil ausWert(String? wert) {
    return TastaturStil.values.firstWhere(
      (s) => s.wert == wert,
      orElse: () => TastaturStil.wieApp,
    );
  }
}
