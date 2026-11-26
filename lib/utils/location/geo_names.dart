import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

/// Liefert das BUNDESLAND zu einer Position - bewusst NICHT den Ort.
///
/// v0.10.0: `describePlace` lieferte "Bremen, Bremen" (locality +
/// administrativeArea) und wurde nach `profiles.city` geschrieben. Damit
/// war der Aufenthaltsort bis auf ~11 km genau öffentlich, obwohl das
/// Bundesland als Anzeige völlig ausreicht.
///
/// Deshalb diese Funktion: sie nimmt `administrativeArea` und lässt den
/// Ort aus. Wo der Geocoder nichts liefert, gibt sie null zurück - dann
/// fragt die Einrichtung nach, statt zu raten. Ein erfundenes Bundesland
/// wäre schlimmer als keines.
Future<String?> describeStateFor(double latitude, double longitude) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isEmpty) return null;

    // Erster Treffer gewinnt; administrativeArea ist in DE/AT/CH das
    // Bundesland, in anderen Ländern die Region.
    final candidates = placemarks
        .map((p) => (p.administrativeArea ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (candidates.isNotEmpty) return candidates.first;

    // Rückfall auf eine grobe Landangabe. Auch das ist besser als der
    // Ortsname: "Deutschland" statt "Bremen".
    final country = placemarks.first.country?.trim();
    return (country != null && country.isNotEmpty) ? country : null;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[GEO_NAMES] Bundesland-Aufloesung fehlgeschlagen: $e');
    }
    return null;
  }
}

/// Audit N-1 / UX: Nach der automatischen Standorterkennung soll im
/// "Stadt"-Feld ein ORTSNAME stehen, nie ein Koordinaten-Paar.
///
/// VERALTET seit v0.10.0 - die Einrichtung speichert keine Orte mehr.
/// Aufrufer dieser Funktion gibt es im aktiven Code nicht mehr; sie
/// bleibt nur als Quelle für describeStateFor dokumentiert und ist
/// dort NICHT mehr aufrufbar.
Future<String> describePlace(double latitude, double longitude) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      final parts = <String>[
        p.locality ?? '',
        p.administrativeArea ?? '',
      ].where((s) => s.trim().isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join(', ');

      final fallback = (p.subAdministrativeArea ?? p.country ?? '').trim();
      if (fallback.isNotEmpty) return fallback;
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[GEO_NAMES] Reverse-Geocoding fehlgeschlagen: $e');
    }
  }
  return 'Region ca. ${latitude.toStringAsFixed(1)} / '
      '${longitude.toStringAsFixed(1)}';
}
