/// Privacy-Härtung für den BLE-Nahbereichsfunk (Transit Spark, v0.9.2).
///
/// WARUM das nötig ist
/// --------------------
/// Ein BLE-Advertising ist kein Funk, den man "verbergen" kann - er wird
/// gesendet. Was man verbergen kann, ist das *Muster*:
///
/// - Ein starrer Advertising-Takt (Android `LOW_LATENCY` ≈ 100 ms) erzeugt
///   über eine ganze Sitzung ein perfekt periodisches Signal.
/// - Eine Token-Rotation im exakt fixen 10-Minuten-Raster ist selbst ein
///   Fingerprint: wer den Wechsel mitzählt, kennt die Periode.
/// - Ohne Hersteller-Filter verarbeitet der Scanner jedes BLE-Paket der
///   Umgebung - das ist seitens der App unsichtbarer Fremdverkehr, kostet
///   aber Akku und erzeugt eine passive "Anwesenheitsanzeige" des Geräts.
///
/// WAS das hier ändert
/// -------------------
/// - Der Advertising-Zyklus wird in unregelmäßigen Abständen neu gestartet
///   ([TransitBlePrivacy.advertiseCycleDelay]) statt durchzulaufen.
/// - Die Token-Rotation jittert um ihre Basisperiode
///   ([TransitBlePrivacy.tokenRotationDelay]).
/// - Der Scan filtert auf die eigene Hersteller-ID und läuft in Impulsen
///   ([TransitBlePrivacy.scanPulseOff]).
///
/// WAS das ausdrücklich NICHT erreicht
/// -----------------------------------
/// Innerhalb eines Bursts sendet der Stack weiter im ~100-ms-Takt. Wer
/// das Burst-Muster selbst mitschreibt, sieht weiterhin ein Signal - es hat
/// nur keine sessionübergreifend konstante Phase mehr. Gegen ein Mitschreiben
/// hilft nur, das Token nicht an Gerätemetadaten zu binden; Gerätename und
/// Tx-Power sind bereits abgeschaltet (siehe MainActivity).
///
/// Die unregelmäßigen Werte kommen aus [Random.secure], damit sie nicht
/// vorhersagbar sind; für Tests kann ein deterministischer Random
/// übergeben werden.
library;

import 'dart:math';

/// Hersteller-ID im Advertising-Payload. Muss zu `addManufacturerData(...)`
/// in `MainActivity.kt` passen, sonst sieht der Scanner nichts.
const int kThestiaManufacturerId = 0xFFFF;

/// Basisperiode der Token-Rotation (bisher: exakt 10 Minuten).
const Duration kTokenRotationBase = Duration(minutes: 10);

/// Jitter-Faktor für die Token-Rotation: 10 min ± 40 % → 6–14 min.
const double kTokenRotationJitter = 0.4;

/// Frühester/spätester Abstand zwischen zwei Advertising-Neustarts.
/// Ein Burst läuft also 20–45 s, dann folgt eine Lücke variabler Länge.
const Duration kAdvertiseCycleMin = Duration(seconds: 20);
const Duration kAdvertiseCycleMax = Duration(seconds: 45);

/// Scan-Impuls: an/aus-Fenster. Der Duty-Cycle bleibt bewusst über 40 %,
/// damit genug Begegnungen erfasst werden - das Matching ist asynchron und
/// rechnet serverseitig mit einem 30-Minuten-Fenster. Einzelne Lücken sind
/// tolerable, ein dauerhaftes Scannen nicht.
const Duration kScanPulseOn = Duration(seconds: 12);
const Duration kScanPulseOffMin = Duration(seconds: 8);
const Duration kScanPulseOffMax = Duration(seconds: 20);

/// Jitter-Funktionen. Alle über [Random] injizierbar, damit die
/// Verteilung deterministisch getestet werden kann.
class TransitBlePrivacy {
  const TransitBlePrivacy._();

  static int _between(Random r, int lo, int hi) => lo + r.nextInt(hi - lo + 1);

  /// Verzögerung bis zum nächsten Advertising-Neustart.
  ///
  /// Wird als Zyklusparameter an die native Seite durchgereicht; dort
  /// wird das Advertising gestoppt und mit frischem Payload gestartet.
  static Duration advertiseCycleDelay({Random? random}) {
    final r = random ?? _secure();
    return Duration(
      milliseconds: _between(r, kAdvertiseCycleMin.inMilliseconds,
          kAdvertiseCycleMax.inMilliseconds),
    );
  }

  /// Nächster Token-Rotationszeitpunkt, mit Jitter um [kTokenRotationBase].
  ///
  /// Ohne Jitter wäre der Rotationszeitpunkt selbst ein Fingerprint.
  static Duration tokenRotationDelay({Random? random}) {
    final r = random ?? _secure();
    final base = kTokenRotationBase.inMilliseconds;
    final spread = (base * kTokenRotationJitter).round();
    return Duration(milliseconds: base - spread + r.nextInt(2 * spread + 1));
  }

  /// Pause zwischen zwei Scan-Impulsen.
  static Duration scanPulseOff({Random? random}) {
    final r = random ?? _secure();
    return Duration(
      milliseconds: _between(
          r, kScanPulseOffMin.inMilliseconds, kScanPulseOffMax.inMilliseconds),
    );
  }

  /// Sicherer Zufall. Fällt nur zurück, wenn [Random.secure] nicht
  /// verfügbar ist - dann ist der Jitter schwächer, aber nicht aus.
  static Random _secure() {
    try {
      return Random.secure();
    } catch (_) {
      return Random(DateTime.now().microsecondsSinceEpoch);
    }
  }
}
