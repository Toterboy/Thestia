// Der eigene Passkey-Authenticator.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/auth/thestia_passkey_authenticator.dart 0 % Abdeckung.
//
// WARUM DIESE DATEI EIGENS EXISTIERT (siehe den Kommentar dort): Der
// eigene Authenticator ruft VOR der Zeremonie NICHT
// `cancelCurrentAuthenticatorOperation()` auf. Das vorzeitige Abbrechen
// wuerde auf manchen Geraeten die FOLGENDE eigene Anfrage mitabwuergen
// ("Anfrage abgebrochen von Thestia") - der Nutzer haette nichts abgebrochen,
// und trotzdem schlug die Registrierung fehl.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Registrierung und die Anmeldung gehen an die Plattform und
//     kommen unveraendert zurueck,
//   * die Signale (unbekannter Passkey / akzeptierte Passkeys) werden
//     weitergereicht,
//   * die Diagnose liest Typ und URSPRUNG aus der clientDataJSON - der
//     Ursprung muss in GOTRUE_WEBAUTHN_RP_ORIGINS stehen, sonst lehnt der
//     Server die Registrierung ab,
//   * eine kaputte clientDataJSON bringt nichts zum Absturz.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_platform_interface/types/types.dart';

import 'package:thestia/services/auth/thestia_passkey_authenticator.dart';

/// Die Plattform als Ersatz: sie zaehlt die Aufrufe und liefert die
/// Antworten, die der Test vorgibt.
class _Plattform extends PasskeysPlatform {
  /// Die Antwort auf eine Registrierung.
  RegisterResponseType? registrierungsAntwort;

  /// Die Antwort auf eine Anmeldung.
  AuthenticateResponseType? anmeldeAntwort;

  /// Wie oft wurde registriert?
  int registrierungen = 0;

  /// Wie oft wurde angemeldet?
  int anmeldungen = 0;

  /// Wie oft kam das Signal "unbekannter Passkey"?
  int unbekannteSignale = 0;

  /// Wie oft kam das Signal "akzeptierte Passkeys"?
  int akzeptierteSignale = 0;

  /// Der zuletzt gesehene Registrierungs-Wunsch.
  RegisterRequestType? letzteAnfrage;

  @override
  Future<RegisterResponseType> register(RegisterRequestType request) async {
    registrierungen++;
    letzteAnfrage = request;
    return registrierungsAntwort!;
  }

  @override
  Future<AuthenticateResponseType> authenticate(
    AuthenticateRequestType request,
  ) async {
    anmeldungen++;
    return anmeldeAntwort!;
  }

  @override
  Future<void> cancelCurrentAuthenticatorOperation() async {}

  @override
  Future<AvailabilityType> getAvailability() async => AvailabilityTypeAndroid(
    hasPasskeySupport: true,
    isNative: true,
    isUserVerifyingPlatformAuthenticatorAvailable: true,
  );

  @override
  Future<void> signalUnknownCredential(
    SignalUnknownCredentialRequestType request,
  ) async {
    unbekannteSignale++;
  }

  @override
  Future<void> signalAllAcceptedCredentials(
    SignalAllAcceptedCredentialsRequestType request,
  ) async {
    akzeptierteSignale++;
  }
}

/// Die clientDataJSON einer Registrierung (base64url).
String _clientData({
  String typ = 'webauthn.create',
  String ursprung = 'https://auth.thestia.de',
}) => base64Url.encode(
  utf8.encode('{"type":"$typ","origin":"$ursprung","challenge":"abc"}'),
);

/// Eine Registrierungs-Anfrage fuer den Test.
RegisterRequestType _anfrage() => RegisterRequestType(
  challenge: 'Y2hhbGxlbmdl',
  relyingParty: RelyingPartyType(name: 'Thestia', id: 'auth.thestia.de'),
  user: const UserType(
    displayName: 'Lena',
    name: 'lena@example.com',
    id: 'dXNlci1pZA',
  ),
  excludeCredentials: const [],
);

/// Eine Anmelde-Anfrage fuer den Test.
AuthenticateRequestType _anmeldeAnfrage() => const AuthenticateRequestType(
  relyingPartyId: 'auth.thestia.de',
  challenge: 'Y2hhbGxlbmdl',
  mediation: MediationType.Optional,
  preferImmediatelyAvailableCredentials: true,
);

