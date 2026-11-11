// Test fuer das Transit-Kandidaten-Modell (v0.10.1).
//
// BEFUND (11.11.2026, Betreiber): "wenn es bei Transit Spark mehrere mit
// der selben Beschreibung geben sollte, dass man dann alle dafuer
// vorgeschlagen bekommt".
//
// WICHTIG (Datenschutz): Der Name erscheint NUR, wenn die Person ihn
// freigegeben hat. Der Ort ist ihre eigene Angabe. Dieser Test haelt
// beides fest.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/transit_models.dart';

void main() {
  group('TransitCandidate', () {
    test('liest die Merkmale, die Notiz und den Ort', () {
      final k = TransitCandidate.fromJson(const {
        'id': 'abc',
        'tags': ['hemd', 'brille'],
        'selfTags': ['hemd'],
        'note': 'Bis 18 Uhr',
        'placeKind': 'messe',
        'placeText': 'Halle 2 bei den Toiletten',
        'name': 'Hermine',
        'showName': true,
      });
      expect(k.id, 'abc');
      expect(k.tags, ['hemd', 'brille']);
      expect(k.selfTags, ['hemd']);
      expect(k.note, 'Bis 18 Uhr');
      expect(k.placeKind, 'messe');
      expect(k.place, 'Halle 2 bei den Toiletten');
      expect(k.name, 'Hermine');
      expect(k.showName, isTrue);
    });

    test('ohne Namensfreigabe bleibt der Name leer', () {
      // Der Server liefert den Namen nur bei Freigabe - der Client darf
      // keinen Namen erfinden, wenn keiner da ist.
      final k = TransitCandidate.fromJson(const {
        'id': 'abc',
        'tags': ['hemd'],
        'showName': false,
      });
      expect(k.name, isNull);
      expect(k.showName, isFalse);
    });

    test('ein leerer Ort wird als leer angezeigt', () {
      final k = TransitCandidate.fromJson(const {
        'id': 'abc',
        'tags': [],
        'placeText': '   ',
      });
      expect(k.place, isNull);
    });

    test('fehlende Felder ergeben leere Werte (kein Absturz)', () {
      final k = TransitCandidate.fromJson(const {'id': 'abc'});
      expect(k.tags, isEmpty);
      expect(k.selfTags, isEmpty);
      expect(k.note, isNull);
      expect(k.place, isNull);
      expect(k.name, isNull);
    });

    test('die Merkmale kommen als Liste (kein Leerstring-Bruch)', () {
      final k = TransitCandidate.fromJson(const {
        'id': 'abc',
        'tags': ['a', 'b'],
      });
      expect(k.tags.length, 2);
      expect(k.tags.every((e) => e.isNotEmpty), isTrue);
    });
  });
}
