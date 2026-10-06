import 'dart:math';

/// Poll-Takt des globalen Relay-Eingangs.
///
/// Ausgelagert aus [GlobalRelayInbox], damit die Stufenlogik ohne
/// Widget-Binding testbar ist - ein Timer-Test braucht sonst eine
/// Sekunde Wanduhr pro Stufe.
///
/// Grundregel: JEDER erfolglose Poll (leer ODER Fehler) streckt das
/// Intervall, jeder erfolgreiche stuft zurueck. Vorher zaehlte nur der
/// Leerfall mit: bei totem Netz blieb der Eingang dauerhaft im
/// 6-Sekunden-Takt, ohne Leere und ohne Zustellung als Gegenwert.
class RelayPollBackoff {
  RelayPollBackoff({
    List<Duration>? ladder,
    Duration? baseInterval,
    this.jitterFraction = 0.2,
    Random? random,
  })  : ladder = ladder ??
            const [
              Duration(seconds: 6),
              Duration(seconds: 12),
              Duration(seconds: 25),
              Duration(seconds: 45),
            ],
        baseInterval = baseInterval ??
            (ladder == null || ladder.isEmpty
                ? const Duration(seconds: 6)
                : ladder.first),
        _random = random ?? Random();

  /// Stufen von aktiv nach Ruhezustand.
  final List<Duration> ladder;

  /// Intervall bei frischer Zustellung (kann von `ladder.first`
  /// abweichen, wenn eine eigene Leiter uebergeben wurde).
  final Duration baseInterval;

  /// Streuung gegen synchronizedes Pollen: tausend Clients, die exakt
  /// nach 6 s aufwachen, ergeben eine Spike auf `relay_fetch`.
  /// 0 = aus, 0.2 = +/- 20 Prozent.
  final double jitterFraction;

  final Random _random;

  int _step = 0;

  /// Aktuelle Stufe (0 = schnellstes Intervall).
  int get step => _step;

  /// Intervall fuer den naechsten Poll, inklusive Jitter.
  Duration get next {
    final base = ladder[_step.clamp(0, ladder.length - 1)];
    return _applyJitter(base);
  }

  /// Leerer Poll: eine Stufe langsamer (Deckel bei der letzten Stufe).
  void onEmpty() => _advance();

  /// Fehlgeschlagener Poll: eine Stufe langsampler. Gleiche
  /// Behandlung wie [onEmpty] - ein Fehler ist fuer den Server genauso
  /// "nichts zu liefern" wie eine leere Antwort.
  void onFailure() => _advance();

  /// Zustellung war erfolgreich: sofort zurueck auf das Basisintervall.
  void onDelivered() => _step = 0;

  /// Vordergrund-Wechsel: frisch starten (der Nutzer soll beim
  /// Zurueckkommen sofort sehen, was angekommen ist).
  void reset() => _step = 0;

  void _advance() {
    if (_step < ladder.length - 1) _step++;
  }

  Duration _applyJitter(Duration base) {
    if (jitterFraction <= 0) return base;
    final ms = base.inMilliseconds;
    final spread = (ms * jitterFraction).round();
    if (spread <= 0) return base;
    // Untergrenze 1 ms, damit ein sehr kurzes Intervall nicht auf 0 faellt.
    return Duration(milliseconds: max(1, ms + _random.nextInt(2 * spread + 1) - spread));
  }
}