void main() {
  late _Plattform plattform;
  late ThestiaPasskeyAuthenticator auth;
  late PasskeysPlatform urspruenglich;

  setUpAll(() {
    // DER STANDARD: Die Attrappe wird nach dem Test zurueckgesetzt -
    // sonst erbt der naechste Test sie.
    urspruenglich = PasskeysPlatform.instance;
  });

  setUp(() {
    plattform = _Plattform();
    PasskeysPlatform.instance = plattform;
    auth = ThestiaPasskeyAuthenticator();
  });

  tearDown(() {
    // Der Standard zuruecksetzen - sonst erbt der naechste Test die
    // Attrappe.
    PasskeysPlatform.instance = urspruenglich;
  });

  group('Der eigene Passkey-Authenticator', () {
    test('die Registrierung geht an die Plattform', () async {
      plattform.registrierungsAntwort = RegisterResponseType(
        id: 'cred-1',
        rawId: 'cred-1',
        clientDataJSON: _clientData(),
        attestationObject: 'attestation',
        transports: const ['internal'],
      );

      final antwort = await auth.register(_anfrage());

      expect(plattform.registrierungen, 1);
      expect(
        antwort.id,
        'cred-1',
        reason:
            'Die Antwort der Plattform muss unveraendert zurueckkommen - '
            'der Server prueft sie gegen die Challenge.',
      );
    });

    test('die Anmeldung geht an die Plattform', () async {
      plattform.anmeldeAntwort = AuthenticateResponseType(
        id: 'cred-1',
        rawId: 'cred-1',
        clientDataJSON: _clientData(typ: 'webauthn.get'),
        authenticatorData: 'authenticator',
        signature: 'signatur',
        userHandle: 'nutzer',
      );

      final antwort = await auth.authenticate(_anmeldeAnfrage());

      expect(plattform.anmeldungen, 1);
      expect(antwort.signature, 'signatur');
    });

    test('das Signal "unbekannter Passkey" wird weitergereicht', () async {
      await auth.signalUnknownCredential(
        const SignalUnknownCredentialRequestType(
          relyingPartyId: 'auth.thestia.de',
          credentialId: 'cred-1',
        ),
      );

      expect(plattform.unbekannteSignale, 1);
    });

    test('das Signal "akzeptierte Passkeys" wird weitergereicht', () async {
      await auth.signalAllAcceptedCredentials(
        const SignalAllAcceptedCredentialsRequestType(
          relyingPartyId: 'auth.thestia.de',
          userId: 'nutzer',
          allAcceptedCredentialIds: ['cred-1', 'cred-2'],
        ),
      );

      expect(plattform.akzeptierteSignale, 1);
    });

    test('die Diagnose nennt den Ursprung der Zeremonie', () async {
      // DIE AUSGABE SAMMELN: `debugPrint` ist global austauschbar - so
      // sieht der Test die Diagnose, ohne den Logcat zu brauchen.
      final alteAusgabe = debugPrint;
      final ausgaben = <String>[];
      debugPrint = (String? nachricht, {int? wrapWidth}) {
        ausgaben.add(nachricht ?? '');
      };
      addTearDown(() => debugPrint = alteAusgabe);

      plattform.registrierungsAntwort = RegisterResponseType(
        id: 'cred-1',
        rawId: 'cred-1',
        clientDataJSON: _clientData(ursprung: 'https://auth.thestia.de'),
        attestationObject: 'attestation',
        transports: const [],
      );

      await auth.register(_anfrage());

      expect(
        ausgaben.any((a) => a.contains('origin=https://auth.thestia.de')),
        isTrue,
        reason:
            'Der Ursprung muss im Log stehen - er muss in '
            'GOTRUE_WEBAUTHN_RP_ORIGINS stehen, sonst lehnt der Server die '
            'Registrierung ab ("credential verification failed").',
      );
      expect(ausgaben.any((a) => a.contains('type=webauthn.create')), isTrue);
    });

    test('eine kaputte clientDataJSON bringt nichts zum Absturz', () async {
      // DER GRUND: Die Diagnose ist nur ein Log. Sie darf die Zeremonie
      // niemals umwerfen - sonst waere ein harmloser Logfehler ein
      // Anmeldefehler.
      plattform.registrierungsAntwort = const RegisterResponseType(
        id: 'cred-1',
        rawId: 'cred-1',
        clientDataJSON: 'kein-base64-xxx',
        attestationObject: 'attestation',
        transports: [],
      );

      final antwort = await auth.register(_anfrage());

      expect(antwort.id, 'cred-1');
    });
  });
}
