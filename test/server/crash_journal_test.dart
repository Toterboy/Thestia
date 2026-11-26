// Das lokale Crash-Journal.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/services/server/crash_journal.dart nur 38 % Abdeckung. Das
// Journal ist der einzige Ort, an dem ein Absturz landet - und es wird
// dem Nutzer als Bug-Report angeboten.
//
// DER WEG: Die Redigierregeln sind öffentlich (`redact`), damit sie
// testbar sind - "eine Redigierregel, die nicht getestet wird, ist eine
// Regel, die irgendwann nicht mehr greift" (so der Kommentar im Code).
//
// WAS HIER GEPRÜFT WIRD:
//   * eine E-Mail-Adresse wird entfernt (der häufigste PII-Weg),
//   * ein Token (Bearer und JWT) wird entfernt,
//   * ein langer Schlüssel wird entfernt,
//   * die eigene User-ID (UUID) BLEIBT stehen - der Nutzer soll sie
//     beim Bug-Report nennen können,
//   * der Absturz wird gespeichert, gelesen und wieder gelöscht.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/server/crash_journal.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  group('Die Redigierung', () {
    test('eine E-Mail-Adresse wird entfernt', () {
      const text = 'Invalid login credentials for user: lena@beispiel.de';

      final redigiert = CrashJournal.redact(text);

      expect(
        redigiert,
        isNot(contains('lena@beispiel.de')),
        reason:
            'Die E-Mail-Adresse darf nicht im Journal stehen - der Bug-Report '
            'wird aus dem Journal erstellt und geht aus dem Geraet heraus.',
      );
    });

    test('ein Bearer-Token wird entfernt', () {
      const text = 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345';

      final redigiert = CrashJournal.redact(text);

      expect(
        redigiert,
        isNot(contains('abcdefghijklmnopqrstuvwxyz')),
        reason: 'Ein Token im Journal waere ein offener Zugang.',
      );
    });

    test('ein JWT wird entfernt', () {
      const token =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
          '.abcdefghij';

      final redigiert = CrashJournal.redact(token);

      expect(
        redigiert,
        isNot(contains('eyJhbGciOi')),
        reason: 'Ein JWT im Journal waere ein offener Zugang.',
      );
    });

    test('ein langer Schluessel wird entfernt', () {
      const text = 'Hash: 0123456789abcdef0123456789abcdef';

      final redigiert = CrashJournal.redact(text);

      expect(
        redigiert,
        isNot(contains('0123456789abcdef')),
        reason: 'Ein Schluessel im Journal waere ein offener Zugang.',
      );
    });

    test('die eigene User-ID bleibt stehen', () {
      // DIE UUID: Der Nutzer soll sie beim Bug-Report nennen können -
      // ohne sie kann der Support den Fall nicht zuordnen.
      const text = 'User 11111111-2222-3333-4444-555555555555 hat geknallt';

      final redigiert = CrashJournal.redact(text);

      expect(
        redigiert,
        contains('11111111-2222-3333-4444-555555555555'),
        reason:
            'Die eigene User-ID muss stehen bleiben - der Support kann den '
            'Fall sonst nicht zuordnen.',
      );
    });

    test('ein harmloser Text bleibt unveraendert', () {
      const text = 'Null check operator used on a null value';

      expect(CrashJournal.redact(text), text);
    });
  });

  group('Das Journal', () {
    test('der Absturz wird gespeichert und gelesen', () async {
      await CrashJournal.capture(
        StateError('Der Fehler mit lena@beispiel.de'),
        StackTrace.fromString('#0      frame (package:app/main.dart:1)'),
      );

      final gelesen = await CrashJournal.readLastCrash();

      expect(gelesen, isNotNull, reason: 'Der Absturz muss im Journal stehen.');
      expect(
        gelesen,
        isNot(contains('lena@beispiel.de')),
        reason: 'Auch im Journal darf die E-Mail-Adresse nicht stehen.',
      );
    });

    test('nach dem Behandeln ist der Eintrag weg', () async {
      await CrashJournal.capture(StateError('Absturz'), null);
      expect(await CrashJournal.readLastCrash(), isNotNull);

      await CrashJournal.clear();

      expect(
        await CrashJournal.readLastCrash(),
        isNull,
        reason:
            'Nach dem Behandeln muss das Journal leer sein - sonst wird der '
            'alte Absturz beim naechsten Start nochmal angeboten.',
      );
    });
  });
}
