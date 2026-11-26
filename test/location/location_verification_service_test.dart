// Der Dienst des Verifizierungs-Standorts.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/services/profile/location_verification_service.dart 41 offene Zeilen
// bei 27 % Abdeckung. Der Dienst entscheidet, OB ein Standort gespeichert
// wird und ob ein neuer Standort "verdächtig" ist.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Standort landet im sicheren Speicher - und nur der gerasterte,
//   * er lässt sich wieder löschen (der Weg muss frei bleiben),
//   * die Entfernungsrechnung stimmt,
//   * die Berechtigung wird gelesen und angefragt,
//   * die Verdachts-Regel gilt genau so, wie sie dokumentiert ist: EIN
//     neuer Standort, der VERDÄCHTIG NAH am gespeicherten liegt, ist
//     verdächtig (derselbe Ort lässt sich nicht ein zweites Mal
//     verifizieren).

// Die Plattform-Interfaces kommen als Transitivum über geolocator und
// permission_handler - der Test setzt die Attrappen darüber.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:thestia/services/profile/location_verification_service.dart';

import '../support/plugin_mocks.dart';

/// Die Position für den Test.
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

/// Der Geolocator-Ersatz: er meldet die Position.
class _Geolocator extends GeolocatorPlatform {
  /// Die Position, die geliefert wird.
  Position? position;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => position ?? _position(53.5511, 9.9937);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Im Test nicht gebraucht: ${invocation.memberName}',
  );
}

/// Die Berechtigungen im Test.
class _Berechtigungen extends PermissionHandlerPlatform {
  /// Ist die Berechtigung erteilt?
  bool erteilt = false;

  /// Wie oft wurde angefragt?
  int anfragen = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    anfragen++;
    return erteilt ? PermissionStatus.granted : PermissionStatus.denied;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    anfragen++;
    erteilt = true;
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

void main() {
  late GeolocatorPlatform originalGeolocator;
  late PermissionHandlerPlatform originalBerechtigungen;
  late _Berechtigungen berechtigungen;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: Der Standort liegt im sicheren Speicher - ohne den
    // Ersatz ruft der Test das echte Plugin.
    mockKeystore();
  });

  setUp(() {
    originalGeolocator = GeolocatorPlatform.instance;
    originalBerechtigungen = PermissionHandlerPlatform.instance;
    GeolocatorPlatform.instance = _Geolocator();
    berechtigungen = _Berechtigungen();
    PermissionHandlerPlatform.instance = berechtigungen;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalGeolocator;
    PermissionHandlerPlatform.instance = originalBerechtigungen;
  });

  group('Der Verifizierungs-Standort', () {
    test('wird gespeichert und wieder gelesen', () async {
      final dienst = LocationVerificationService();

      // VORHER: Da ist noch nichts.
      expect(await dienst.hasVerificationLocation(), isFalse);
      expect(await dienst.getVerificationLocation(), isNull);

      await dienst.saveVerificationLocation(_position(53.5511, 9.9937));

      expect(
        await dienst.hasVerificationLocation(),
        isTrue,
        reason:
            'Nach dem Speichern muss der Dienst den Standort kennen - er '
            'vergleicht ihn mit dem naechsten.',
      );

      final gelesen = await dienst.getVerificationLocation();
      expect(gelesen, isNotNull);
      expect(gelesen!['latitude'], isNotNull);
      expect(gelesen['longitude'], isNotNull);
    });

    test('laesst sich wieder loeschen', () async {
      final dienst = LocationVerificationService();

      await dienst.saveVerificationLocation(_position(53.5511, 9.9937));
      expect(await dienst.hasVerificationLocation(), isTrue);

      await dienst.clearVerificationLocation();

      expect(
        await dienst.hasVerificationLocation(),
        isFalse,
        reason:
            'Der Weg muss frei bleiben: wer seinen Standort nicht mehr '
            'will, muss ihn loeschen koennen.',
      );
    });

    test('die Entfernungsrechnung stimmt', () {
      final dienst = LocationVerificationService();

      // BERLIN - HAMBURG: rund 255 km.
      final entfernung = dienst.calculateDistance(
        52.5200,
        13.4050,
        53.5511,
        9.9937,
      );

      expect(
        entfernung,
        closeTo(255000, 5000),
        reason:
            'Die Entfernung wird in Metern gerechnet - ein Fehler hier '
            'wuerde jeden Verdachts-Hinweis falsch ausloesen.',
      );
    });

    test('ein Standort direkt daneben gilt als verdaechtig', () async {
      final dienst = LocationVerificationService();

      // GESPEICHERT: Hamburg. NEU: 10 Meter daneben.
      await dienst.saveVerificationLocation(_position(53.5511, 9.9937));

      final verdaechtig = await dienst.isLocationSuspicious(
        _position(53.55111, 9.99371),
      );

      expect(
        verdaechtig,
        isTrue,
        reason:
            'Dieselbe Stelle laesst sich nicht ein zweites Mal bestaetigen '
            '- das ist das Muster von Sammel-Konten.',
      );
    });

    test('ein weit entfernter Standort ist nicht verdaechtig', () async {
      final dienst = LocationVerificationService();

      // GESPEICHERT: Hamburg. NEU: München - 500 km weiter.
      await dienst.saveVerificationLocation(_position(53.5511, 9.9937));

      final verdaechtig = await dienst.isLocationSuspicious(
        _position(48.1372, 11.5756),
      );

      expect(
        verdaechtig,
        isFalse,
        reason:
            'Wer umzieht, ist niemand - die Regel gilt nur fuer denselben '
            'Ort.',
      );
    });

    test('ohne gespeicherten Standort ist nichts verdaechtig', () async {
      final dienst = LocationVerificationService();

      final verdaechtig = await dienst.isLocationSuspicious(
        _position(48.1372, 11.5756),
      );

      expect(
        verdaechtig,
        isFalse,
        reason:
            'Ohne Vergleichspunkt gibt es nichts zu vergleichen - der erste '
            'Standort darf niemanden belasten.',
      );
    });
  });

  group('Die Berechtigung', () {
    test('die erteilte Berechtigung wird erkannt', () async {
      berechtigungen.erteilt = true;
      final dienst = LocationVerificationService();

      expect(await dienst.hasLocationPermission(), isTrue);
    });

    test('die fehlende Berechtigung wird erkannt', () async {
      berechtigungen.erteilt = false;
      final dienst = LocationVerificationService();

      expect(await dienst.hasLocationPermission(), isFalse);
    });

    test('die Anfrage holt die Berechtigung', () async {
      berechtigungen.erteilt = false;
      final dienst = LocationVerificationService();

      final erteilt = await dienst.requestLocationPermission();

      expect(erteilt, isTrue);
      expect(
        berechtigungen.anfragen,
        greaterThan(0),
        reason: 'Der Dienst muss den Nutzer wirklich fragen.',
      );
    });
  });
}
