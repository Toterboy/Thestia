// Die Fehler-Übersetzung der Passkey-Zeremonie.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/services/auth/passkey_auth.dart 78 offene Zeilen. Das meiste davon
// steckt in der Übersetzung der Fehler: der Nutzer sieht nur eine
// Meldung, und die muss ihm SAGEN, was er tun kann.
//
// WARUM DAS WICHTIG IST: Die Meldung "Passkey-Einrichtung fehlgeschlagen"
// sagt nichts aus. Ob der Sperrbildschirm fehlt, die Domain-Verknüpfung
// nicht stimmt, die Play Services alt sind oder der Server die Anfrage
// ablehnt - für den Nutzer sieht alles gleich aus. Genau deshalb hat
// die App eine eigene Übersetzung mit einer Liste von Schlüsseln
// (messageKey), die die Oberfläche zweisprachig auflöst.
//
// WAS HIER GEPRÜFT WIRD: jeder bekannte Fehler landet in seiner eigenen
// Meldung (und nicht in der generischen), die generische Meldung
// bekommt nur, was wirklich unbekannt ist, der Server-Grund wird
// durchgereicht, und der Sicherheitscheck wird erkannt.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/auth/auth_exception.dart';
import 'package:thestia/services/auth/passkey_auth.dart';

void main() {
  /// Übersetzt einen Fehler und gibt den Schlüssel zurück.
  String keyOf(Object fehler, {required bool login}) =>
      PasskeyAuth.explainError(fehler, login: login).messageKey ?? '';

  group('Der Nutzer hat abgebrochen', () {
    test('ein Abbruch des Geraets', () {
      expect(keyOf('cancelled', login: true), 'passkey.err.cancelledLogin');
      expect(keyOf('cancelled', login: false), 'passkey.err.cancelledRegister');
    });

    test('eine Abbruch-Ausnahme', () {
      expect(
        keyOf('PlatformException: CancellationException', login: true),
        'passkey.err.cancelledLogin',
      );
    });
  });

  group('Der Nutzer kann es nicht wissen', () {
    test('NotAllowedError: kein Sperrbildschirm oder Timeout', () {
      expect(
        keyOf('android-unhandled: NotAllowedError', login: true),
        'passkey.err.notAllowedLogin',
      );
      expect(
        keyOf('android-unhandled: NotAllowedError', login: false),
        'passkey.err.notAllowedRegister',
      );
    });

    test('InvalidStateError: auf diesem Geraet gibt es den Passkey schon', () {
      expect(
        keyOf('InvalidStateError', login: true),
        'passkey.err.invalidState',
      );
    });

    test('SecurityError: die Domain-Verknuepfung passt nicht', () {
      expect(keyOf('SecurityError', login: true), 'passkey.err.securityError');
    });

    test('das Google-Konto fehlt (kein Speichern moeglich)', () {
      expect(
        keyOf('android-sync-account-not-available', login: true),
        'passkey.err.syncAccount',
      );
    });

    test('eine Zeitueberschreitung', () {
      expect(keyOf('android-timeout', login: true), 'passkey.err.timeoutLogin');
      expect(
        keyOf('android-timeout', login: false),
        'passkey.err.timeoutRegister',
      );
    });

    test('kein Passkey vorhanden', () {
      expect(
        keyOf('no_credential', login: true),
        'passkey.err.noCredentialLogin',
      );
      expect(
        keyOf('NoCredentialException', login: false),
        'passkey.err.noCredentialRegister',
      );
    });
  });

  group('Der Server', () {
    test('der Sicherheitscheck fehlte', () {
      expect(
        keyOf('AuthApiException: captcha_verification_failed', login: true),
        'passkey.err.captcha',
        reason:
            'Der Sicherheitscheck muss erkannt werden - sonst fragt die '
            'App nie nach ihm.',
      );
    });

    test('die Verifikation des Passkeys scheiterte', () {
      expect(
        keyOf('credential verification failed', login: true),
        'passkey.err.verificationFailed',
      );
    });

    test('die Server-Konfiguration passt nicht (RP-ID)', () {
      expect(
        keyOf('invalid relying party id', login: true),
        'passkey.err.rpIdMismatch',
      );
      expect(keyOf('wrong hostname', login: true), 'passkey.err.rpIdMismatch');
    });

    test('der Server hat die Anfrage abgelehnt', () {
      expect(
        keyOf('AuthApiException: aal2 required', login: true),
        'passkey.err.serverRejected',
      );
      expect(keyOf('status: 400', login: true), 'passkey.err.serverRejected');
      expect(
        keyOf('webauthn error', login: true),
        'passkey.err.serverRejected',
      );
    });

    test('der Server-Grund wird durchgereicht', () {
      final fehler = PasskeyAuth.explainError(
        'AuthApiException: message: aal2 required',
        login: true,
      );

      expect(fehler.params['reason'], contains('aal2 required'));
      expect(
        fehler.params['reason'],
        contains('Server'),
        reason:
            'Der Grund muss lesbar bleiben - er hilft dem Team bei der '
            'Ursachensuche.',
      );
    });

    test('der HTTP-Status wird durchgereicht', () {
      final fehler = PasskeyAuth.explainError(
        'AuthApiException: status: 404',
        login: true,
      );

      expect(fehler.params['reason'], contains('404'));
    });
  });

  group('Die Verknuepfung mit der Seite', () {
    test('Digital Asset Links', () {
      expect(
        keyOf('Unable to verify package. AssetLinkError', login: true),
        'passkey.err.assetLinks',
      );
      expect(
        keyOf('GetCredentialProviderConfigurationException', login: true),
        'passkey.err.assetLinks',
      );
    });

    test('das Plugin fehlt (Fehler im Build)', () {
      expect(
        keyOf('MissingPluginException(No implementation found)', login: true),
        'passkey.err.pluginMissing',
      );
    });
  });

  group('Der unbekannte Fehler', () {
    test('er landet in der generischen Meldung', () {
      expect(
        keyOf('Etwas ganz anderes', login: true),
        'passkey.err.unknownLogin',
      );
      expect(
        keyOf('Etwas ganz anderes', login: false),
        'passkey.err.unknownRegister',
      );
    });

    test('der Roh-Fehler landet nicht in der Meldung', () {
      final fehler = PasskeyAuth.explainError(
        'Geheimnis mit Passwort 1234',
        login: true,
      );

      expect(
        fehler.message.contains('1234'),
        isFalse,
        reason:
            'Die Meldung darf keine Roh-Daten durchreichen - der Roh-Fehler '
            'gehoert ins Log, nicht auf den Bildschirm.',
      );
    });
  });

  group('Die Hilfen fuer die Oberflaeche', () {
    test('der Sicherheitscheck wird erkannt', () {
      final captcha = PasskeyAuth.explainError(
        'AuthApiException: captcha_verification_failed',
        login: true,
      );

      expect(PasskeyAuth.requiresCaptcha(captcha), isTrue);
      expect(PasskeyAuth.requiresCaptcha('irgendwas'), isFalse);
    });

    test('eine eigene AppException bleibt unveraendert', () {
      final eigen = AppException(
        'Meine eigene Meldung',
        messageKey: 'mein.key',
      );

      expect(
        PasskeyAuth.explainForUi(eigen, login: true).message,
        'Meine eigene Meldung',
      );
      expect(
        PasskeyAuth.explainForUi(eigen, login: true).messageKey,
        'mein.key',
      );
    });

    test('ein fremder Fehler wird uebersetzt', () {
      final uebersetzt = PasskeyAuth.explainForUi(
        'NotAllowedError',
        login: true,
      );

      expect(uebersetzt.messageKey, 'passkey.err.notAllowedLogin');
    });
  });
}
