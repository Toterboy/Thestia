import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/best_effort.dart';

/// Tests fuer den zentralen Helfer fuer Schritte, deren Fehler den
/// Ablauf nicht stoppen duerfen.
///
/// WARUM (05.11.2026): In der App gab es 94 leere
/// `catch (_) {}`-Bloecke. Sie verschluckten jeden Fehler spurlos -
/// beim Aufräumen nach dem Abmelden war nicht mehr zu sehen, was
/// schiefging. Der Helfer macht dasselbe wie vorher (der Fehler
/// stoppt den Ablauf nicht), laesst ihn aber nicht verschwinden.
void main() {
  group('bestEffort', () {
    test('ein erfolgreicher Schritt laeuft durch', () async {
      var aufgerufen = false;
      await bestEffort('Schritt', () async {
        aufgerufen = true;
      });
      expect(aufgerufen, isTrue);
    });

    test('ein Fehler stoppt den Ablauf nicht', () async {
      var danachAusgefuehrt = false;
      await bestEffort('Schritt', () async {
        throw StateError('kaputt');
      });
      danachAusgefuehrt = true;
      expect(danachAusgefuehrt, isTrue);
    });

    test('ein Fehler wird geschluckt, nicht weitergegeben', () async {
      // Wichtig: der Aufrufer darf keinen Fehler sehen - sonst waere
      // das Verhalten anders als bei einem leeren catch.
      await expectLater(
        bestEffort('Schritt', () async {
          throw StateError('kaputt');
        }),
        completes,
      );
    });
  });

  group('bestEffortSync', () {
    test('ein erfolgreicher Schritt laeuft durch', () {
      var aufgerufen = false;
      bestEffortSync('Schritt', () {
        aufgerufen = true;
      });
      expect(aufgerufen, isTrue);
    });

    test('ein Fehler stoppt den Ablauf nicht', () {
      var danachAusgefuehrt = false;
      bestEffortSync('Schritt', () {
        throw StateError('kaputt');
      });
      danachAusgefuehrt = true;
      expect(danachAusgefuehrt, isTrue);
    });
  });

  group('bestEffortOr', () {
    test('liefert den Wert des Schritts', () async {
      final wert = await bestEffortOr('Schritt', () async => 42, 0);
      expect(wert, 42);
    });

    test('liefert den Ersatzwert, wenn der Schritt fehlschlaegt', () async {
      final wert = await bestEffortOr(
        'Schritt',
        () async => throw StateError('kaputt'),
        -1,
      );
      expect(wert, -1);
    });

    test('liefert null, wenn der Schritt fehlschlaegt', () async {
      final wert = await bestEffortOr<Map<String, dynamic>?>(
        'Schritt',
        () async => throw StateError('kaputt'),
        null,
      );
      expect(wert, isNull);
    });
  });

  group('bestEffortOrSync', () {
    test('liefert den Wert des Schritts', () {
      expect(bestEffortOrSync('Schritt', () => 42, 0), 42);
    });

    test('liefert den Ersatzwert, wenn der Schritt fehlschlaegt', () {
      expect(
        bestEffortOrSync(
          'Schritt',
          () => throw StateError('kaputt'),
          -1,
        ),
        -1,
      );
    });
  });
}
