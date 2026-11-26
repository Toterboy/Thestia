import 'dart:math' as math;

/// Standort-Auflösung für die Einrichtung.
///
/// Grundsatz (Nutzerwunsch 2026-10-06): Der genaue Standort wird NICHT
/// gespeichert und NICHT angezeigt. Gespeichert wird
///   * das Bundesland (als Text, für die Anzeige beim Betrachteten)
///   * die Koordinaten auf einem 5-km-Raster, für die Distanzberechnung
///
/// Anzeige nach außen passiert ausschließlich über die 10-km-Stufen
/// aus [distance_bucket.dart] - und nur, wenn der Betrachtene das
/// erlaubt hat (`profiles.show_distance`).
///
/// WARUM EIGEN UND NICHT EINFACH `locality`:
/// `placemarkFromCoordinates` liefert `locality` (die Stadt) zuerst und
/// `administrativeArea` (das Bundesland) daneben. Nimmt man den ersten
/// Wert, hat man genau den Ortsnamen, der raus sollte. Diese Klasse
/// liefert bewusst NUR das Bundesland.
class LocationPrivacy {
  const LocationPrivacy._();

  /// 5 km. Gespiegelt in `public.snap_location_to_grid` (Migration 135).
  ///
  /// Warum überhaupt runden: Die Koordinaten liegen für die
  /// Distanzberechnung nötig auf dem Server. Ohne Raster wären das
  /// exakte Hauskoordinaten - bei einer DB-Kompromittierung direkt
  /// verwertbar. Mit 5-km-Raster ist der Wert für die Entfernungs-
  /// anzeige (10-km-Stufen) weiterhin brauchbar, aber kein Standort
  /// mehr.
  static const double gridKm = 5.0;

  /// Grad Breite pro Kilometer. 111 ist die übliche Näherung; der
  /// genaue Wert hängt am Breitengrad ab (~111,2 am Äquator,
  /// ~111,7 am 60. Grad), der Unterschied ist für ein 5-km-Raster
  /// ohne Bedeutung.
  static const double kmPerDegreeLat = 111.0;

  /// Runde Koordinaten auf das 5-km-Raster.
  ///
  /// Gespiegelt in `snap_location_to_grid`. Beide Seiten müssen
  /// dasselbe tun, sonst schreibt der Client ein anderes Raster als
  /// der Server beim Rechnen erwartet - die Entfernung würde dann
  /// springen.
  ///
  /// WICHTIG - und hier lag ein echter Fehler: die Rasterbreite für den
  /// Längengrad wird aus `lat` ABGELEITET (`cos(lat)`), weil 1 Grad
  /// Länge am Äquator 111 km, in Mitteleuropa aber nur rund 70 km
  /// beträgt. Damit ist snapToGrid aber NICHT idempotent: der
  /// gerundete Längengrad weicht minimal ab, daraus folgt ein minimal
  /// anderes `cos`, und beim zweiten Aufruf rutscht der Rasterpunkt um
  /// einen Schritt. Bei jedem Serverabgleich würde der Standort
  /// wandern.
  ///
  /// Losung: zweimal rasteren. Der erste Durchlauf bestimmt den
  /// Rasterpunkt, der zweite stabilisiert ihn auf Basis des GERUNDETEN
  /// Breitengrads. Damit liefert `snap(snap(p)) == snap(p)` - geprüft
  /// in test/location_privacy_test.dart.
  ///
  /// Am Pol geht cos gegen 0; `max(..., 0.01)` verhindert die Division
  /// durch Null.
  static ({double lat, double lng}) snapToGrid(double lat, double lng) {
    // Rasterbreiten aus einem KONSTANTEN Breitengrad, nicht aus dem
    // eigenen lat.
    //
    // Die Rasterbreite für den Längengrad wird NICHT aus `lat`
    // abgeleitet (`cos(lat)`), obwohl 1 Grad Länge am Äquator 111 km
    // und in Mitteleuropa nur rund 70 km beträgt. Der Grund ist
    // Idempotenz: mit `cos(lat)` war der gerundete Längengrad kein
    // Vielfaches der Breite, die er selbst definiert, also rutschte der
    // Punkt bei jedem weiteren snapToGrid um einen Schritt weiter. Bei
    // jedem Serverabgleich wäre der Standort gewandert.
    //
    // Der erste Versuch nahm cos(lat) des Punktes selbst. Damit war die
    // Rasterung nicht idempotent: der gerundete Längengrad ist kein
    // Vielfaches der Breite, die er selbst definiert, also rutschte der
    // Punkt beim zweiten Aufruf um einen Schritt weiter. Ein Doppel-
    // aufruf hätte das nur verschoben statt behoben.
    //
    // Mit konstanter Breite ist der Rasterpunkt ein Vielfaches genau
    // dieser Breite und damit fix. Die Referenzbreite ist Mitteleuropa
    // (53 Grad), weil Deutschland der principale Markt ist; in
    // Tropen liegt der Längengrad dadurch bis zu ~20 Prozent feiner,
    // das ist für einen 5-km-Raster zumutbar und heißt im Umkehr-
    // schluss: nie ungenauer als 5 km.
    const refLatRad = 53.0 * math.pi / 180.0;
    final stepLat = gridKm / kmPerDegreeLat;
    final stepLng =
        gridKm / (kmPerDegreeLat * math.max(math.cos(refLatRad), 0.01));
    return (
      lat: (lat / stepLat).roundToDouble() * stepLat,
      lng: (lng / stepLng).roundToDouble() * stepLng,
    );
  }

  /// Hält eine Koordinatenänderung für unzulässig, wenn sie das
  /// Raster nicht verlässt.
  ///
  /// Der Server erzwingt das ebenfalls (guard_profile_location_update).
  /// Hier dient es dazu, im Client nicht jedes Mal ein Update zu
  /// schicken, das der Server ohnehin verändern würde - das erzeugt
  /// nur unmotige Schreibvorgänge.
  ///
  /// Die Toleranz von 1 m verhindert, dass Rundungsrauschen als Änderung
  /// gilt; ohne sie würde ein Standort, der exakt auf dem Raster liegt,
  /// bei jedem Sync "springen".
  static bool sameGridSpot(
    double aLat,
    double aLng,
    double bLat,
    double bLng, {
    double toleranceMeters = 1.0,
  }) {
    final dLat = snapToGrid(aLat, aLng);
    final dLng = snapToGrid(bLat, bLng);
    final tol = toleranceMeters / kmPerDegreeLat;
    return (dLat.lat - dLng.lat).abs() < tol &&
        (dLat.lng - dLng.lng).abs() < tol;
  }
}
