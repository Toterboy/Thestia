/// Grobung der Entfernung fuer die Anzeige bei anderen Nutzern.
///
/// Grundsatz (Nutzerwunsch 2026-10-06): andere sollen wissen, OB jemand
/// nah oder weit weg ist - "ich in Bremen, die andere Person in
/// Niedersachsen" ist bereits eine Information. Nicht mehr: kein Ort, kein
/// exakter Standort, keine Meter.
///
/// Deshalb zwei Stufige Grobung, in dieser Reihenfolge:
///
///  1. **Kaskadierung von innen.** Eine Person 200 km entfernt ist
///     "ueber 100 km", nicht "180 km". Alle werden mit 10-km-Stufen
///     feiner, je naeher desto genauer - wer nah wohnt, erfaehrt auch
///     mehr, aber eben nur in Stufen.
///  2. **Rundung auf 10 km**, nicht auf 5. 5 km waren in der
///     Anforderung als *Raster fuer die Speicherung* gemeint; fuer die
///     *Anzeige* waeren 5-km-Stufen genau die Genauigkeit, die man
///     eigentlich loswerden wollte.
///
/// Fuer weniger als 10 km wird bewusst nur "unter 10 km" gesagt: die
/// erste Stufe enthielte sonst die Information "weniger als 10 km",
/// gefolgt von "10 bis 20 km" - ein Sprung, der sich sauber anfaengt,
/// sobald man die Nachkommastelle weglässt.
class DistanceBucket {
  const DistanceBucket._();

  /// Obergrenze der Stufe in km. `null` heisst: ueber der letzten Stufe,
  /// die Zahl wird bewusst nicht verraten.
  static const int lastThresholdKm = 100;

  /// Anzahl der beschrifteten Stufen unterhalb von [lastThresholdKm].
  /// 10-20, 20-30, ... 90-100 = 9 Stufen, plus "unter 10" = 10.
  static const int stepCount = 10;

  /// Stufenbreite in km fuer die Anzeige.
  static const int stepKm = 10;

  /// Untergrenze in km fuer eine ueberhaupt sichtbare Entfernung.
  ///
  /// Alles darunter bekommt keinen Bucket. 5 km sind zwar "nah", aber
  /// in einem Land mit Millionen Einwohnern kann der Unterschied
  /// zwischen 2 und 4 km den Nachbarn verraten.
  static const int visibleFromKm = 5;

  /// Stufe einer Entfernung, oder `null` wenn zu klein zum Zeigen.
  ///
  /// [km] = untere Schranke der Stufe, [kmUpper] = obere Schranke.
  /// Beide null = ueber [lastThresholdKm].
  ///
  /// Die Stufe ist das 10-km-Band `[untere, untere + 10)`, in das [km]
  /// faellt - mathematisch `floor(km / 10) * 10`. Damit ist jede Grenze
  /// genau einmal besetzt: 9,9 -> [0,10), 10,0 -> [10,20), 19,9 -> [10,20),
  /// 20,0 -> [20,30). Ein "rundet bei exakter Grenze nach oben"-Zweig
  /// waere hier falsch und wuerde 10 km als "20 bis 30" ausgeben.
  static ({int? km, int? kmUpper})? bucketFor(double? km) {
    if (km == null || km.isNaN) return null;
    if (km < visibleFromKm) return null;
    if (km >= lastThresholdKm) return (km: lastThresholdKm, kmUpper: null);

    final lower = (km / stepKm).floor() * stepKm;
    if (lower >= lastThresholdKm) {
      return (km: lastThresholdKm, kmUpper: null);
    }
    return (km: lower, kmUpper: lower + stepKm);
  }

  /// Der lokalisierte Text fuer eine Stufe.
  ///
  /// Der Aufrufer gibt [L10n.t] als Funktion, damit dieses Widget ohne
  /// BuildContext und damit testbar bleibt.
  static String label(
    ({int? km, int? kmUpper}) bucket,
    String Function(String key) t,
  ) {
    final km = bucket.km;
    final upper = bucket.kmUpper;
    if (km == null) return t('distance.bucketUnknown');
    if (upper == null) {
      return t('distance.bucketOver').replaceAll('{km}', '$km');
    }
    if (km == 0) {
      return t('distance.bucketUnder').replaceAll('{km}', '$upper');
    }
    return t('distance.bucketRange')
        .replaceAll('{from}', '$km')
        .replaceAll('{to}', '$upper');
  }

  /// Bequemlichkeit: Stufe + Text in einem Aufruf.
  static String? labelForKm(double? km, String Function(String key) t) {
    final b = bucketFor(km);
    return b == null ? null : label(b, t);
  }
}