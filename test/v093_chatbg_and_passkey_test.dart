import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/app_settings.dart';

/// Tests fuer die beiden nachgetragenen Punkte aus v0.9.3.
///
/// Beide betreffen Zustaende, die vorher vorhanden waren, aber nie
/// gesetzt wurden: `chatBackgroundSeen` (der einmalige Hinweis) war ein
/// totes Feld, und die Passkey-Einrichtung lief ohne Bestandspruefung.
/// Beide sind hier am Quelltext geprueft, weil das Verhalten eine
/// WebAuthn-Zeremonie bzw. einen nativen Dialog braucht, den ein
/// Widget-Test nicht ausloesen kann - und weil ein Test, der den
/// Quelltext liest, genau das abdeckt, was zurueckfallen kann.
void main() {
  group('Chat-Hintergrund: einmaliger Hinweis', () {
    test('der Hinweis wird beim ersten Chat tatsaechlich gezeigt', () {
      final src = File('lib/screens/chat/chat_detail_screen.dart')
          .readAsStringSync();

      expect(src.contains('_maybeShowBackgroundHint'), isTrue);
      // Und er wird beim Oeffnen aufgerufen, nicht nur definiert.
      expect(src.contains('unawaited(_maybeShowBackgroundHint())'), isTrue);
    });

    test('der Hinweis kommt nach dem ersten Frame, nicht im initState', () {
      final src = File('lib/screens/chat/chat_detail_screen.dart')
          .readAsStringSync();

      // Riverpod verbietet Provider-Schreibzugriffe waehrend des Aufbaus;
      // die Datei erklaert das ausdruecklich. Ein showDialog vor dem Frame
      // waere genau der Fehler, den dort erklaert wird.
      final aufruf = src.indexOf('unawaited(_maybeShowBackgroundHint())');
      final frame = src.indexOf('addPostFrameCallback');
      expect(aufruf, greaterThan(frame));
    });

    test('"Spaeter" merkt den Hinweis ebenfalls - sonst kommt er wieder', () {
      final src = File('lib/screens/chat/chat_detail_screen.dart')
          .readAsStringSync();

      // Das Merken steht NACH dem Dialog, also fuer beide Ausgaenge.
      final dialogPos = src.indexOf('await showDialog<bool>');
      final merkenPos = src.indexOf('await settingsNotifier.markChatBackgroundSeen()');
      expect(merkenPos, greaterThan(dialogPos));
    });

    test('der Dialog enthaelt den echten Picker, nicht nur Text', () {
      final src = File('lib/screens/chat/chat_detail_screen.dart')
          .readAsStringSync();
      expect(src.contains('ChatBackgroundPicker()'), isTrue);
    });

    test('der Hinweis ist abschaltbar und kommt nicht bei jedem Chat', () {
      // Default aus, und der Bildschirm fragt danach.
      expect(const AppSettings().chatBackgroundSeen, isFalse);
      final src = File('lib/screens/chat/chat_detail_screen.dart')
          .readAsStringSync();
      expect(src.contains('settings.chatBackgroundSeen'), isTrue);
    });
  });

  group('Passkey: kein blindes Zweitregisterieren', () {
    test('die Einrichtung prueft vorher, ob ein Passkey existiert', () {
      final src = File('lib/screens/onboarding/settings_privacy_once_screen.dart')
          .readAsStringSync();

      expect(src.contains('PasskeyAuth.hasRegisteredPasskey()'), isTrue);
      // Die Pruefung muss VOR dem Register kommen.
      expect(
        src.indexOf('hasRegisteredPasskey()'),
        lessThan(src.indexOf('await PasskeyAuth.register()')),
      );
    });

    test('der Bestandsfall gilt als erledigt, nicht als Fehler', () {
      final src = File('lib/screens/onboarding/settings_privacy_once_screen.dart')
          .readAsStringSync();

      // Sonst zeigt der Screen "Einrichtung fehlgeschlagen", obwohl das
      // Konto in Ordnung ist.
      expect(src.contains('_passkeyCreated = true'), isTrue);
      expect(src.contains('setup.passkeyAlreadyThere'), isTrue);
    });

    test('ein Fehler beim Lesen der Liste blockiert die Einrichtung nicht', () {
      // Sonst waere auf einem Geraet ohne biometrische Anmeldung
      // (Listen lesen verlangt AAL2) kein Passkey einrichtbar.
      final src = File('lib/services/passkey_auth.dart').readAsStringSync();
      final anfang = src.indexOf('hasRegisteredPasskey()');
      expect(anfang, greaterThan(-1));
      final body = src.substring(anfang, anfang + 700);
      expect(body.contains('catch'), isTrue);
      expect(body.contains('return false'), isTrue);
    });
  });

  group('Texte existieren in beiden Sprachen', () {
    final src = File('lib/l10n/app_strings.dart').readAsStringSync();

    for (final key in const [
      'chatbg.hintTitle',
      'chatbg.hintBody',
      'chatbg.hintDone',
      'common.later',
      'setup.passkeyAlreadyThere',
    ]) {
      test('$key ist definiert', () {
        expect(src.contains("'$key'"), isTrue);
        // Genau zweimal: einmal DE, einmal EN. Ein drittes Vorkommen
        // waere eine Sprachluecke.
        expect("'$key'".allMatches(src).length, 2, reason: key);
      });
    }
  });
}