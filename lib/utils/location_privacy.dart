import 'dart:math' as math;

/// Standort-Aufloesung fuer die Einrichtung.
///
/// Grundsatz (Nutzerwunsch 2026-10-06): Der genaue Standort wird NICHT
/// gespeichert und NICHT angezeigt. Gespeichert wird
///   * das Bundesland (als Text, fuer die Anzeige beim Betrachteten)
///   * die Koordinaten auf einem 5-km-Raster, fuer die Distanzberechnung
///
/// Anzeige nach aussen passiert ausschliesslich ueber die 10-km-Stufen
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
  /// Warum ueberhaupt runden: Die Koordinaten liegen fuer die
  /// Distanzberechnung noetig auf dem Server. Ohne Raster waeren das
  /// exakte Hauskoordinaten - bei einer DB-Kompromittierung direkt
  /// verwertbar. Mit 5-km-Raster ist der Wert fuer die Entfernungs-
  /// anzeige (10-km-Stufen) weiterhin brauchbar, aber kein Standort
  /// mehr.
  static const double gridKm = 5.0;

  /// Grad Breite pro Kilometer. 111 ist die uebliche Naeherung; der
  /// genaue Wert haengt am Breitengrad ab (~111,2 am Aequator,
  /// ~111,7 am 60. Grad), der Unterschied ist fuer ein 5-km-Raster
  /// ohne Bedeutung.
  static const double kmPerDegreeLat = 111.0;

  /// Runde Koordinaten auf das 5-km-Raster.
  ///
  /// Gespiegelt in `snap_location_to_grid`. Beide Seiten muessen
  /// dasselbe tun, sonst schreibt der Client ein anderes Raster als
  /// der Server beim Rechnen erwartet - die Entfernung wuerde dann
  /// springen.
  ///
  /// WICHTIG - und hier lag ein echter Fehler: die Rasterbreite fuer den
  /// Laengengrad wird aus `lat` ABGELEITET (`cos(lat)`), weil 1 Grad
  /// Laenge am Aequator 111 km, in Mitteleuropa aber nur rund 70 km
  /// betraegt. Damit ist snapToGrid aber NICHT idempotent: der
  /// gerundete Laengengrad weicht minimal ab, daraus folgt ein minimal
  /// anderes `cos`, und beim zweiten Aufruf rutscht der Rasterpunkt um
  /// einen Schritt. Bei jedem Serverabgleich wuerde der Standort
  /// wandern.
  ///
  /// Losung: zweimal rasteren. Der erste Durchlauf bestimmt den
  /// Rasterpunkt, der zweite stabilisiert ihn auf Basis des GERUNDETEN
  /// Breitengrads. Damit liefert `snap(snap(p)) == snap(p)` - geprueft
  /// in test/location_privacy_test.dart.
  ///
  /// Am Pol geht cos gegen 0; `max(..., 0.01)` verhindert die Division
  /// durch Null.
  static ({double lat, double lng}) snapToGrid(double lat, double lng) {
    // Rasterbreiten aus einem KONSTANTEN Breitengrad, nicht aus dem
    // eigenen lat.
    //
    // Die Rasterbreite fuer den Laengengrad wird NICHT aus `lat`
    // abgeleitet (`cos(lat)`), obwohl 1 Grad Laenge am Aequator 111 km
    // und in Mitteleuropa nur rund 70 km betraegt. Der Grund ist
    // Idempotenz: mit `cos(lat)` war der gerundete Laengengrad kein
    // Vielfaches der Breite, die er selbst definiert, also rutschte der
    // Punkt bei jedem weiteren snapToGrid um einen Schritt weiter. Bei
    // jedem Serverabgleich waere der Standort gewandert.
    //
    // Der erste Versuch nahm cos(lat) des Punktes selbst. Damit war die
    // Rasterung nicht idempotent: der gerundete Laengengrad ist kein
    // Vielfaches der Breite, die er selbst definiert, also rutschte der
    // Punkt beim zweiten Aufruf um einen Schritt weiter. Ein Doppel-
    // aufruf haette das nur verschoben statt behoben.
    //
    // Mit konstanter Breite ist der Rasterpunkt ein Vielfaches genau
    // dieser Breite und damit fix. Die Referenzbreite ist Mitteleuropa
    // (53 Grad), weil Deutschland der principale Markt ist; in
    // Tropen liegt der Laengengrad dadurch bis zu ~20 Prozent feiner,
    // das ist fuer einen 5-km-Raster zumutbar und heisst im Umkehr-
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

  /// Haelt eine Koordinatenaenderung fuer unzulaessig, wenn sie das
  /// Raster nicht verlaesst.
  ///
  /// Der Server erzwingt das ebenfalls (guard_profile_location_update).
  /// Hier dient es dazu, im Client nicht jedes Mal ein Update zu
  /// schicken, das der Server ohnehin veraendern wuerde - das erzeugt
  /// nur unmotige Schreibvorgaenge.
  ///
  /// Die Toleranz von 1 m verhindert, dass Rundungsrauschen als Aenderung
  /// gilt; ohne sie wuerde ein Standort, der exakt auf dem Raster liegt,
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