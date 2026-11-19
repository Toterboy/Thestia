// Der Busy-Guard der Passkey-Zeremonie.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/auth/passkey_auth.dart 101 offene Zeilen. Der Guard
// (nur EINE Zeremonie gleichzeitig) war ungetestet - und er ist der
// Unterschied zwischen "der Nutzer muss einmal klicken" und "der
// Passkey ist dauerhaft kaputt".
//
// DER GRUND: Ein Doppel-Tap auf "Passkey erstellen" startete zwei
// Registrierungen parallel - die zweite brach die erste ab, und die
// Challenge-Verrechnung endete in "credential verification failed".
// Der Guard verhindert das. ABER: Ein Guard, der haengen bleibt
// (weil eine Zeremonie mit einem Fehler endet), wuerde jeden weiteren
// Passkey-Versuch des Nutzers blockieren - fuer immer. Das ist
// beides getestet.
//
// ANMERKUNG: Der Test braucht KEINEN Server. Ohne Supabase-Anbindung
// bricht die Zeremonie sofort ab - und genau das reicht, um den
// Guard zu pruefen: der Fehler darf den Guard NICHT festsitzen
// lassen.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/auth/auth_exception.dart';
import 'package:thestia/services/auth/passkey_auth.dart';

void main() {
  /// Passt der Fehler zur Meldung "laeuft bereits"?
  Matcher laeuftGerade() => predicate<AppException>(
    (e) => e.message.contains('läuft bereits'),
    'eine AppException mit "laeuft bereits"',
  );

  group('Der Busy-Guard der Passkey-Zeremonie', () {
    test(
      'ein zweiter Versuch waehrend einer laufenden Anfrage wird abgewiesen',
      () async {
        // DER WEG: Die erste Anfrage laeuft noch (sie haengt an einem
        // Fehler), die zweite kommt sofort danach.
        final erst = PasskeyAuth.signIn();
        final zweit = PasskeyAuth.signIn();

        // Die Erwartungen werden VOR dem Warten angemeldet - sonst gaebe
        // es eine unbehandelte Fehlermeldung.
        final h1 = expectLater(erst, throwsA(isA<AppException>()));
        final h2 = expectLater(zweit, throwsA(laeuftGerade()));

        await h1;
        await h2;

        expect(
          true,
          isTrue,
          reason: 'Der zweite Versuch muss abgewiesen worden sein.',
        );
      },
    );

    test('die Einrichtung und die Anmeldung schliessen sich aus', () async {
      // DER GRUND: Zwei Zeremonien gleichzeitig (eine Anmeldung und
      // eine Einrichtung) wuerden sich gegenseitig ins Gehege
      // kommen - der native Dialog gehoert nur einer davon.
      final anmeldung = PasskeyAuth.signIn();
      final einrichtung = PasskeyAuth.register();

      final h1 = expectLater(anmeldung, throwsA(isA<AppException>()));
      final h2 = expectLater(einrichtung, throwsA(laeuftGerade()));

      await h1;
      await h2;

      expect(true, isTrue);
    });

    test('der Guard wird nach einem Fehler wieder frei', () async {
      // DER GRUND: Wenn der Guard nach einem Fehler haengen bliebe,
      // koennte der Nutzer nie wieder einen Passkey einrichten oder
      // anmelden - die App waere fuer ihn tot.
      await expectLater(
        PasskeyAuth.signIn(),
        throwsA(isA<AppException>()),
        reason: 'Ohne Server muss die Anmeldung scheitern.',
      );

      // Der naechste Versuch darf NICHT am Guard scheitern, sondern
      // wieder am fehlenden Server.
      await expectLater(
        PasskeyAuth.signIn(),
        throwsA(
          predicate<AppException>(
            (e) => !e.message.contains('läuft bereits'),
            'ein Fehler, der NICHT vom Guard kommt',
          ),
        ),
        reason:
            'Der Guard muss nach dem Fehler wieder frei sein - sonst '
            'waeren alle weiteren Passkey-Versuche des Nutzers blockiert.',
      );
    });

    test('der Guard wird auch nach einer Einrichtung wieder frei', () async {
      await expectLater(PasskeyAuth.register(), throwsA(isA<AppException>()));

      await expectLater(
        PasskeyAuth.register(),
        throwsA(
          predicate<AppException>(
            (e) => !e.message.contains('läuft bereits'),
            'ein Fehler, der NICHT vom Guard kommt',
          ),
        ),
      );
    });
  });
}
