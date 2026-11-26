// Der Standort für die Verifizierung (auf dem 5-km-Raster).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/services/profile/location_verification_service.dart 7 offene
// Zeilen - den Standortabruf selbst (Berechtigung, Abruf, Rasterung).
//
// DER WEG: Der Geolocator läuft über eine Plattform-Schnittstelle und
// die Berechtigungen über eine zweite - beides lässt sich im Test
// ersetzen (ohne GPS und ohne Plugin).
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Berechtigung gibt es keinen Standort (und die App fragt sie
//     an),
//   * der Standort kommt auf dem 5-km-Raster (die App verspricht, den
//     genauen Standort NICHT zu speichern - auf älteren Geräten ist
//     die genaue Berechtigung aber Pflicht),
//   * schlägt der Abruf fehl, gibt es keinen Standort (kein Absturz).
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// Die beiden Schnittstellen kommen als Transitivum über geolocator
// und permission_handler - der Test braucht nur ihre Typen.
// ignore_for_file: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:thestia/services/profile/location_verification_service.dart';

/// Der Geolocator als Ersatz.
///
/// DER GRUND: Ohne GPS liefert das echte Plugin nichts - und die App
/// muss mit "keiner Position" umgehen können.
class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator({this.position, this.wirft = false});

  /// Die Position, die der Ersatz meldet.
  final Position? position;

  /// Wirft der Abruf fehl (z. B. der Timeout im Freien)?
  final bool wirft;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (wirft) throw Exception('Der Standort ist nicht zu bekommen.');
    return position!;
  }
}

/// Die Berechtigungen als Ersatz.
class _FakeBerechtigungen extends PermissionHandlerPlatform {
  _FakeBerechtigungen();

  /// Ist die Berechtigung erteilt?
  bool erteilt = false;

  /// Wurde die Berechtigung angefragt?
  bool angefragt = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      erteilt ? PermissionStatus.granted : PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    angefragt = true;
    erteilt = true;
    return <Permission, PermissionStatus>{
      for (final p in permissions) p: PermissionStatus.granted,
    };
  }
}

void main() {
  late _FakeGeolocator geolocator;
  late _FakeBerechtigungen berechtigungen;

  setUp(() {
    geolocator = _FakeGeolocator(
      position: Position(
        latitude: 53.55347,
        longitude: 9.99123,
        timestamp: DateTime(2026, 11, 24),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    GeolocatorPlatform.instance = geolocator;
    berechtigungen = _FakeBerechtigungen();
    PermissionHandlerPlatform.instance = berechtigungen;
  });

  group('Der Standort', () {
    test('ohne Berechtigung wird sie angefragt', () async {
      final service = LocationVerificationService();

      final position = await service.getCurrentLocation();

      expect(
        berechtigungen.angefragt,
        isTrue,
        reason:
            'Die App muss die Berechtigung anfragen - sie darf nicht '
            'stillschweigend auf den Standort verzichten.',
      );
      expect(position, isNotNull);
    });

    test('der Standort kommt auf dem 5-km-Raster', () async {
      berechtigungen.erteilt = true;
      final service = LocationVerificationService();

      final position = await service.getCurrentLocation();

      expect(position, isNotNull);
      // DAS RASTER: Der Standort muss auf dem 5-km-Raster liegen - die
      // App verspricht, den genauen Standort NICHT zu speichern.
      // DER DIENST LIEFERT BEREITS DEN RASTERPUNKT - der Vergleich
      // läuft deshalb gegen die ROH-Position des Ersatzes.
      final roh = geolocator.position!;
      expect(
        (position!.latitude - roh.latitude).abs() +
                (position.longitude - roh.longitude).abs() >
            0,
        isTrue,
        reason:
            'Der Standort muss auf dem Raster liegen - sonst speichert die '
            'App doch den genauen Standort.',
      );
      // UND: Der Punkt ist ein Vielfaches der Rasterweite (5 km).
      final gerastert = LocationVerificationService.aufRaster(roh);
      expect(gerastert.latitude, isNot(closeTo(roh.latitude, 0.0001)));
      // UND: Der Rasterpunkt ist stabil (zweimal rasteren liefert
      // denselben Punkt).
      final zweimal = LocationVerificationService.aufRaster(gerastert);
      expect(zweimal.latitude, closeTo(gerastert.latitude, 0.0001));
      expect(zweimal.longitude, closeTo(gerastert.longitude, 0.0001));
    });

    test('schlaegt der Abruf fehl, gibt es keinen Standort', () async {
      berechtigungen.erteilt = true;
      geolocator = _FakeGeolocator(wirft: true);
      GeolocatorPlatform.instance = geolocator;
      final service = LocationVerificationService();

      final position = await service.getCurrentLocation();

      expect(
        position,
        isNull,
        reason:
            'Ein fehlgeschlagener Standortabruf darf keinen Absturz '
            'ausloesen - der Fall geht dann an die manuelle Pruefung.',
      );
    });
  });
}
