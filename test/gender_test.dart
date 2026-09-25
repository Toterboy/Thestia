import 'package:thestia/models/gender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gender', () {
test('Alle Werte vorhanden', () {
      expect(Gender.values.length, 6);
      expect(Gender.male.value, 'male');
      expect(Gender.female.value, 'female');
      expect(Gender.maleTrans.value, 'male_trans');
      expect(Gender.femaleTrans.value, 'female_trans');
      expect(Gender.diverse.value, 'diverse');
      expect(Gender.other.value, 'other');
    });

    test('Labels sind nicht leer', () {
      for (final gender in Gender.values) {
        expect(gender.label, isNotEmpty);
      }
    });

    test('fromValue liefert male bei male', () {
      expect(Gender.fromValue('male'), Gender.male);
    });

    test('fromValue liefert female bei female', () {
      expect(Gender.fromValue('female'), Gender.female);
    });

    test('fromValue liefert diverse bei diverse', () {
      expect(Gender.fromValue('diverse'), Gender.diverse);
    });

    test('fromValue liefert other bei other', () {
      expect(Gender.fromValue('other'), Gender.other);
    });

    test('fromValue liefert other bei ungueltigem Wert', () {
      expect(Gender.fromValue('invalid'), Gender.other);
    });

    test('fromValue liefert null bei null', () {
      expect(Gender.fromValue(null), isNull);
    });
  });

  group('GenderPreference', () {
test('Alle Werte vorhanden', () {
      expect(GenderPreference.values.length, 7);
      expect(GenderPreference.male.value, 'male');
      expect(GenderPreference.female.value, 'female');
      expect(GenderPreference.maleTrans.value, 'male_trans');
      expect(GenderPreference.femaleTrans.value, 'female_trans');
      expect(GenderPreference.diverse.value, 'diverse');
      expect(GenderPreference.other.value, 'other');
      expect(GenderPreference.all.value, 'all');
    });

    test('Labels sind nicht leer', () {
      for (final pref in GenderPreference.values) {
        expect(pref.label, isNotEmpty);
      }
    });

    test('fromValue liefert male bei male', () {
      expect(GenderPreference.fromValue('male'), GenderPreference.male);
    });

    test('fromValue liefert female bei female', () {
      expect(GenderPreference.fromValue('female'), GenderPreference.female);
    });

    test('fromValue liefert diverse bei diverse', () {
      expect(GenderPreference.fromValue('diverse'), GenderPreference.diverse);
    });

    test('fromValue liefert all bei all', () {
      expect(GenderPreference.fromValue('all'), GenderPreference.all);
    });

    test('fromValue liefert all bei ungueltigem Wert', () {
      expect(GenderPreference.fromValue('invalid'), GenderPreference.all);
    });

    test('fromValue liefert all bei null', () {
      expect(GenderPreference.fromValue(null), GenderPreference.all);
    });
  });
}

