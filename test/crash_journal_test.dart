import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/crash_journal.dart';

/// Der Redaktor des Crash-Journals.
///
/// BEFUND 04.11.2026: Das Journal versprach im Kommentar "keine
/// Nutzertexte, keine Geraete-Serials, keine PII" - speicherte aber
/// den ROHEN Fehlertext und den ROHEN Stack. Ein Supabase-Fehler kann
/// die E-Mail-Adresse enthalten, das Journal wird dem Nutzer aber per
/// Bug-Report angeboten - die Daten wuerden also das Geraet verlassen.
void main() {
  group('CrashJournal.redact', () {
    test('entfernt eine E-Mail-Adresse', () {
      const fehler = 'Invalid login credentials for user: max@example.de';
      final redigiert = CrashJournal.redact(fehler);

      expect(redigiert, isNot(contains('max@example.de')));
      expect(redigiert, contains('Invalid login credentials'));
    });

    test('entfernt mehrere E-Mail-Adressen', () {
      const fehler = 'von a@b.de nach c@d.de, Fehler in x@y.de und z@w.de';
      final redigiert = CrashJournal.redact(fehler);

      expect(redigiert, isNot(contains('@b.de')));
      expect(redigiert, isNot(contains('@d.de')));
      expect(redigiert, isNot(contains('@y.de')));
      expect(redigiert, isNot(contains('@w.de')));
    });

    test('entfernt eine E-Mail mit Sonderzeichen im Namen', () {
      const fehler = 'Nutzer max.mustermann+test@example.de nicht gefunden';
      final redigiert = CrashJournal.redact(fehler);

      expect(redigiert, isNot(contains('mustermann')));
      expect(redigiert, isNot(contains('example.de')));
      expect(redigiert, contains('nicht gefunden'));
    });

    test('entfernt ein Bearer-Token', () {
      const fehler =
          '401 mit Bearer eyJhbGciOiJIUzI1NiJ9abcdefghijklmnop.abc'
          '.def';
      final redigiert = CrashJournal.redact(fehler);

      expect(redigiert, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(redigiert, contains('401'));
    });

    test('entfernt ein JWT ohne Bearer-Prefix', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
          '.abcdefghijk';
      final redigiert = CrashJournal.redact(jwt);

      expect(
        redigiert,
        isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')),
      );
    });

    test('entfernt einen langen Hex-Schluessel', () {
      const fehler =
          'Hash: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final redigiert = CrashJournal.redact(fehler);

      expect(redigiert, isNot(contains('0123456789abcdef0123456789abcdef')));
      expect(redigiert, contains('Hash:'));
    });

    test('behaelt die UUID der eigenen User-ID (fuer den Bug-Report)', () {
      const uuid = '46f3f558-b134-4d25-946b-4e052a8ab3b5';
      final redigiert = CrashJournal.redact('Fehler bei $uuid');

      // Die User-ID wird fuer die Bearbeitung des Bug-Reports
      // gebraucht ("nenne dazu deine User-ID"). Sie wird nicht
      // redigiert.
      expect(redigiert, contains(uuid));
    });

    test('behaelt Dateipfade und Zeilennummern (ohne sie ist der '
        'Absturz nicht zuzuordnen)', () {
      const stack = '#0      main (package:thestia/main.dart:42:7)';
      final redigiert = CrashJournal.redact(stack);

      expect(redigiert, contains('main.dart:42:7'));
    });

    test('laesst einen Text ohne PII unveraendert', () {
      const text = 'Bad state: No element';
      expect(CrashJournal.redact(text), text);
    });
  });
}
