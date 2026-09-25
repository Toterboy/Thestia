import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:thestia/services/secure_location_storage.dart';

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

  /// Holt den aktuellen GPS-Standort (hohe Genauigkeit).
  Future<Position?> getCurrentLocation() async {
    if (!await hasLocationPermission()) {
      final granted = await requestLocationPermission();
      if (!granted) return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[LocationVerification] Fehler beim Standortabruf: $e');
      return null;
    }
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
  Future<Map<String, dynamic>?> getVerificationLocation() async {
    final data = await _storage.readAll();
    if (data == null) return null;

    return {
      'latitude': double.parse(data['latitude']!),
      'longitude': double.parse(data['longitude']!),
      'timestamp': data['timestamp']!.isNotEmpty
          ? DateTime.parse(data['timestamp']!)
          : null,
      'accuracy': data['accuracy']!.isNotEmpty
          ? double.parse(data['accuracy']!)
          : null,
    };
  }

  /// Berechnet die Distanz zwischen zwei Standorten in Metern.
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Prüft, ob ein neuer Standort verdächtig nah an einem bestehenden Verifizierungs-Standort ist.
  ///
  /// Schwellenwert: 100 Meter (konfigurierbar).
  /// In Produktion: Server-seitige Prüfung gegen alle verifizierten Standorte.
  Future<bool> isLocationSuspicious(Position newPosition, {double thresholdMeters = 100}) async {
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
final locationVerificationServiceProvider = Provider<LocationVerificationService>((ref) {
  return LocationVerificationService();
});
