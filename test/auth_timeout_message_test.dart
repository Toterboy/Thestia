import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests fuer die Fehlermeldung des Auth-Timeouts (v0.9.2).
///
/// Anlass: der 20-Sekunden-Timeout aus `login_screen.dart` warf
/// `TimeoutException`, und im `catch` gab es dafuer keinen Zweig. Er
/// landete in `error.generic` ("Etwas ist schiefgelaufen") und war damit
/// von einem CAPTCHA-Fehler, einem falschen Passwort und einem echten
/// Serverfehler nicht zu unterscheiden.
///
/// Fuer die offene Registrierungsfrage ist genau das der Unterschied: der
/// Nutzer wurde gebeten, den **Wortlaut** der Meldung zu schicken. Bei
/// "Etwas ist schiefgelaufen" ist diese Frage nicht beantwortbar.
void main() {
  // Die Quelle wird statisch gelesen, nicht ueber ein Widget: der
  // Timeout-Zweig liegt in einer privaten Methode mit BuildContext, und
  // ein Widget-Test wuerde Supabase initialisieren muessen.
  final loginSrc = File('lib/screens/auth/login_screen.dart').readAsStringSync();
  final stringsSrc =
      File('lib/l10n/app_strings.dart').readAsStringSync();

  group('Timeout-Zweig im catch', () {
    test('der catch behandelt TimeoutException ausdruecklich', () {
      // Ohne eigenen Zweig faellt der Timeout in den generischen else.
      expect(loginSrc.contains('e is TimeoutException'), isTrue);
    });

    test('der Timeout-Zweig nennt den neuen Schluessel', () {
      expect(loginSrc.contains("'error.serverUnreachable'"), isTrue);
    });

    test('der Zweig steht VOR dem generischen else im selben catch',
        () {
      // Ein Timeout-Zweig nach dem generischen else waere toter Code.
      //
      // Nur der catch-Block zaehlt: `error.generic` kommt weiter oben
      // schon im Provider-Fehlerzweig vor (Zeile ~264). Ein blindes
      // `indexOf` im ganzen File wuerde also den FALSCHEN Treffer finden
      // und den Test unabhaengig vom Umbau gruen halten.
      final catchAt = loginSrc.indexOf('} catch (e) {');
      expect(catchAt, greaterThan(-1));
      final block = loginSrc.substring(catchAt);

      final timeoutAt = block.indexOf('e is TimeoutException');
      final genericAt = block.indexOf("error.generic'");
      expect(timeoutAt, greaterThan(-1), reason: 'Timeout-Zweig fehlt');
      expect(genericAt, greaterThan(-1), reason: 'generischer else fehlt');
      expect(
        timeoutAt,
        lessThan(genericAt),
        reason: 'der Timeout-Zweig muss vor dem generischen else stehen, '
            'sonst ist er toter Code',
      );
    });
  });

  group('error.serverUnreachable', () {
    test('existiert in Deutsch und Englisch', () {
      final deMarker = "  'de': {";
      final enMarker = "  'en': {";
      final deBlock = stringsSrc.substring(
        stringsSrc.indexOf(deMarker),
        stringsSrc.indexOf(enMarker),
      );
      final enBlock = stringsSrc.substring(stringsSrc.indexOf(enMarker));

      expect(deBlock.contains("'error.serverUnreachable'"), isTrue);
      expect(enBlock.contains("'error.serverUnreachable'"), isTrue);
    });

    test('nennt die Ursache statt eines Sammelbegriffs', () {
      // "Etwas ist schiefgelaufen" waere genau die Formulierung, die die
      // Registrierungsfrage nicht beantwortet.
      final i = stringsSrc.indexOf("'error.serverUnreachable':");
      expect(i, greaterThan(-1));
      final de = stringsSrc.substring(i, i + 300);
      expect(de.toLowerCase().contains('server'), isTrue);
      expect(de.toLowerCase().contains('internet'), isTrue);
    });

    test('ist nicht die generische Meldung', () {
      final i = stringsSrc.indexOf("'error.serverUnreachable':");
      final block = stringsSrc.substring(i, i + 300);
      expect(block.contains('Etwas ist schiefgelaufen'), isFalse);
    });
  });

  group('Zeitgrenze des Timeouts', () {
    test('beträgt genau 20 Sekunden', () {
      // Die Zahl steckt als Sekunden-Wert in der Duration-Konstante.
      expect(
        loginSrc.contains('Duration(seconds: 20)'),
        isTrue,
        reason: 'Die Abnahme fordert "Fehler in 20 s". 8 oder 60 wären '
            'beides Rückschritte bzw. Umstellungen ohne sichtbaren Grund.',
      );
    });

    test('gilt für Registrierung UND Login', () {
      // Genau zwei .timeout(_authTimeout): einmal je Pfad. Ein drittes
      // oder nur eines wäre eine der beiden halb abgesichert.
      final count = RegExp(r'\.timeout\(_authTimeout\)')
          .allMatches(loginSrc)
          .length;
      expect(count, 2, reason: 'Beide Pfade brauchen dieselbe Grenze');
    });

    test('der Timeout ist als Konstante benannt, nicht inline', () {
      expect(
        loginSrc.contains('static const Duration _authTimeout'),
        isTrue,
      );
    });
  });
}
