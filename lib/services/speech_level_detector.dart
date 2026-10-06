/// Erkennt, ob in einer Aufnahme wirklich etwas gesagt wird.
///
/// Anlass: eine Aufnahme konnte 10 Sekunden und mehr vollstaendig still
/// sein und wurde danach trotzdem akzeptiert. Der Mindestlaengen-Check
/// im Review-Sheet prueft nur die *Dauer* - 10 Sekunden Rauschen auf
/// Zimmerlautigkeit sind auch 10 Sekunden lang.
///
/// Entscheidung bewusst simpel und ohne Frequenzanalyse: der Nutzer
/// will "habe ich etwas gesagt", nicht "war die Aufnahme akustisch
/// sauber". Ein Schwellwert ueber dem Ruhepegel reicht dafuer, und er
/// ist auf jedem Geraet gleich reproduzierbar - im Gegensatz zu einem
/// Verdeutlichungs- oder Klangerkennungs-Modell, das auf einem
/// testaerkenden Raum falsch entscheidet.
class SpeechLevelDetector {
  /// Pegel in dBFS, oberhalb dessen von gesprochenem Ton ausgegangen
  /// wird.
  ///
  /// -34 dBFS ist bewusst tief angesetzt: Stille im Handylautsprecher
  /// liegt meist bei -55 bis -65 dBFS, normales Sprechen im 10-cm-
  /// Abstand bei -30 bis -20 dBFS. Wer sein Handy 40 cm weg haelt,
  /// spricht leiser und wuerde mit einem zu hohen Wert (z. B. -20) als
  /// "still" eingestuft und zur Wiederholung gezwungen.
  static const double speechThresholdDb = -34;

  /// dBFS, unterhalb dessen garantiert nichts mehr als Rauschen ist.
  ///
  /// -60 dBFS ist die Untergrenze der Anzeigenormalisierung und gilt
  /// praktisch als Rauschteppich. Alles darunter wird als -inf behandelt.
  static const double noiseFloorDb = -60;

  /// Toleranz gegen kurze Pausen: bis zu dieser Anzahl aufeinander
  /// folgender stiller Messungen gilt die Sequenz noch als "wird
  /// gesprochen".
  ///
  /// Bei 10 Hz sind das 1,5 s. Ohne Toleranz wuerde jedes laengere
  /// Denken ("aehm... was sag ich") als Stille gewertet und die
  /// Aufnahme verworfen - obwohl der Nutzer sehr wohl geredet hat.
  static const int pauseTolerance = 15;

  /// Erzeugt aus einem Rohwert (dBFS) ein Level, das die Vergleichs-
  /// logik unverwirrbar macht: `null` bedeutet "unterhalb des
  /// Rauschteppichs", sonst der Pegel selbst.
  ///
  /// Ohne diese Normalisierung kaeme NaN herein: `record` liefert bei
  /// Stille teils `0` (was 0 dBFS waere und damit Maximum), teils
  /// einen sehr kleinen Wert. Beides darf nicht als "laut" gelten.
  static double? normalize(double? rawDb) {
    if (rawDb == null || rawDb.isNaN) return null;
    if (rawDb <= noiseFloorDb) return null;
    return rawDb;
  }

  /// Kurz, aber mit allem, was die Entscheidung braucht.
  static bool isAudible(double? rawDb) {
    final db = normalize(rawDb);
    return db != null && db > speechThresholdDb;
  }

  final List<double?> _samples = <double?>[];
  final int _maxSamples;

  SpeechLevelDetector({int window = 60})
      : _maxSamples = window < 1 ? 1 : window;

  /// Anzahl der gehaltenen Messungen (10 Hz => 60 = 6 Sekunden).
  int get windowSeconds => _maxSamples ~/ 10;

  /// Bisheriger Höchstwert im Fenster, in dBFS, oder null bei Stille.
  double? get peakDb {
    double? best;
    for (final s in _samples) {
      if (s != null && (best == null || s > best)) best = s;
    }
    return best;
  }

  /// Ob bislang etwas gehört wurde.
  bool get hasSpeech => _samples.any((s) => s != null && s > speechThresholdDb);

  /// Anzahl aufeinanderfolgender stiller Messungen am Fensterende.
  int get trailingSilenceCount {
    var n = 0;
    for (var i = _samples.length - 1; i >= 0; i--) {
      final s = _samples[i];
      if (s != null && s > speechThresholdDb) break;
      n++;
    }
    return n;
  }

  /// Ob gerade Stille am Ende herrscht (mit Toleranz gegen Pausen).
  ///
  /// `requiredMs` erlaubt, dem Nutzer Zeit zum Sprechen zu geben, bevor
  /// gemeldet wird - 1500 ms entspricht der [pauseTolerance].
  bool get isSilentTail => trailingSilenceCount >= pauseTolerance;

  /// Eine Messung aufnehmen. Gibt zurueck, ob der Zustand gekippt ist.
  ///
  /// Der Rueckgabewert spart dem Widget einen [setState]: nur wenn sich
  /// das Ergebnis aendert, muss neu gebaut werden.
  bool addSample(double? rawDb) {
    final before = hasSpeech;
    _samples.add(normalize(rawDb));
    while (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
    return before != hasSpeech;
  }

  /// Zustand zuruecksetzen (neue Aufnahme).
  void reset() => _samples.clear();

  /// Kurzes Label fuer die Anzeige: der auf 5 km gerundete Weg ist hier
  /// nicht gemeint - der Pegel wird als "Hoehe" bzw. "Stille" gezeigt.
  ///
  /// Gehoert hierher, weil die Entscheidung "wie viel Hoehe braucht man
  /// noch" an dieselbe Zahl gebunden ist wie die Schwellen.
  static int peakToPercent(double? db) {
    final n = normalize(db);
    if (n == null) return 0;
    final from = noiseFloorDb;
    final to = 0.0;
    final pct = (n - from) / (to - from) * 100;
    return pct.clamp(0, 100).round();
  }

  /// Etwas zu viel Mathematik fuer einen Widget, aber hier gehoert es
  /// hin: die Anzeige soll die *gleiche* Zahl zeigen wie die
  /// Entscheidung, nicht eine zusaetzlich gerundete.
  static double dbToLevel01(double? db) {
    final n = normalize(db);
    if (n == null) return 0;
    return ((n - noiseFloorDb) / (0.0 - noiseFloorDb)).clamp(0.0, 1.0);
  }

  /// Mittelwert im Fenster, fuer eine ruhigere Anzeige als den Peak.
  ///
  /// Bewusst ohne die Max-Funktion: der Peak ist fuer die Entscheidung
  /// da, der Mittelwert nur fuer die Anzeige, und ein zweiter
  /// Normalisierungspfad waere eine zweite Stelle, an der ein Fehler
  /// entstehen kann.
  double? get averageDb {
    final present = _samples.whereType<double>().toList();
    if (present.isEmpty) return null;
    final sum = present.fold<double>(0, (a, b) => a + b);
    return sum / present.length;
  }

  /// Beschreibung fuer Screenreader / Semantik.
  static String describe({required bool silent, required double? peakDb}) {
    if (!silent) return 'Ton erkannt';
    final p = peakToPercent(peakDb);
    if (p <= 0) return 'Nur Stille';
    return 'Sehr leise ($p %)';
  }
}