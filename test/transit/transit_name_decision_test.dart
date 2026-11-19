// Test fuer die Namens-Entscheidung beim Transit Spark (v0.10.1).
//
// BEFUND (Betreiber, 10.11.2026): "Die Abfrage über die Entscheidung
// Name an oder aus soll beim ersten öffnen des Transit Spark screens
// kommen und dann nachträglich noch änderbar sein."
//
// Geprueft wird das Modell: der Wert (AN/AUS) und das Flag "hat der
// Nutzer entschieden" (das den Dialog steuert) sind getrennt.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/app_settings.dart';

void main() {
  group('AppSettings.transitShowName / transitShowNameSet', () {
    test('der Standard ist "unentschieden" (der Dialog kommt)', () {
      final s = AppSettings.defaults();
      expect(s.transitShowNameSet, isFalse);
      // Der Wert bis zur Entscheidung: "an" (damit nichts kompliziert ist,
      // bevor der Nutzer gefragt wurde).
      expect(s.transitShowName, isTrue);
    });

    test('nach der Entscheidung: der Wert ist gesetzt, das Flag auch', () {
      final s = AppSettings.defaults().copyWith(
        transitShowName: false,
        transitShowNameSet: true,
      );
      expect(s.transitShowName, isFalse);
      expect(s.transitShowNameSet, isTrue);
    });

    test('aus der JSON kommen beide Werte (Server-Stand)', () {
      final s = AppSettings.fromJson(const {
        'transitShowName': false,
        'transitShowNameSet': true,
      });
      expect(s.transitShowName, isFalse);
      expect(s.transitShowNameSet, isTrue);
    });

    test('fehlt das Flag, gilt "unentschieden" (Dialog kommt)', () {
      final s = AppSettings.fromJson(const {'transitShowName': true});
      expect(s.transitShowNameSet, isFalse);
    });

    test('toJson schreibt beide Werte mit (lokale Persistenz)', () {
      final json = AppSettings.defaults()
          .copyWith(transitShowName: false, transitShowNameSet: true)
          .toJson();
      expect(json['transitShowName'], isFalse);
      expect(json['transitShowNameSet'], isTrue);
    });
  });
}
