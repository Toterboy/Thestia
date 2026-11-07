import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:thestia/services/secure_location_storage.dart';
import 'package:thestia/utils/location_privacy.dart';

/// Service für die einmalige Standort-Abfrage bei der Verifizierung.
///
/// Wird verwendet, um Massen-Fake-Accounts von derselben Position/Gerät zu erkennen.
/// Der Standort wird nur EINMAL bei der Verifizierung abgefragt und gespeichert.
///
/// Ab v1 wird der Standort in [SecureLocationStorage] (FlutterSecureStorage →
/// Android Keystore / iOS Keychain) abgelegt, NICHT mehr im Klartext in
/// SharedPreferences. Eine einmalige Migration über
/// [SecureLocationStorage.migrateFromSharedPreferences] ist im App-Start
/// eingebaut.
class LocationVerificationService {
  final SecureLocationStorage _storage = SecureLocationStorage.instance;

  /// Prüft, ob die Standortberechtigung erteilt ist.
  Future<bool> hasLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  /// Fordert die Standortberechtigung an.
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  /// Holt den aktuellen Standort - auf dem 5-km-Raster der App.
  ///
  /// `LocationAccuracy.high` war falsch fuer diesen Zweck und verlangte
  /// faktisch ACCESS_FINE_LOCATION: Geolocator kann dann keine
  /// Netzwerkmessung mehr machen und liefert nur mit GPS eine Position -
  /// auf einem Gerät ohne GPS-Signal bleibt `null`, und die
  /// Standortverifikation waere unmoeglich.
  ///
  /// DER STANDORT WIRD GERASTET (BEFUND 06.11.2026): Die App holt die
  /// Position auf dem 5-km-Raster ([LocationPrivacy.snapToGrid]) - auf
  /// JEDER Systemversion. Grund: Auf Android 11 und aelter ist die genaue
  /// Standort-Berechtigung Pflicht (fuer den BLE-Scan), und dort gibt es
  /// keine Wahl zwischen "ungefaehr" und "genau" - die Wahl kam erst mit
  /// Android 12. Ohne das Raster wuerde die App auf aelteren Geraeten
  /// einen genauen Standort bekommen und lokal speichern, obwohl sie
  /// verspricht, den genauen Standort NICHT zu speichern. Das Raster ist
  /// genau die Genauigkeit, die die App braucht (sie leitet daraus die
  /// Stadt ab) - und es ist dieselbe Regel, die fuer das Profil gilt.
  Future<Position?> getCurrentLocation() async {
    if (!await hasLocationPermission()) {
      final granted = await requestLocationPermission();
      if (!granted) return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return aufRaster(position);
    } catch (e) {
      debugPrint('[LocationVerification] Fehler beim Standortabruf: $e');
      return null;
    }
  }

  /// Die Position auf das 5-km-Raster der App zurueckgeben.
  ///
  /// OEFFENTLICH, damit der Test pruefen kann: der gespeicherte
  /// Verifizierungs-Standort ist ein Rasterpunkt und kein exakter
  /// Standort (BEFUND 06.11.2026).
  static Position aufRaster(Position position) {
    final gerastert = LocationPrivacy.snapToGrid(
      position.latitude,
      position.longitude,
    );
    return Position(
      latitude: gerastert.lat,
      longitude: gerastert.lng,
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      altitude: position.altitude,
      altitudeAccuracy: position.altitudeAccuracy,
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
    );
  }

  /// Speichert den Verifizierungs-Standort (einmalig) im sicheren Speicher.
  Future<void> saveVerificationLocation(Position position) async {
    await _storage.save(
      latitude: position.latitude.toString(),
      longitude: position.longitude.toString(),
      timestamp: position.timestamp.toIso8601String(),
      accuracy: position.accuracy.toString(),
    );
  }

  /// Prüft, ob bereits ein Verifizierungs-Standort gespeichert ist.
  Future<bool> hasVerificationLocation() => _storage.hasLocation();

  /// Holt den gespeicherten Verifizierungs-Standort.
  ///
  /// Die Werte kommen aus `FlutterSecureStorage` und können nach einem
  /// Gerätewechsel, einem App-Update oder einer Migration korrupt sein.
  /// Ein `parse` auf ungeprüften Rohtext würde dann eine FormatException
  /// werfen und den aufrufenden Screen crashen. Lieber "kein Standort"
  /// zurückgeben als den Nutzer mit einem Absturz zu verlieren.
  Future<Map<String, dynamic>?> getVerificationLocation() async {
    final data = await _storage.readAll();
    if (data == null) return null;

    try {
      final lat = double.parse(data['latitude'] ?? '');
      final lng = double.parse(data['longitude'] ?? '');
      final rawTs = data['timestamp'] ?? '';
      final rawAcc = data['accuracy'] ?? '';
      return {
        'latitude': lat,
        'longitude': lng,
        'timestamp': rawTs.isNotEmpty ? DateTime.tryParse(rawTs) : null,
        'accuracy': rawAcc.isNotEmpty ? double.tryParse(rawAcc) : null,
      };
    } catch (e) {
      debugPrint('[LocationVerification] Gespeicherter Standort unlesbar: $e');
      return null;
    }
  }

  /// Berechnet die Distanz zwischen zwei Standorten in Metern.
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Prüft, ob ein neuer Standort verdächtig nah an einem bestehenden Verifizierungs-Standort ist.
  ///
  /// Schwellenwert: 100 Meter (konfigurierbar).
  /// In Produktion: Server-seitige Prüfung gegen alle verifizierten Standorte.
  Future<bool> isLocationSuspicious(
    Position newPosition, {
    double thresholdMeters = 100,
  }) async {
    final saved = await getVerificationLocation();
    if (saved == null) return false;

    final distance = calculateDistance(
      saved['latitude'] as double,
      saved['longitude'] as double,
      newPosition.latitude,
      newPosition.longitude,
    );

    return distance < thresholdMeters;
  }

  /// Löscht den gespeicherten Verifizierungs-Standort (z. B. bei Account-Löschung).
  Future<void> clearVerificationLocation() => _storage.clear();
}

/// Provider für den LocationVerificationService.
final locationVerificationServiceProvider =
    Provider<LocationVerificationService>((ref) {
      return LocationVerificationService();
    });
