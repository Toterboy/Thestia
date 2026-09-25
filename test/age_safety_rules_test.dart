import 'package:thestia/utils/age_safety_rules.dart';
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
    test('Gestufte Regeln: 18 sieht 16+, 19 sieht 17+, 20+ sieht 18+', () {
      // 18 (adult18): darf 16+ sehen.
      expect(AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 16), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 17), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 18), isTrue);
      // 19 (adult19): darf 17+ sehen, aber NICHT 16.
      expect(AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 17), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 18), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 16), isFalse);
      // 20+ (adult): darf 18+ sehen, aber NICHT 16-17.
      expect(AgeSafetyRules.canViewProfile(viewerAge: 20, targetAge: 18), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 19), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 17), isFalse);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 30, targetAge: 16), isFalse);
    });

    test('Minor (16-17) cannot see adult (18+)', () {
      expect(AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 18), isFalse);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 19), isFalse);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 20), isFalse);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 25), isFalse);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 30), isFalse);
    });

    test('Same age group is always allowed', () {
      expect(AgeSafetyRules.canViewProfile(viewerAge: 16, targetAge: 16), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 17, targetAge: 17), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 18, targetAge: 18), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 19, targetAge: 19), isTrue);
      expect(AgeSafetyRules.canViewProfile(viewerAge: 25, targetAge: 25), isTrue);
    });
  });

  group('AgeSafetyRules - maxFilterAge', () {
    test('Minor (16-17) max filter = 19', () {
      expect(AgeSafetyRules.maxFilterAge(16), equals(19));
      expect(AgeSafetyRules.maxFilterAge(17), equals(19));
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
    test('All ages (16+) min filter = 16', () {
      expect(AgeSafetyRules.minFilterAge(16), equals(16));
      expect(AgeSafetyRules.minFilterAge(17), equals(16));
      expect(AgeSafetyRules.minFilterAge(18), equals(16));
      expect(AgeSafetyRules.minFilterAge(19), equals(16));
      expect(AgeSafetyRules.minFilterAge(20), equals(16));
      expect(AgeSafetyRules.minFilterAge(25), equals(16));
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
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 16,
        viewerAge: 16,
        blindModeEnabled: false,
        revealPhotosAfterMatch: false,
        isMatched: false,
      ), isTrue);

      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 17,
        viewerAge: 17,
        blindModeEnabled: true,
        revealPhotosAfterMatch: true,
        isMatched: false,
      ), isTrue);

      // Minor target, adult viewer -> NOT visible
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 16,
        viewerAge: 18,
        blindModeEnabled: false,
        revealPhotosAfterMatch: false,
        isMatched: false,
      ), isFalse);

      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 16,
        viewerAge: 20,
        blindModeEnabled: false,
        revealPhotosAfterMatch: false,
        isMatched: false,
      ), isFalse);
    });

    test('Adult target (18+): follows blind mode settings', () {
      // Adult target, blind mode OFF -> visible immediately
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 18,
        viewerAge: 18,
        blindModeEnabled: false,
        revealPhotosAfterMatch: false,
        isMatched: false,
      ), isTrue);

      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 20,
        viewerAge: 20,
        blindModeEnabled: false,
        revealPhotosAfterMatch: false,
        isMatched: false,
      ), isTrue);

      // Adult target, blind mode ON, not matched -> NOT visible
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 18,
        viewerAge: 18,
        blindModeEnabled: true,
        revealPhotosAfterMatch: true,
        isMatched: false,
      ), isFalse);

      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 25,
        viewerAge: 25,
        blindModeEnabled: true,
        revealPhotosAfterMatch: true,
        isMatched: false,
      ), isFalse);

      // Adult target, blind mode ON, matched -> visible
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 18,
        viewerAge: 18,
        blindModeEnabled: true,
        revealPhotosAfterMatch: true,
        isMatched: true,
      ), isTrue);

      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 25,
        viewerAge: 25,
        blindModeEnabled: true,
        revealPhotosAfterMatch: true,
        isMatched: true,
      ), isTrue);

      // Adult target, blind mode ON, matched, revealPhotosAfterMatch=false -> visible (match overrides)
      expect(AgeSafetyRules.arePhotosVisible(
        targetAge: 30,
        viewerAge: 30,
        blindModeEnabled: true,
        revealPhotosAfterMatch: false,
        isMatched: true,
      ), isTrue);
    });
  });

  group('AgeSafetyRules - clampFilterAge', () {
    test('Minor filter clamped to 16-19', () {
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 16, filterMin: 16, filterMax: 99),
          equals((16, 19)));
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 17, filterMin: 10, filterMax: 30),
          equals((16, 19)));
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 16, filterMin: 18, filterMax: 19),
          equals((18, 19)));
    });

    test('Adult filter clamped to 16-99', () {
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 18, filterMin: 16, filterMax: 99),
          equals((16, 99)));
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 20, filterMin: 16, filterMax: 99),
          equals((16, 99)));
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 25, filterMin: 16, filterMax: 30),
          equals((16, 30)));
      expect(AgeSafetyRules.clampFilterAge(viewerAge: 25, filterMin: 10, filterMax: 5),
          equals((16, 16)));
    });
  });

  group('AgeSafetyRules - isValidFilterAge', () {
    test('Valid filter ranges', () {
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 16, filterMin: 16, filterMax: 19), isTrue);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 18, filterMin: 16, filterMax: 30), isTrue);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 20, filterMin: 16, filterMax: 35), isTrue);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 20, filterMin: 18, filterMax: 25), isTrue);
    });

    test('Invalid filter ranges', () {
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 16, filterMin: 16, filterMax: 20), isFalse);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 16, filterMin: 15, filterMax: 19), isFalse);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 20, filterMin: 15, filterMax: 35), isFalse);
      expect(AgeSafetyRules.isValidFilterAge(viewerAge: 16, filterMin: 20, filterMax: 16), isFalse);
    });
  });
}
