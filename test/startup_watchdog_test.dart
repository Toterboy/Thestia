import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/startup_watchdog.dart';

/// Start-Wächter: der Weg, der auf dem Telefon ohne Computer und ohne
/// Konsole aus der Sackgasse "Die App konnte nicht gestartet werden"
/// herausführt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // Die Schreibvorgaenge des Wächters sind absichtlich fire-and-forget
  // (der Start darf nie warten). Im Test muss man ihnen trotzdem
  // nachlaufen - SharedPreferences geht über einen Plattformkanal, das
  // braucht mehr als einen Tick.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('Erfolgreicher Start', () {
    test('hinterlaesst keinen Befund', () async {
      StartupWatchdog.reached(0);
      StartupWatchdog.reached(1);
      StartupWatchdog.reached(5);
      StartupWatchdog.markAlive();
      await settle();

      expect(await StartupWatchdog.readPreviousAttempt(), isNull);
    });

    test('ein alter Fehler wird beim naechsten Start aufgeraeumt', () async {
      // Ein Fehler, danach ein sauberer Start. Ohne Aufraeumen wuerde
      // der alte Befund beim Start danach wieder erscheinen und der
      // Nutzer glaubt, es sei noch nicht behoben.
      StartupWatchdog.reached(4, error: Exception('alter Fehler'));
      await settle();
      StartupWatchdog.markAlive();
      await settle();
      expect(await StartupWatchdog.readPreviousAttempt(), isNull);
    });
  });

  group('Abgestuerzter Start', () {
    test('nennt den letzten erreichten Schritt', () async {
      StartupWatchdog.reached(0);
      StartupWatchdog.reached(1);
      StartupWatchdog.reached(2);
      await settle();

      final f = await StartupWatchdog.readPreviousAttempt();
      expect(f, isNotNull);
      expect(f!.step, 'keystore');
      expect(f.stepIndex, 2);
      expect(f.diedBeforeDart, isFalse);
      expect(f.headline, contains('3 von 6'));
    });

    test('behaelt den Fehlertext des Schritts', () async {
      StartupWatchdog.reached(4, error: Exception('Supabase nicht erreichbar'));
      await settle();

      final f = await StartupWatchdog.readPreviousAttempt();
      expect(f!.error, contains('Supabase nicht erreichbar'));
    });

    test('ein Schritt ohne Fehler raeumt einen alten Fehlertext ab', () async {
      // Sonst zeigte der Screen nach einem erfolgreichen Teilschritt
      // weiter den Fehler des vorherigen.
      StartupWatchdog.reached(4, error: Exception('kaputt'));
      await settle();
      StartupWatchdog.reached(5);
      await settle();

      final f = await StartupWatchdog.readPreviousAttempt();
      expect(f!.error, isNull);
    });

    test('ohne jeden Schritt heisst es: Absturz vor Dart', () async {
      // Der wichtigste Fall. Liegt der Prozesssturz nativ, erreicht
      // Dart nie Schritt 0 - und genau das ist die Information, die
      // sagt "suche nicht im Dart-Code".
      final f = await StartupWatchdog.readPreviousAttempt();
      expect(f, isNotNull, reason: 'es muss einen Befund geben');
      expect(f!.diedBeforeDart, isTrue);
      expect(f.step, isNull);
      expect(f.stepIndex, -1);
    });
  });

  group('Bericht zum Kopieren', () {
    test('enthaelt Schritt, Zeitpunkt und Schrittliste', () async {
      StartupWatchdog.reached(3, error: Exception('Boom'));
      await settle();
      final f = await StartupWatchdog.readPreviousAttempt();
      final text = f!.toReport();

      expect(text, contains('Startprotokoll'));
      expect(text, contains('Schritt:'));
      expect(text, contains('Boom'));
      expect(text, contains('Startprotokoll'));
      // Die Schrittliste hilft beim Zuordnen, ohne dass man raten muss.
      expect(text, contains('dart-main'));
      expect(text, contains('keystore'));
    });

    test('erklaert den Sonderfall "vor Dart"', () async {
      final f = await StartupWatchdog.readPreviousAttempt();
      final text = f!.toReport();
      expect(text, contains('native'), reason: 'muss sagen, wo man sucht');
    });

    test('enthaelt keine leere Fehlerrubrik, wenn es keinen Fehler gab',
        () async {
      StartupWatchdog.reached(1);
      await settle();
      final f = await StartupWatchdog.readPreviousAttempt();
      expect(f!.toReport(), isNot(contains('Fehler:')));
    });
  });

  test('Schrittgrenzen werden nicht ueberschritten', () async {
    // Ein Tippfehler in einem Aufruf darf nicht still zu einem
    // unauffaelligen "Schritt 0" fuehren.
    StartupWatchdog.reached(99);
    StartupWatchdog.reached(-1);
    await settle();
    final f = await StartupWatchdog.readPreviousAttempt();
    expect(f!.step, isNull,
        reason: 'ungueltige Schrittnummer darf nichts schreiben');
  });
}
