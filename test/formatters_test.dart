import 'package:thestia/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters - distance', () {
    test('Unter 1 km wird als "< 1 km" formatiert', () {
      expect(Formatters.distance(0.0), '< 1 km');
      expect(Formatters.distance(0.3), '< 1 km');
      expect(Formatters.distance(0.9), '< 1 km');
    });

    test('Ganze km werden ohne Dezimalstellen formatiert', () {
      expect(Formatters.distance(1.0), '1 km');
      expect(Formatters.distance(5.0), '5 km');
      expect(Formatters.distance(10.0), '10 km');
      expect(Formatters.distance(100.0), '100 km');
    });

    test('Dezimale km werden gerundet', () {
      expect(Formatters.distance(1.4), '1 km');
      expect(Formatters.distance(1.5), '2 km');
      expect(Formatters.distance(5.7), '6 km');
      expect(Formatters.distance(9.9), '10 km');
    });
  });

  group('Formatters - time', () {
    test('Formatiert Stunden und Minuten mit fuehrenden Nullen', () {
      final morning = DateTime(2024, 1, 1, 9, 5);
      expect(Formatters.time(morning), '09:05');

      final afternoon = DateTime(2024, 1, 1, 14, 30);
      expect(Formatters.time(afternoon), '14:30');

      final midnight = DateTime(2024, 1, 1, 0, 0);
      expect(Formatters.time(midnight), '00:00');

      final noon = DateTime(2024, 1, 1, 12, 0);
      expect(Formatters.time(noon), '12:00');

      final lateNight = DateTime(2024, 1, 1, 23, 59);
      expect(Formatters.time(lateNight), '23:59');
    });
  });

  group('Formatters - relative', () {
    test('Gerade eben fuer weniger als 1 Minute', () {
      final now = DateTime.now();
      expect(Formatters.relative(now), 'gerade eben');
    });

    test('vor X Min. fuer 1-59 Minuten', () {
      final fiveMinAgo = DateTime.now().subtract(const Duration(minutes: 5));
      expect(Formatters.relative(fiveMinAgo), 'vor 5 Min.');

      final fiftyNineMinAgo = DateTime.now().subtract(const Duration(minutes: 59));
      expect(Formatters.relative(fiftyNineMinAgo), 'vor 59 Min.');
    });

    test('vor X Std. fuer 1-23 Stunden', () {
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      expect(Formatters.relative(twoHoursAgo), 'vor 2 Std.');

      final twentyThreeHoursAgo = DateTime.now().subtract(const Duration(hours: 23));
      expect(Formatters.relative(twentyThreeHoursAgo), 'vor 23 Std.');
    });

    test('gestern fuer genau 1 Tag', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(Formatters.relative(yesterday), 'gestern');
    });

    test('vor X Tagen fuer mehr als 1 Tag', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      expect(Formatters.relative(twoDaysAgo), 'vor 2 Tagen');

      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      expect(Formatters.relative(tenDaysAgo), 'vor 10 Tagen');
    });
  });

  group('Formatters - ageFromBirthDate', () {
    test('null liefert null', () {
      expect(Formatters.ageFromBirthDate(null), isNull);
    });

    test('Datum in der Zukunft liefert null', () {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(Formatters.ageFromBirthDate(future), isNull);
    });

    test('Berechnet Alter korrekt', () {
      final birthDate = DateTime.now().subtract(const Duration(days: 25 * 365));
      final age = Formatters.ageFromBirthDate(birthDate);
      expect(age, isNotNull);
      expect(age, inInclusiveRange(24, 26));
    });
  });
}

