import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:thestia/services/profile/location_verification_service.dart';
import 'package:thestia/utils/location/location_privacy.dart';

/// Test für das Raster des Verifizierungs-Standorts.
///
/// WARUM (06.11.2026, Betreiber): "Also muss der Standort jetzt doch
/// genau statt nur ungefähr ermittelt werden?"
///
/// Die genaue Standort-Berechtigung ist auf Android 11 und älter
/// Pflicht (für den BLE-Scan), und dort gibt es keine Wahl zwischen
/// "ungefähr" und "genau" - die Wahl kam erst mit Android 12. Damit
/// kännte die App auf älteren Geräten einen EXAKTEN Standort
/// bekommen und lokal speichern - obwohl sie verspricht, den genauen
/// Standort nicht zu speichern.
///
/// Die Lösung: der Standort geht durch dasselbe 5-km-Raster wie das
/// Profil. Damit gilt das Versprechen auf ALLEN Systemversionen.
Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  group('Der Verifizierungs-Standort', () {
    test('liegt auf dem 5-km-Raster, nicht auf dem exakten Punkt', () {
      // Ein exakter Standort (52,520123 / 13,405678).
      final exakt = _position(52.520123, 13.405678);

      final gerastert = LocationVerificationService.aufRaster(exakt);

      expect(
        gerastert.latitude,
        isNot(52.520123),
        reason:
            'der exakte Standort darf nicht weitergegeben werden - das '
            'waere ein Hauskoordinaten-Ort',
      );
      expect(
        gerastert.latitude,
        LocationPrivacy.snapToGrid(exakt.latitude, exakt.longitude).lat,
      );
      expect(
        gerastert.longitude,
        LocationPrivacy.snapToGrid(exakt.latitude, exakt.longitude).lng,
      );
    });

    test('liegt hoechstens 5 km vom exakten Punkt entfernt', () {
      final exakt = _position(48.137154, 11.576124);

      final gerastert = LocationVerificationService.aufRaster(exakt);

      // 5-km-Raster: die Entfernung darf nie größer als das Raster sein.
      const gradProKm = 1 / LocationPrivacy.kmPerDegreeLat;
      const kmPerGradLng = LocationPrivacy.kmPerDegreeLat * 0.67;
      final dLat = (gerastert.latitude - exakt.latitude).abs() * gradProKm;
      final dLng = (gerastert.longitude - exakt.longitude).abs() * kmPerGradLng;
      final entfernungKm = dLat * dLat + dLng * dLng;

      expect(
        entfernungKm,
        lessThanOrEqualTo(LocationPrivacy.gridKm * LocationPrivacy.gridKm),
        reason:
            'der Rasterpunkt liegt weiter als 5 km vom echten Punkt - das '
            'waere keine Genauigkeit von "ungefaehr", sondern eine andere',
      );
    });

    test('zweimal rasteren aendert nichts (idempotent)', () {
      final exakt = _position(50.937531, 6.960279);

      final einmal = LocationVerificationService.aufRaster(exakt);
      final zweimal = LocationVerificationService.aufRaster(einmal);

      expect(zweimal.latitude, einmal.latitude);
      expect(zweimal.longitude, einmal.longitude);
    });
  });
}
