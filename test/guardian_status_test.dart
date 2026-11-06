import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/widgets/usage_time_gate.dart';

void main() {
  group('GuardianStatus', () {
    test('leere Antwort ergibt "unbekannt", nicht "keine Aufsicht"', () {
      const s = GuardianStatus.unknown;
      expect(s.isUnknown, isTrue);
      expect(s.loaded, isFalse);
      // WICHTIG: isUnknown ist nicht dasselbe wie "es gibt nichts".
      expect(s.hasConsent, isFalse);
    });

    test('fromJson liest die Felder des Servers', () {
      final s = GuardianStatus.fromJson({
        'consentState': 'granted',
        'supervised': true,
        'status': 'active',
        'age': 17,
        'guardianEmail': 'mutter@beispiel.de',
        'guardianEmailMasked': 'm***@beispiel.de',
        'notifyEnabled': true,
        'notifyFrequency': 'weekly',
        'usageLimitEnabled': true,
        'usageStartMin': 540,
        'usageEndMin': 1260,
        'hasPin': true,
        'accessPolicy': 'until_18',
        'accessUntil': '2026-12-31T23:59:59Z',
        'transitionPending': false,
      });

      expect(s.isActive, isTrue);
      expect(s.hasConsent, isTrue);
      expect(s.isPending, isFalse);
      expect(s.isMinor, isTrue);
      expect(s.justBecameAdult, isFalse);
      expect(s.notifyFrequency, 'weekly');
      expect(s.usageStartMin, 540);
      expect(s.usageEndMin, 1260);
      expect(s.hasPin, isTrue);
      expect(s.accessUntil, isNotNull);
      expect(s.loaded, isTrue);
    });

    test('ein 18-Jaehriger mit offener Entscheidung hat transitionPending', () {
      final s = GuardianStatus.fromJson({
        'status': 'active',
        'age': 18,
        'transitionPending': true,
      });
      expect(s.justBecameAdult, isTrue);
      expect(s.transitionPending, isTrue);
    });

    test('fehlende Felder ergeben sichere Standardwerte', () {
      final s = GuardianStatus.fromJson({'status': 'none'});
      expect(s.usageLimitEnabled, isFalse);
      expect(s.hasPin, isFalse);
      expect(s.notifyFrequency, 'none');
      expect(s.isMinor, isFalse);
      // Ohne Alter ist das Alter UNBEKANNT - nicht "erwachsen".
      expect(s.age, isNull);
    });
  });

  group('GuardianResult', () {
    test('ok hat keinen Code', () {
      const r = GuardianResult.ok();
      expect(r.isOk, isTrue);
      expect(r.code, isNull);
    });

    test('Fehler tragen den Code', () {
      const r = GuardianResult.failed('same_email');
      expect(r.isOk, isFalse);
      expect(r.code, 'same_email');
    });
  });

  group('UsageTimeGate.isWithinWindow', () {
    test('normales Fenster (9:00 bis 21:00)', () {
      bool drin(int min) => UsageTimeGate.isWithinWindow(
        nowMinutes: min,
        startMinutes: 9 * 60,
        endMinutes: 21 * 60,
      );
      expect(drin(9 * 60), isTrue);
      expect(drin(12 * 60), isTrue);
      expect(drin(20 * 60 + 59), isTrue);
      expect(drin(21 * 60), isFalse);
      expect(drin(8 * 60 + 59), isFalse);
      expect(drin(23 * 60), isFalse);
    });

    test('Fenster ueber Mitternacht (20:00 bis 06:00)', () {
      bool drin(int min) => UsageTimeGate.isWithinWindow(
        nowMinutes: min,
        startMinutes: 20 * 60,
        endMinutes: 6 * 60,
      );
      expect(drin(22 * 60), isTrue);
      expect(drin(2 * 60), isTrue);
      expect(drin(5 * 60 + 59), isTrue);
      expect(drin(6 * 60), isFalse);
      expect(drin(12 * 60), isFalse);
      expect(drin(19 * 60 + 59), isFalse);
      expect(drin(20 * 60), isTrue);
    });

    test('leeres Fenster (von == bis) sperrt NICHT', () {
      // Eine Fehlgabe des Elternteils darf die App nicht unbenutzbar
      // machen - und niemand wuesste, warum.
      expect(
        UsageTimeGate.isWithinWindow(
          nowMinutes: 3 * 60,
          startMinutes: 20 * 60,
          endMinutes: 20 * 60,
        ),
        isTrue,
      );
    });
  });
}
