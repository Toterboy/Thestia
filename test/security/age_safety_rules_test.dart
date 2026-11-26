import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgeSafetyRules - ageGroup', () {
    test('15 -> minor (unterhalb des Mindestalters)', () {
      expect(AgeSafetyRules.ageGroup(15), equals(AgeGroup.minor));
    });

    test('16-17 -> minor', () {
      expect(AgeSafetyRules.ageGroup(16), equals(AgeGroup.minor));
      expect(AgeSafetyRules.ageGroup(17), equals(AgeGroup.minor));
    });

    test('18 -> adult18, 19 -> adult19, 20+ -> adult (gestufte Regeln)', () {
      expect(AgeSafetyRules.ageGroup(18), equals(AgeGroup.adult18));
      expect(AgeSafetyRules.ageGroup(19), equals(AgeGroup.adult19));
      expect(AgeSafetyRules.ageGroup(20), equals(AgeGroup.adult));
      expect(AgeSafetyRules.ageGroup(25), equals(AgeGroup.adult));
      expect(AgeSafetyRules.ageGroup(50), equals(AgeGroup.adult));
      expect(AgeSafetyRules.ageGroup(99), equals(AgeGroup.adult));
    });
  });

  group('AgeSafetyRules - canViewProfile', () {
    // Die Regel entspricht dem Server (Migration 154 + 155):
    // Die Discovery filtert BEIDSEITIG über
    // age_compatible_bidirectional, also age_compatible(a->b) UND
    // age_compatible(b->a). age_compatible (Migration 056):
    //
    //   Viewer < 18  -> Ziel in [16, 18)
    //   Viewer = 18  -> Ziel >= 16
    //   Viewer = 19  -> Ziel >= 17
    //   Viewer >= 20 -> Ziel >= 18
    //
    // Beidseitig heißt das: Minderjährige sehen nur Minderjährige,
    // Erwachsene sehen nur Erwachsene. 18<->16/17 ist gesperrt und
    // 19<->17 ebenfalls.
    //
    // BISHER stand hier die einseitige Regel ("18 sieht 16+"), und
    // die Tests haben sie festgeschrieben - obwohl der Server sie
    // nie erteilt. Ein 18-Jähriger sieht niemals einen
    // Minderjährigen.
    test('Erwachsene sehen keine Minderjaehrigen', () {
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 16),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 17),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 17),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 16),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 17),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 30, targetAge: 16),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 40, targetAge: 17),
        isFalse,
      );
    });

    test('Erwachsene sehen Erwachsene', () {
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 18),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 19),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 18),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 19),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 20, targetAge: 18),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 19),
        isTrue,
      );
    });

    test('Minor (16-17) cannot see adult (18+)', () {
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 18),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 19),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 20),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 25),
        isFalse,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 30),
        isFalse,
      );
    });

    test('Minderjaehrige sehen nur Minderjaehrige', () {
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 16),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 17),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 16),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 17),
        isTrue,
      );
    });

    test('Erwachsene sehen Erwachsene (gleiche Gruppe)', () {
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 18),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 19),
        isTrue,
      );
      expect(
        AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 25),
        isTrue,
      );
    });
  });

  group('AgeSafetyRules - maxFilterAge', () {
    // v0.10.0 (Migration 154): Die Altersprüfung ist beidseitig.
    // Minderjährige sehen ausschließlich 16 und 17 - ein Wert
    // darüber wäre ein toter Filter (der Server liefert ihn nie).
    test('Minor (16-17) max filter = 17', () {
      expect(AgeSafetyRules.maxFilterAge(16), equals(17));
      expect(AgeSafetyRules.maxFilterAge(17), equals(17));
    });

    test('Adult (18+) max filter = 99', () {
      expect(AgeSafetyRules.maxFilterAge(18), equals(99));
      expect(AgeSafetyRules.maxFilterAge(19), equals(99));
      expect(AgeSafetyRules.maxFilterAge(20), equals(99));
      expect(AgeSafetyRules.maxFilterAge(25), equals(99));
      expect(AgeSafetyRules.maxFilterAge(99), equals(99));
    });
  });

  group('AgeSafetyRules - minFilterAge', () {
    // v0.10.0 (Migration 154): Die Untergrenze ist höchstens 10
    // Jahre unter dem eigenen Alter und nie unter 18, sobald der
    // Nutzer volljährig ist.
    //
    // Das ist wortgleich die Server-Funktion max_age_range_min:
    //
    //   greatest(v_viewer_age - 10,
    //            CASE WHEN v_viewer_age < 18 THEN 16 ELSE 18 END)
    //
    // Die App hat bis 04.11.2026 für 18-Jährige 16 und für
    // 19-Jährige 17 angeboten - der Server liefert diese Altersstufen
    // nie. Der Filter war damit TOT: leere Liste, keine
    // Erklärung. Die Parität ist jetzt über [die Tabelle unten]
    // festgeschrieben.
    test('Minderjaehrige (16-17) min filter = 16', () {
      expect(AgeSafetyRules.minFilterAge(16), equals(16));
      expect(AgeSafetyRules.minFilterAge(17), equals(16));
    });

    test('18-Jaehriger: 18 (der Server liefert nur Erwachsene)', () {
      expect(AgeSafetyRules.minFilterAge(18), equals(18));
    });

    test('19-Jaehriger: 18 (der Server liefert nur Erwachsene)', () {
      expect(AgeSafetyRules.minFilterAge(19), equals(18));
    });

    test('Volljaehrige: eigenes Alter minus 10, mindestens 18', () {
      expect(AgeSafetyRules.minFilterAge(20), equals(18));
      expect(AgeSafetyRules.minFilterAge(25), equals(18));
      expect(AgeSafetyRules.minFilterAge(30), equals(20));
      expect(AgeSafetyRules.minFilterAge(40), equals(30));
      expect(AgeSafetyRules.minFilterAge(65), equals(55));
    });

    // Die Parität zur Server-Funktion max_age_range_min. Jede Zeile
    // ist 1:1 aus dem SQL abgeleitet - nicht aus der App abgeleitet.
    // Weicht eine Zahl ab, läuft die App auseinander.
    test('Paritaet zur Server-Funktion max_age_range_min', () {
      const serverWerte = <int, int>{
        // Alter: max_age_range_min(Alter)
        15: 16,
        16: 16,
        17: 16,
        18: 18,
        19: 18,
        20: 18,
        25: 18,
        28: 18,
        29: 19,
        30: 20,
        40: 30,
        65: 55,
        99: 89,
      };
      serverWerte.forEach((alter, erwartet) {
        expect(
          AgeSafetyRules.minFilterAge(alter),
          equals(erwartet),
          reason:
              'minFilterAge($alter) muss max_age_range_min($alter) = '
              '$erwartet entsprechen',
        );
      });
    });
  });

  group('AgeSafetyRules - isBlindModeForced', () {
    test('Minor (16-17) blind mode forced', () {
      expect(AgeSafetyRules.isBlindModeForced(16), isTrue);
      expect(AgeSafetyRules.isBlindModeForced(17), isTrue);
    });

    test('Adult (18+) blind mode NOT forced', () {
      expect(AgeSafetyRules.isBlindModeForced(18), isFalse);
      expect(AgeSafetyRules.isBlindModeForced(19), isFalse);
      expect(AgeSafetyRules.isBlindModeForced(20), isFalse);
      expect(AgeSafetyRules.isBlindModeForced(25), isFalse);
      expect(AgeSafetyRules.isBlindModeForced(99), isFalse);
    });
  });

  group('AgeSafetyRules - isRoughDistanceForced', () {
    // BETREIBER-ENTSCHEIDUNG (02.11.2026): "Die grobe Entfernung
    // dürfen 16 und 17 jährige auch nicht aktivieren können."
    //
    // Die mächtige Sperre sitzt in der Datenbank
    // (profile_distance_km, Migration 163). Diese Regel ist die
    // freundliche Seite: der Schalter wird gar nicht erst angeboten.
    test('Minor (16-17): die grobe Entfernung ist gesperrt', () {
      expect(AgeSafetyRules.isRoughDistanceForced(16), isTrue);
      expect(AgeSafetyRules.isRoughDistanceForced(17), isTrue);
    });

    test('Adult (18+): die grobe Entfernung ist frei waehlbar', () {
      expect(AgeSafetyRules.isRoughDistanceForced(18), isFalse);
      expect(AgeSafetyRules.isRoughDistanceForced(19), isFalse);
      expect(AgeSafetyRules.isRoughDistanceForced(20), isFalse);
      expect(AgeSafetyRules.isRoughDistanceForced(25), isFalse);
      expect(AgeSafetyRules.isRoughDistanceForced(99), isFalse);
    });

    test('Unbekanntes Alter (0) gilt als gesperrt', () {
      // Fehlt das Geburtsdatum im Profil, ist die strengste Variante
      // richtig: gesperrt.
      expect(AgeSafetyRules.isRoughDistanceForced(0), isTrue);
    });
  });

  group('AgeSafetyRules - Suchradius (v0.10.0)', () {
    // BETREIBER-ENTSCHEIDUNG (03.11.2026): "für 16 und 17 jährige
    // entweder gleiches Bundesland oder max. 25 Km. Und ab 18 alles
    // frei auswählbar."
    //
    // Die mächtige Sperre sitzt in der Datenbank
    // (profile_discovery_visible, Migration 164). Diese Regel ist die
    // freundliche Seite: der Radius wird gar nicht erst größer
    // angeboten.
    test('Minor (16-17): der Suchradius ist begrenzt', () {
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(16), isTrue);
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(17), isTrue);
    });

    test('Adult (18+): der Suchradius ist frei waehlbar', () {
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(18), isFalse);
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(19), isFalse);
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(25), isFalse);
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(99), isFalse);
    });

    test('Unbekanntes Alter (0) gilt als begrenzt', () {
      // Fehlt das Geburtsdatum im Profil, ist die strengste Variante
      // richtig: begrenzt.
      expect(AgeSafetyRules.isDiscoveryRadiusCapped(0), isTrue);
    });

    test('Minor: hoechstens 25 km', () {
      expect(AgeSafetyRules.maxDiscoveryRadiusKm(16), 25);
      expect(AgeSafetyRules.maxDiscoveryRadiusKm(17), 25);
      expect(AgeSafetyRules.maxDiscoveryRadiusKm(0), 25);
    });

    test('Adult: der normale Slider-Endwert (100 km)', () {
      expect(AgeSafetyRules.maxDiscoveryRadiusKm(18), 100);
      expect(AgeSafetyRules.maxDiscoveryRadiusKm(30), 100);
    });

    test('Minor: "Ganz Deutschland" ist gesperrt', () {
      expect(AgeSafetyRules.isWholeGermanyAllowed(16), isFalse);
      expect(AgeSafetyRules.isWholeGermanyAllowed(17), isFalse);
      expect(AgeSafetyRules.isWholeGermanyAllowed(0), isFalse);
    });

    test('Adult: "Ganz Deutschland" ist erlaubt', () {
      expect(AgeSafetyRules.isWholeGermanyAllowed(18), isTrue);
      expect(AgeSafetyRules.isWholeGermanyAllowed(40), isTrue);
    });
  });

  group('AgeSafetyRules - canChangePhotoVisibilitySettings', () {
    test('Minor (16-17) cannot change photo visibility settings', () {
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(16), isFalse);
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(17), isFalse);
    });

    test('Adult (18+) can change photo visibility settings', () {
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(18), isTrue);
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(19), isTrue);
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(20), isTrue);
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(25), isTrue);
      expect(AgeSafetyRules.canChangePhotoVisibilitySettings(99), isTrue);
    });
  });

  group('AgeSafetyRules - arePhotosVisible', () {
    test('Minor target (16-17): photos only visible to other minors', () {
      // Minor target, minor viewer -> visible
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 16,
          viewerAge: 16,
          blindModeEnabled: false,
          revealPhotosAfterMatch: false,
          isMatched: false,
        ),
        isTrue,
      );

      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 17,
          viewerAge: 17,
          blindModeEnabled: true,
          revealPhotosAfterMatch: true,
          isMatched: false,
        ),
        isTrue,
      );

      // Minor target, adult viewer -> NOT visible
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 16,
          viewerAge: 18,
          blindModeEnabled: false,
          revealPhotosAfterMatch: false,
          isMatched: false,
        ),
        isFalse,
      );

      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 16,
          viewerAge: 20,
          blindModeEnabled: false,
          revealPhotosAfterMatch: false,
          isMatched: false,
        ),
        isFalse,
      );
    });

    test('Adult target (18+): follows blind mode settings', () {
      // Adult target, blind mode OFF -> visible immediately
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 18,
          viewerAge: 18,
          blindModeEnabled: false,
          revealPhotosAfterMatch: false,
          isMatched: false,
        ),
        isTrue,
      );

      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 20,
          viewerAge: 20,
          blindModeEnabled: false,
          revealPhotosAfterMatch: false,
          isMatched: false,
        ),
        isTrue,
      );

      // Adult target, blind mode ON, not matched -> NOT visible
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 18,
          viewerAge: 18,
          blindModeEnabled: true,
          revealPhotosAfterMatch: true,
          isMatched: false,
        ),
        isFalse,
      );

      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 25,
          viewerAge: 25,
          blindModeEnabled: true,
          revealPhotosAfterMatch: true,
          isMatched: false,
        ),
        isFalse,
      );

      // Adult target, blind mode ON, matched -> visible
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 18,
          viewerAge: 18,
          blindModeEnabled: true,
          revealPhotosAfterMatch: true,
          isMatched: true,
        ),
        isTrue,
      );

      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 25,
          viewerAge: 25,
          blindModeEnabled: true,
          revealPhotosAfterMatch: true,
          isMatched: true,
        ),
        isTrue,
      );

      // Adult target, blind mode ON, matched, revealPhotosAfterMatch=false -> visible (match overrides)
      expect(
        AgeSafetyRules.arePhotosVisible(
          targetAge: 30,
          viewerAge: 30,
          blindModeEnabled: true,
          revealPhotosAfterMatch: false,
          isMatched: true,
        ),
        isTrue,
      );
    });
  });

  group('AgeSafetyRules - clampFilterAge', () {
    // v0.10.0 (Migration 154): Minderjährige sehen nur 16 und 17.
    test('Minor filter clamped to 16-17', () {
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 16,
          filterMin: 16,
          filterMax: 99,
        ),
        equals((16, 17)),
      );
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 17,
          filterMin: 10,
          filterMax: 30,
        ),
        equals((16, 17)),
      );
      // Obergrenze für Minderjährige ist jetzt 17 - beides wird
      // auf 17 geklemmt.
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 16,
          filterMin: 18,
          filterMax: 19,
        ),
        equals((17, 17)),
      );
    });

    // v0.10.0 (Migration 154): nach unten max. 10 Jahre unter dem
    // eigenen Alter, mindestens 18.
    test('Adult filter clamped to eigenes Alter minus 10', () {
      // Ein 18-Jähriger bekommt auf 18 geklemmt: 16 wäre ein toter
      // Filter (der Server liefert für ihn nur Erwachsene).
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 18,
          filterMin: 16,
          filterMax: 99,
        ),
        equals((18, 99)),
      );
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 19,
          filterMin: 16,
          filterMax: 99,
        ),
        equals((18, 99)),
      );
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 20,
          filterMin: 16,
          filterMax: 99,
        ),
        equals((18, 99)),
      );
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 25,
          filterMin: 16,
          filterMax: 30,
        ),
        equals((18, 30)),
      );
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 40,
          filterMin: 16,
          filterMax: 99,
        ),
        equals((30, 99)),
      );
      // Untergrenze für 25-Jährige ist max(18, 25-10) = 18.
      expect(
        AgeSafetyRules.clampFilterAge(
          viewerAge: 25,
          filterMin: 10,
          filterMax: 5,
        ),
        equals((18, 18)),
      );
    });
  });

  group('AgeSafetyRules - isValidFilterAge', () {
    test('Valid filter ranges', () {
      // v0.10.0 (Migration 154): Minderjährige dürfen höchstens
      // bis 17; Volljährige höchstens 10 Jahre unter ihr eigenes
      // Alter.
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 16,
          filterMin: 16,
          filterMax: 17,
        ),
        isTrue,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 18,
          filterMin: 18,
          filterMax: 30,
        ),
        isTrue,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 20,
          filterMin: 18,
          filterMax: 35,
        ),
        isTrue,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 20,
          filterMin: 18,
          filterMax: 25,
        ),
        isTrue,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 40,
          filterMin: 30,
          filterMax: 60,
        ),
        isTrue,
      );
    });

    test('Invalid filter ranges', () {
      // Minderjährige über 17 hinaus, unter 16 hinunter, bei
      // Volljährigen mehr als 10 Jahre unter das eigene Alter.
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 16,
          filterMin: 16,
          filterMax: 20,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 16,
          filterMin: 15,
          filterMax: 17,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 20,
          filterMin: 15,
          filterMax: 35,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 16,
          filterMin: 20,
          filterMax: 16,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 20,
          filterMin: 16,
          filterMax: 35,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 40,
          filterMin: 25,
          filterMax: 60,
        ),
        isFalse,
      );
      // Ein 18-Jähriger mit Untergrenze 16: der Server liefert ihm
      // niemals einen Minderjährigen - der Filter wäre tot.
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 18,
          filterMin: 16,
          filterMax: 30,
        ),
        isFalse,
      );
      expect(
        AgeSafetyRules.isValidFilterAge(
          viewerAge: 19,
          filterMin: 17,
          filterMax: 30,
        ),
        isFalse,
      );
    });
  });
}
