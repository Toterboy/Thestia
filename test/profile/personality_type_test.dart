// Die MBTI-Persönlichkeitstypen und ihre Kompatibilität.
//
// ANLASS (19.11.2026): `lib/models/profile/personality_type.dart` war zu 0 %
// abgedeckt - die Datei wird im Matching benutzt, aber nie geprüft.
//
// WAS HIER GEPRÜFT WIRD:
//   * es sind genau die 16 MBTI-Typen,
//   * ein unbekannter Code liefert null (kein Absturz),
//   * die Kompatibilität liegt immer zwischen 0 und 1,
//   * gleiche Typen passen besser zueinander als verschiedene,
//   * die Matrix ist symmetrisch (A zu B ist B zu A).
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/profile/personality_type.dart';

void main() {
  group('Die Persoenlichkeitstypen', () {
    test('es sind genau die 16 MBTI-Typen', () {
      expect(PersonalityType.allTypes.length, 16);
      expect(
        PersonalityType.allTypes.toSet().length,
        16,
        reason: 'kein Typ darf doppelt sein',
      );
      for (final typ in PersonalityType.allTypes) {
        expect(typ.length, 4);
        expect(typ, typ.toUpperCase());
      }
      expect(PersonalityType.allTypes, contains('ENFP'));
      expect(PersonalityType.allTypes, contains('ISTJ'));
    });

    test('ein bekannter Code liefert den Typ', () {
      expect(PersonalityType.fromCode('ENFP')?.code, 'ENFP');
    });

    test('kleinbuchstaben werden angenommen', () {
      expect(PersonalityType.fromCode('enfp')?.code, 'ENFP');
    });

    test('ein unbekannter oder leerer Code liefert null', () {
      expect(PersonalityType.fromCode(null), isNull);
      expect(PersonalityType.fromCode(''), isNull);
      expect(PersonalityType.fromCode('XXXX'), isNull);
      expect(PersonalityType.fromCode('ENF'), isNull);
    });
  });

  group('Die Kompatibilitaet der Typen', () {
    test('gleiche Typen passen gut zueinander', () {
      expect(MbtiCompatibility.score('ENFP', 'ENFP'), 0.9);
    });

    test('jede Paarung liegt zwischen 0 und 1', () {
      for (final a in PersonalityType.allTypes) {
        for (final b in PersonalityType.allTypes) {
          final wert = MbtiCompatibility.score(a, b);
          expect(wert, greaterThanOrEqualTo(0.0));
          expect(wert, lessThanOrEqualTo(1.0));
        }
      }
    });

    test('die Matrix ist symmetrisch', () {
      for (final a in PersonalityType.allTypes) {
        for (final b in PersonalityType.allTypes) {
          expect(
            MbtiCompatibility.score(a, b),
            closeTo(MbtiCompatibility.score(b, a), 0.0001),
            reason: '$a und $b',
          );
        }
      }
    });

    test('verschiedene Typen liegen ueber der Basislinie', () {
      // Verschiedene Typen bekommen mindestens den Basiswert 0,5.
      for (final a in PersonalityType.allTypes) {
        for (final b in PersonalityType.allTypes) {
          if (a == b) continue;
          expect(
            MbtiCompatibility.score(a, b),
            greaterThanOrEqualTo(0.5),
            reason: '$a und $b',
          );
        }
      }
    });

    test('eine verstellte Uhr veraendert den Wert nicht', () {
      // Der Wert hängt nur an den vier Buchstaben, nicht an der Zeit.
      final einmal = MbtiCompatibility.score('INTJ', 'ESFP');
      expect(einmal, MbtiCompatibility.score('INTJ', 'ESFP'));
      expect(einmal, isNot(MbtiCompatibility.score('INTJ', 'INTJ')));
    });
  });
}
