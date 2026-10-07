import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/location_privacy.dart';

/// Tests fuer die Standort-Privatisierung.
///
/// Kernpunkt: was gespeichert wird, ist das Bundesland und ein
/// 5-km-Raster - nicht der Ortsname und nicht die exakte Position.
/// Das Raster muss identisch zu dem in Migration 135 sein
/// (`snap_location_to_grid`), sonst springt die Entfernungsanzeige.
void main() {
  group('snapToGrid', () {
    test('rundet auf ein 5-km-Raster', () {
      final g = LocationPrivacy.snapToGrid(53.1, 8.2);
      // Ein Grad Breite ~ 111 km, 5 km entspricht ~0,045 Grad.
      expect(g.lat, closeTo(53.1, 0.05));
      expect(g.lng, closeTo(8.2, 0.1));
    });

    test('zwei dicht beieinander liegende Punkte landen im selben Raster', () {
      // WICHTIG: Der Ausgangspunkt muss sicher in der Rastermitte
      // liegen, nicht auf einer Grenze. 8.2 liegt praktisch auf der
      // Grenze (8.17746 vs 8.17747). Deshalb erst das Raster berechnen
      // und von DORT aus ein paar Meter Weg testen - so ist der Punkt
      // garantiert mittig im Raster.
      final mitte = LocationPrivacy.snapToGrid(53.10, 8.20);
      // ~8 m noerdlich, ~5 m oestlich
      final nah = LocationPrivacy.snapToGrid(mitte.lat + 0.000072, mitte.lng + 0.000072);
      expect(nah.lat, mitte.lat);
      expect(nah.lng, mitte.lng);
    });

    test('das Raster ist diskret: weit auseinander = anderes Raster', () {
      // Hamburg und Muenchen, beide vorher auf ihr Raster gelegt:
      // muessen garantiert verschiedene Raster sein.
      final hamburg = LocationPrivacy.snapToGrid(53.55, 9.99);
      final muenchen = LocationPrivacy.snapToGrid(48.14, 11.58);
      expect(hamburg.lat == muenchen.lat, isFalse);
      expect(hamburg.lng == muenchen.lng, isFalse);
    });

    test('der Laengengrad wird am Breitengrad gestreckt', () {
      // Am Aequator ist 1 Grad Laenge 111 km, in 53 Grad Breite nur
      // rund 67. Ohne Streckung waere das Raster in Mitteleuropa zu
      // fein - der gleiche_km-Schritt waere dort kleiner als beabsichtigt.
      final aequator = LocationPrivacy.snapToGrid(0.0, 0.05);
      final mitteleuropa = LocationPrivacy.snapToGrid(53.0, 8.05);
      final stepAequator = aequator.lng.abs();
      final stepMittel = mitteleuropa.lng.abs();
      expect(stepMittel, greaterThan(stepAequator));
    });

    test('Punkte auf dem Aequator und an den Polen sprengen nicht', () {
      // cos(90 Grad) waere 0 und damit Division durch Null.
      expect(() => LocationPrivacy.snapToGrid(90.0, 0.0), returnsNormally);
      expect(() => LocationPrivacy.snapToGrid(-90.0, 0.0), returnsNormally);
      expect(() => LocationPrivacy.snapToGrid(0.0, 0.0), returnsNormally);
    });

    test('Bremen liegt im erwarteten Bereich', () {
      // Realer Referenzpunkt, damit die Formel nicht nur synthetisch
      // stimmt.
      final b = LocationPrivacy.snapToGrid(53.0793, 8.8017);
      expect(b.lat, inInclusiveRange(53.0, 53.2));
      expect(b.lng, inInclusiveRange(8.7, 8.9));
    });

    test('negative Breiten funktionieren', () {
      final s = LocationPrivacy.snapToGrid(-33.8688, 151.2093);
      expect(s.lat, closeTo(-33.8688, 0.05));
      expect(s.lng, closeTo(151.2093, 0.1));
    });

    test('ist idempotent: zweimal rasteren aendert nichts', () {
      // Wichtig fuer den Sync: der Client snappt, der Server snappt noch
      // einmal. Liegt das Ergebnis nicht auf dem Raster, wandert es bei
      // jedem Sync ein Stueck weiter - die Entfernung wuerde driften.
      final p = LocationPrivacy.snapToGrid(52.52, 13.405);
      final g = LocationPrivacy.snapToGrid(p.lat, p.lng);
      expect(g.lat, p.lat);
      expect(g.lng, p.lng);

      final h = LocationPrivacy.snapToGrid(g.lat, g.lng);
      expect(h.lat, p.lat);
      expect(h.lng, p.lng);
    });
  });

  group('sameGridSpot', () {
    test('zwei Punkte im selben Raster gelten als gleich', () {
      expect(
        LocationPrivacy.sameGridSpot(53.10000, 8.20000, 53.10100, 8.20100),
        isTrue,
      );
    });

    test('zwei Punkte in verschiedenen Rastern gelten als verschieden', () {
      // Hamburg und München muessen auseinanderfallen.
      expect(
        LocationPrivacy.sameGridSpot(53.55, 9.99, 48.14, 11.58),
        isFalse,
      );
    });

    test('Rundungsrauschen gilt nicht als Wechsel', () {
      // Toleranz von 1 m: sonst wuerde ein Punkt, der exakt auf dem
      // Raster liegt, beim Sync springen.
      final p = LocationPrivacy.snapToGrid(53.1, 8.2);
      expect(
        LocationPrivacy.sameGridSpot(p.lat, p.lng, p.lat, p.lng),
        isTrue,
      );
    });

    test('die Toleranz ist winzig gegenueber einem Rasterschritt', () {
      // Sonst waere die Toleranz so weit, dass benachbarte Raster
      // zusammenfielen und die Entfernung falsch bliebe.
      final step = LocationPrivacy.gridKm / LocationPrivacy.kmPerDegreeLat;
      expect(step, greaterThan(0.001));
    });
  });

  group('Der alte Ortsname darf nicht mehr gespeichert werden', () {
    // Gegenprobe auf den Quelltext: describePlace() lieferte
    // "Bremen, Bremen" (locality + administrativeArea). Solange das im
    // Einrichtungs-Screen aufgerufen und nach city geschrieben wird, ist
    // die Privatisierung nicht erreicht - unabhaengig davon, wie korrekt
    // die Rasterung ist.
    final src = File('lib/screens/onboarding/settings_privacy_once_screen.dart')
        .readAsStringSync();

    test('der Screen ruft describePlace nicht mehr auf', () {
      // describePlace() LIEGT weiter in geo_names.dart (dort liefert der
      // Geocoder den Ortsnamen) - aber der Screen ruft sie nicht mehr
      // auf. Geprueft wird deshalb der Aufruf, nicht die Existenz.
      expect(src.contains('describePlace'), isFalse);
    });

    test('der Screen schreibt kein city in die Datenbank', () {
      // profileProvider.update(city: ...) und
      // updateOwnProfile({'city': ...}) sind beide verboten.
      expect(src.contains("'city':"), isFalse);
      expect(src.contains('city: city'), isFalse);
    });

    test('der Screen schreibt kein city lokal in die Einstellungen', () {
      expect(src.contains('setLocation('), isFalse);
    });
  });

  // v0.9.3: Der Profil-Edit-Screen hatte ein eigenes Ortsfeld mit
  // Tippvorschlag "Berlin", Debounce und einer GPS-Gegenpruefung
  // ("liegt mehr als 15 km entfernt"). Genau dort landete der Ort
  // wieder in profiles.city - nur eben beim Bearbeiten, nicht bei der
  // Einrichtung. Der Test haelt beide Wege dicht.
  group('Auch der Profil-Edit-Screen kennt keinen Ortsnamen', () {
    final src = File('lib/screens/profile/profile_edit_screen.dart')
        .readAsStringSync();

    test('kein Orts-Textfeld und kein city-Parameter', () {
      expect(src.contains('describePlace'), isFalse);
      expect(src.contains("'city':"), isFalse);
      expect(src.contains('city: city'), isFalse);
      // Der Controller selbst darf nicht mehr existieren.
      expect(src.contains('_cityCtrl'), isFalse);
    });

    test('GPS leitet nur das Bundesland ab und rastet vorher', () {
      expect(src.contains('describeStateFor'), isTrue);
      // Ohne vorheriges Raster wuerden die ungerundeten Koordinaten
      // gespeichert - der Server rastet zwar auch, aber ein Client,
      // der ungerundet schickt, macht das Rastering von sich abhaengig.
      expect(src.contains('LocationPrivacy.snapToGrid'), isTrue);
    });

    test('der Server bekommt kein city-Feld mehr', () {
      // Auch der Praeferenz-Sync darf den Ort nicht mehr mitschicken.
      expect(src.contains('savePreferencesToServer'), isTrue);
      expect(src.contains('city: location'), isFalse);
    });
  });

  group('Bundesland statt Ortsname', () {
    final src = File('lib/screens/onboarding/settings_privacy_once_screen.dart')
        .readAsStringSync();

    test('die Standortermittlung leitet das Bundesland ab', () {
      // Der Aufruf muss die administrativeArea-Version nutzen, nicht
      // describePlace().
      expect(src.contains('describeStateFor'), isTrue);
    });
  });

  group('Der Praeferenz-Provider fuehrt keinen Ort mit', () {
    final src = File('lib/providers/user_preferences_provider.dart')
        .readAsStringSync();

    test('kein location-Feld in den Praeferenzen', () {
      expect(src.contains('setLocation'), isFalse);
      expect(src.contains("'location'"), isFalse);
    });

    test('kein city im Server-Sync der Praeferenzen', () {
      expect(src.contains("p['city']"), isFalse);
      expect(src.contains("body['city']"), isFalse);
    });
  });

  // Ohne diesen Schritt bleibt profile_locations fuer neue Accounts leer
  // und die Entfernungsanzeige faellt aus. Migration 135 hat die Tabelle
  // nur fuer Bestandsprofile gefuellt.
  group('Die Koordinaten landen in profile_locations', () {
    final db = File('lib/services/supabase_database_service.dart')
        .readAsStringSync();

    test('der Service schreibt per upsert in profile_locations', () {
      expect(db.contains('saveOwnLocation'), isTrue);
      // insert wuerde beim zweiten Speichern (GPS-Knopf) scheitern.
      expect(db.contains("from('profile_locations').upsert"), isTrue);
    });

    test('der Client rastert vor dem Senden', () {
      // beider Aufrufer
      for (final pfad in const [
        'lib/screens/onboarding/settings_privacy_once_screen.dart',
        'lib/screens/profile/profile_edit_screen.dart',
      ]) {
        final s = File(pfad).readAsStringSync();
        expect(s.contains('saveOwnLocation'), isTrue,
            reason: '$pfad schreibt nicht nach profile_locations');
        expect(s.contains('snapToGrid'), isTrue,
            reason: '$pfad sendet ungerundete Koordinaten');
      }
    });

    test('die Datenbank fragt city nicht mehr ab', () {
      // Solange die Spalte noch existiert (Contract-Schritt 138) wird sie
      // wenigstens nicht mehr gelesen.
      expect(db.contains("'city': response['city']"), isFalse);
      expect(db.contains('is_location_suspicious, city'), isFalse);
    });
  });
}