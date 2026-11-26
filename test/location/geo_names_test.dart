// Die Bundesland-Auflösung aus der Position (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/utils/location/geo_names.dart 0 %.
//
// WARUM DAS WICHTIG IST: Die Funktion liefert bewusst NUR das
// Bundesland, nicht den Ort - der Aufenthaltsort wäre sonst bis auf
// ~11 km genau öffentlich. Ein Test hält diese Zusage fest.
//
// WAS HIER GEPRÜFT WIRD:
//   * geliefert wird das Bundesland, NICHT der Ort,
//   * ohne Treffer kommt null (die Einrichtung fragt dann, statt zu raten),
//   * ohne Bundesland kommt die grobe Landangabe,
//   * ein Fehler kommt als null (kein Absturz),
//   * der Aufruf geht an die Platform-Schnittstelle (der Test mockt sie).
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:thestia/utils/location/geo_names.dart';

/// Der Ersatz für die Geocoding-Plattform.
///
/// Die echte Schnittstelle braucht das Gerät - im Test antwortet der
/// Ersatz aus dem RAM.
class _FakeGeocoding extends GeocodingPlatform {
  /// Die Placemarks, die der "Geocoder" liefert.
  List<Placemark> antwort = const [];

  /// Wenn gesetzt, wirft [placemarkFromCoordinates] diesen Fehler.
  Object? fehler;

  /// Die Koordinaten, nach denen gefragt wurde.
  List<(double, double)> aufrufe = [];

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    aufrufe.add((latitude, longitude));
    final f = fehler;
    if (f != null) throw f;
    return antwort;
  }
}

void main() {
  late _FakeGeocoding geocoding;

  setUp(() {
    geocoding = _FakeGeocoding();
    GeocodingPlatform.instance = geocoding;
  });

  group('Die Bundesland-Aufloesung', () {
    test('geliefert wird das Bundesland, nicht der Ort', () async {
      geocoding.antwort = [
        const Placemark(
          administrativeArea: 'Niedersachsen',
          locality: 'Bremen',
          country: 'Deutschland',
        ),
      ];

      final bundesland = await describeStateFor(53.08, 8.81);

      expect(bundesland, 'Niedersachsen');
      expect(
        bundesland,
        isNot('Bremen'),
        reason:
            'Der Ort waere bis auf ~11 km genau oeffentlich - er darf nicht '
            'zurueckkommen.',
      );
    });

    test('ohne Treffer kommt null', () async {
      geocoding.antwort = const [];

      // Null heißt: die Einrichtung fragt den Nutzer. Ein erfundenes
      // Bundesland wäre schlimmer als keines.
      expect(await describeStateFor(53.08, 8.81), isNull);
    });

    test('ohne Bundesland kommt die grobe Landangabe', () async {
      geocoding.antwort = [
        const Placemark(locality: 'Bremen', country: 'Deutschland'),
      ];

      // Auch das ist besser als der Ortsname.
      expect(await describeStateFor(53.08, 8.81), 'Deutschland');
    });

    test('gibt es weder Bundesland noch Land, kommt null', () async {
      geocoding.antwort = [const Placemark(locality: 'Bremen')];

      expect(await describeStateFor(53.08, 8.81), isNull);
    });

    test('ein Fehler kommt als null', () async {
      geocoding.fehler = StateError('Geocoder nicht erreichbar');

      // Kein Absturz, kein geratener Wert.
      expect(await describeStateFor(53.08, 8.81), isNull);
    });

    test('der erste Treffer gewinnt', () async {
      geocoding.antwort = [
        const Placemark(administrativeArea: 'Bayern'),
        const Placemark(administrativeArea: 'Hessen'),
      ];

      expect(await describeStateFor(48.13, 11.57), 'Bayern');
    });

    test('die Koordinaten gehen unveraendert an den Geocoder', () async {
      geocoding.antwort = [const Placemark(administrativeArea: 'Bayern')];

      await describeStateFor(48.13, 11.57);

      expect(geocoding.aufrufe, [(48.13, 11.57)]);
    });
  });
}
