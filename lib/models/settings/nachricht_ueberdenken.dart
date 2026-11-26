/// Wie die App vor dem Senden nachfragt (NUTZERWUNSCH 26.11.2026).
///
/// DER WEG: Der Nutzer tippt eine Nachricht und drückt auf "Senden".
/// Bevor sie rausgeht, fragt die App ihn, wie er die Nachricht selbst
/// versteht - und ob sie wirklich so bleiben soll. Damit ist der letzte
/// Moment vor dem Abschicken ein Moment des Nachdenkens.
///
/// Die Stärke hängt an zwei Stellschrauben:
/// * **Wann** geprüft wird (jede Nachricht, nur lange, nur auf Wunsch),
/// * **für wen** (für alle Kontakte oder nur für einen).
enum NachrichtPruefModus {
  /// Kein Nachfragen - die Nachricht geht sofort raus.
  aus,

  /// Jede Nachricht wird vor dem Senden gezeigt.
  immer,

  /// Nur Nachrichten ab einer bestimmten Länge (siehe [NachrichtPruefEinstellung.schwelle]).
  abZeichen,

  /// Nur wenn der Nutzer selbst den Extra-Knopf im Eingabefeld drückt.
  manuell,
}

/// Der Modus in der Form, in der er gespeichert wird.
///
/// DER GRUND: Die Einstellung liegt als Text in den Einstellungen (JSON
/// im Keystore). Eine Zahl wäre kürzer, aber ein Text lässt sich lesen,
/// wenn man die Datei ansieht - und ein unbekannter Text (etwa aus einer
/// älteren App-Version) wird als "aus" gelesen statt als Absturz.
extension NachrichtPruefModusWert on NachrichtPruefModus {
  /// Der Text, der gespeichert wird.
  String get wert => switch (this) {
    NachrichtPruefModus.aus => 'aus',
    NachrichtPruefModus.immer => 'immer',
    NachrichtPruefModus.abZeichen => 'abZeichen',
    NachrichtPruefModus.manuell => 'manuell',
  };

  /// Liest den Modus aus dem gespeicherten Text.
  ///
  /// Unbekanntes wird zu [NachrichtPruefModus.aus] - ein kaputter Wert
  /// darf den Chat nicht blockieren.
  static NachrichtPruefModus ausWert(String? wert) {
    return NachrichtPruefModus.values.firstWhere(
      (m) => m.wert == wert,
      orElse: () => NachrichtPruefModus.aus,
    );
  }
}

/// Die Einstellung "Nachricht überdenken" - mit dem Modus, der Schwelle
/// und den Ausnahmen je Kontakt.
///
/// DIE AUSNAHMEN: Der Nutzer kann global sagen "immer prüfen" und für
/// einen bestimmten Kontakt "nein, da nicht". Oder umgekehrt. Deshalb
/// steht je Kontakt ein eigener Modus - fehlt er, gilt der globale.
class NachrichtPruefEinstellung {
  /// Der Modus für alle Kontakte.
  final NachrichtPruefModus modus;

  /// Ab wie vielen Zeichen geprüft wird (Modus [NachrichtPruefModus.abZeichen]).
  ///
  /// 250 Zeichen sind ungefähr vier Sätze - genug, um sich zu verschreiben,
  /// aber nicht so viel, dass jede kurze Nachricht aufgehalten wird.
  final int schwelle;

  /// Die Ausnahmen je Kontakt (die Kontakt-ID auf den Modus).
  final Map<String, NachrichtPruefModus> ausnahmen;

  const NachrichtPruefEinstellung({
    this.modus = NachrichtPruefModus.aus,
    this.schwelle = 250,
    this.ausnahmen = const <String, NachrichtPruefModus>{},
  });

  /// Der Modus, der für einen Kontakt gilt.
  ///
  /// DER WEG: Die Ausnahme des Kontakts gewinnt - sonst wäre der globale
  /// Wert nur Dekoration.
  NachrichtPruefModus modusFuer(String kontaktId) {
    return ausnahmen[kontaktId] ?? modus;
  }

  /// Muss vor dem Senden nachgefragt werden?
  ///
  /// DER WEG: Im Modus [NachrichtPruefModus.manuell] nur auf Wunsch -
  /// deshalb prüft der Extra-Knopf selbst und ruft diese Methode nicht auf.
  bool prueftNach(String text, String kontaktId) {
    switch (modusFuer(kontaktId)) {
      case NachrichtPruefModus.aus:
        return false;
      case NachrichtPruefModus.immer:
        return true;
      case NachrichtPruefModus.abZeichen:
        return text.length >= schwelle;
      case NachrichtPruefModus.manuell:
        return false;
    }
  }

  /// Zeigt der Extra-Knopf im Eingabefeld den Knopf?
  ///
  /// DER WEG: Bei "aus" gibt es nichts zu tun - der Knopf wäre eine
  /// tote Fläche. In den anderen Modi hilft er: bei "ab Zeichen" prüft
  /// er auch eine kurze Nachricht, bei "immer" ist er nur überflüssig
  /// (und wird deshalb nicht gezeigt).
  bool zeigtKnopf(String kontaktId) {
    final m = modusFuer(kontaktId);
    return m == NachrichtPruefModus.abZeichen ||
        m == NachrichtPruefModus.manuell;
  }
}
