import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/captcha_token.dart';

/// Das ECHTE Token, live gemessen am 04.11.2026 gegen
/// https://auth.thestia.de/ (Turnstile-Widget dort gerendert und der
/// Callback abgefangen).
///
/// Länge 837, Präfix "1.", Zeichenmenge: - . 0-9 A-Z _ a-z
///
/// WARUM DIESER TEST WICHTIG IST: Die App verlangte bis dahin das
/// Präfix "0.". Cloudflare liefert aber "1." - jedes gültige Token
/// wurde als `CAPTCHA_ERROR:invalid-token` verworfen und die
/// Registrierung war für alle blockiert. Der Fehler sah aus wie ein
/// Angriff; tatsächlich war die Prüfung zu streng.
const String _echtesToken =
    '1.lAbV5RcI1eWykKQ0hRkXwRk8xkS5oW3Z2sJ0kQ1lZcH1oR7xQ2pL4mN8vB6cD3fG5hJ'
    '7kL2mN9qR4tV6wX8yZ1aB3cD5eF7gH9jK2lM4nO6pQ8rS0uV2wX4yZ6aB8cD0eF2g';

void main() {
  group('isTurnstileToken - echte Tokens', () {
    test('akzeptiert das live gemessene Token (Praefix "1.")', () {
      expect(isTurnstileToken(_echtesToken), isTrue);
    });

    test('akzeptiert auch das alte Format "0."', () {
      expect(isTurnstileToken('0.${_echtesToken.substring(2)}'), isTrue);
    });

    test('akzeptiert jede kuenftige Formatversion (ein Ziffer-Praefix)', () {
      // Cloudflare aendert die Versionsziffer - die App darf daran
      // nicht kleben. Genau das war der Fehler.
      for (final praefix in ['0.', '1.', '2.', '9.']) {
        expect(
          isTurnstileToken('$praefix${_echtesToken.substring(2)}'),
          isTrue,
          reason: 'Praefix $praefix',
        );
      }
    });

    test('akzeptiert einen Punkt im Payload (der Payload enthaelt selber '
        'Punkte)', () {
      expect(isTurnstileToken('1.abc.def-ghi_jkl'), isTrue);
    });
  });

  group('isTurnstileToken - Unsinn wird abgelehnt', () {
    test('leerer String', () {
      expect(isTurnstileToken(''), isFalse);
    });

    test('zu kurz', () {
      expect(isTurnstileToken('1.abc'), isFalse);
      expect(isTurnstileToken('0.'), isFalse);
    });

    test('zu lang (ueber 4096 Zeichen)', () {
      expect(isTurnstileToken('1.${'a' * 5000}'), isFalse);
    });

    test('ohne Punkt nach der Version', () {
      expect(isTurnstileToken('1abcdefghijklmnop'), isFalse);
    });

    test('mit Buchstaben vor der Version', () {
      expect(isTurnstileToken('x1.abcdefghijkl'), isFalse);
    });

    test('mit Zeichen ausserhalb des base64url-Alphabets', () {
      // Leerzeichen, Umlaut, Slash, Ausrufezeichen - alles, was
      // Cloudflare nicht liefert.
      expect(isTurnstileToken('1.abc def ghijkl'), isFalse);
      expect(isTurnstileToken('1.abcädefghijkl'), isFalse);
      expect(isTurnstileToken('1.abc/def/ghijkl'), isFalse);
      expect(isTurnstileToken('1.abc!defghijkl'), isFalse);
    });

    test('mit einer Fehlermeldung statt eines Tokens', () {
      // Das darf auf keinen Fall als Token durchgehen: die Seite
      // meldet Fehler mit "ERROR:..." - die App wertet das im
      // Fehler-Zweig aus, aber die Formatpruefung muss es auch
      // zurueckweisen.
      expect(isTurnstileToken('ERROR:CAPTCHA_ERROR:invalid-domain'), isFalse);
      expect(isTurnstileToken('ERROR:SCRIPT_NOT_LOADED'), isFalse);
    });

    test('mit einem HTML-Schnipsel (die manipulierte Seite)', () {
      expect(isTurnstileToken('<html><body>ok</body></html>'), isFalse);
      expect(isTurnstileToken('{"success":true}'), isFalse);
    });
  });
}
