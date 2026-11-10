// Test fuer die neue Einstellung "Namen beim Zuwinken zeigen" (v0.10.1).
//
// Prueft:
//  1. Das Modell kennt die Einstellung und speichert sie lokal.
//  2. Der Standard ist "an" (der Name wird beim Zuwinken gezeigt).
//  3. Der Server-Schalter wird beim Start uebernommen ("Server gewinnt").
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/app_settings.dart';

void main() {
  group('AppSettings.transitShowName', () {
    test('der Standard ist "an" (der Name wird gezeigt)', () {
      final s = AppSettings.defaults();
      expect(s.transitShowName, isTrue);
    });

    test('aus der JSON kommt der Serverwert', () {
      final s = AppSettings.fromJson(const {'transitShowName': false});
      expect(s.transitShowName, isFalse);
    });

    test('fehlt der Wert, gilt der Standard "an"', () {
      final s = AppSettings.fromJson(const {});
      expect(s.transitShowName, isTrue);
    });

    test('copyWith schaltet um, ohne das andere zu verlieren', () {
      final s = AppSettings.defaults().copyWith(
        transitShowName: false,
        showDistance: true,
      );
      expect(s.transitShowName, isFalse);
      expect(s.showDistance, isTrue);
    });

    test('toJson schreibt den Wert mit (lokale Persistenz)', () {
      final json = AppSettings.defaults()
          .copyWith(transitShowName: false)
          .toJson();
      expect(json['transitShowName'], isFalse);
    });
  });
}
