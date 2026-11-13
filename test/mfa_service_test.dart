// Unit-Tests fuer den MFA-Service (TOTP mit Authenticator-App).
//
// WAS HIER GEPRUEFT WIRD:
//   * der MFA-Status (AAL, verifizierte Faktoren) inklusive Fail-closed,
//   * der Start einer TOTP-Einrichtung (Aufräumen, Enroll, otpauth-URI),
//   * die Pruefung des Codes (Challenge + Verify),
//   * die Fehlerfaelle: kaputte Serverantwort, Serverfehler, Timeout.
//
// WIE DER SERVER ERSETZT WIRD:
//   Der Service spricht mit Supabase ueber HTTP. Statt eines Servers
//   laeuft ein handgeschriebener Fake ([_FakeAuthServer]), der genau die
//   Auth-Endpunkte beantwortet, die der Service braucht. So bleibt der
//   Test offline und deterministisch - und der echte Supabase-Client
//   (inklusive seiner echten Fehlerbehandlung) wird mitgetestet.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/mfa_service.dart';

/// Baut ein JWT mit einem gewuenschten Assurance-Level.
///
/// DER GRUND: Das AAL steht NICHT in der User-Zeile, sondern im
/// Access-Token (`aal`-Claim). Der Service liest es mit
/// `decodeJwtPayload` - also braucht der Test einen echten (wenn auch
/// nicht signierten) JWT, sonst kaeme `aal1` heraus.
String _jwt({String aal = 'aal1'}) {
  String teil(Map<String, dynamic> inhalt) =>
      base64Url.encode(utf8.encode(jsonEncode(inhalt))).replaceAll('=', '');
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final kopf = teil({'alg': 'HS256', 'typ': 'JWT'});
  final nutzlast = teil({
    'sub': 'nutzer-1',
    'aal': aal,
    'exp': jetzt + 3600,
    'iat': jetzt,
  });
  return '$kopf.$nutzlast.c2ln';
}

/// Ein handgeschriebener Supabase-Auth-Server fuer die Tests.
///
/// DER GRUND FUER DEN EIGENEN FAKE: Der MFA-Service nutzt den echten
/// Supabase-Client. Nur so kann der Test beweisen, dass der Service mit
/// den echten Antworten des Servers umgeht (Faktor-Liste, Enroll,
/// Challenge/Verify) - und nicht mit einer Wunschvorstellung davon.
class _FakeAuthServer {
  _FakeAuthServer();

  /// Die E-Mail-Adresse des eingeloggten Nutzers (landet im otpauth-URI).
  final String email = 'lena@thestia.de';

  /// Die Faktoren, die der Server kennt (unverified/verified).
  List<Map<String, dynamic>> faktoren = [];

  /// Das Secret, das der Server beim Enroll zurueckgibt.
  String secret = 'JBSWY3DPEHPK3PXP';

  /// Das Assurance-Level im Access-Token ('aal1' oder 'aal2').
  String aal = 'aal1';

  /// Wenn true, liefert der naechste Refresh eine kaputte Antwort
  /// (User ohne 'id'). Der Service darf daran nicht zerbrechen.
  bool refreshKaputt = false;

  /// HTTP-Status beim Token-Refresh (0 = Erfolg).
  ///
  /// WICHTIG: Ein 4xx-Fehler wird vom Supabase-Client NICHT intern
  /// wiederholt - ein 5xx wuerde bis zu einer Minute lang probieren.
  /// Deshalb wird hier der "echte" Serverfehler simuliert.
  int refreshStatus = 0;

  /// HTTP-Status beim Enroll (0 = Erfolg).
  int enrollStatus = 0;

  /// Wenn true, bricht der Enroll mit einem Netzwerkfehler ab
  /// (Timeout-Simulation).
  bool enrollTimeout = false;

  /// Wenn true, liefert das Enroll keine TOTP-Daten.
  bool enrollOhneTotp = false;

  /// Wenn true, liefert das Enroll ein leeres Secret.
  bool enrollLeeresSecret = false;

  /// HTTP-Status beim Unenroll (0 = Erfolg).
  int unenrollStatus = 0;

  /// HTTP-Status beim Verify (0 = Erfolg).
  int verifyStatus = 0;

  /// Alle Anfragen, die der Server gesehen hat (z. B. 'POST /factors').
  final List<String> anfragen = [];

  /// Die Koerper der Enroll-Aufrufe.
  final List<Map<String, dynamic>> enrollKoerper = [];

  /// Die Codes, mit denen verifiziert wurde.
  final List<String> verifizierteCodes = [];

  /// Anzahl der Token-Refreshes (der Client holt die Faktoren immer ueber
  /// einen frischen Session-Stand).
  int refreshAnzahl = 0;

  /// Baut einen Faktor-Eintrag in der Form, die der Server liefert.
  Map<String, dynamic> faktor(
    String id, {
    String status = 'verified',
    String typ = 'totp',
  }) {
    return {
      'id': id,
      'friendly_name': 'Thestia',
      'factor_type': typ,
      'status': status,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
  }

  Map<String, dynamic> _userJson() {
    return {
      'id': 'nutzer-1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'created_at': '2026-01-01T00:00:00Z',
      'factors': faktoren,
    };
  }

  Map<String, dynamic> _sessionJson() {
    return {
      'access_token': _jwt(aal: aal),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': _userJson(),
    };
  }

  http.Response _json(Object inhalt) {
    return http.Response(
      jsonEncode(inhalt),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  /// Beantwortet einen Aufruf des Supabase-Clients.
  http.Response antworte(http.Request anfrage) {
    final pfad = anfrage.url.path;
    anfragen.add('${anfrage.method} $pfad');

    // GET /auth/v1/user - das Profil des eingeloggten Nutzers.
    if (anfrage.method == 'GET' && pfad.endsWith('/auth/v1/user')) {
      return _json(_userJson());
    }

    // POST /auth/v1/token - der Refresh der Session.
    if (anfrage.method == 'POST' && pfad.endsWith('/auth/v1/token')) {
      refreshAnzahl++;
      if (refreshStatus != 0) {
        return http.Response(
          '{"msg":"invalid refresh token","code":"refresh_token_not_found"}',
          refreshStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      if (refreshKaputt) {
        refreshKaputt = false;
        // Absichtlich kaputt: der User hat keine 'id', damit der Client
        // keine Session bauen kann. Das ist der Fehlerfall, an dem der
        // Service seinen Retry zeigen muss.
        return _json({
          'access_token': _jwt(aal: aal),
          'token_type': 'bearer',
          'refresh_token': 'refresh-token',
          'user': <String, dynamic>{},
        });
      }
      return _json(_sessionJson());
    }

    // POST /auth/v1/factors - die Einrichtung starten.
    if (anfrage.method == 'POST' && pfad.endsWith('/auth/v1/factors')) {
      if (enrollTimeout) {
        // Ein Netzwerkfehler sieht fuer den Client aus wie ein Timeout.
        throw http.ClientException('Timeout beim Enroll');
      }
      if (enrollStatus != 0) {
        return http.Response('{"msg":"Serverfehler"}', enrollStatus);
      }
      enrollKoerper.add(jsonDecode(anfrage.body) as Map<String, dynamic>);
      if (enrollOhneTotp) {
        return _json({'id': 'faktor-neu', 'type': 'totp'});
      }
      return _json({
        'id': 'faktor-neu',
        'type': 'totp',
        'totp': {
          'qr_code': '<svg/>',
          'secret': enrollLeeresSecret ? '' : secret,
          'uri': 'otpauth://totp/Thestia:lena',
        },
      });
    }

    // DELETE /auth/v1/factors/{id} - einen Faktor entfernen.
    if (anfrage.method == 'DELETE' && pfad.contains('/auth/v1/factors/')) {
      if (unenrollStatus != 0) {
        return http.Response('{"msg":"Serverfehler"}', unenrollStatus);
      }
      final id = pfad.substring(pfad.lastIndexOf('/') + 1);
      faktoren.removeWhere((f) => f['id'] == id);
      return _json({'id': id});
    }

    // POST /auth/v1/factors/{id}/challenge - die Challenge fuer den Code.
    if (anfrage.method == 'POST' && pfad.endsWith('/challenge')) {
      return _json({'id': 'challenge-1', 'expires_at': 1900000000});
    }

    // POST /auth/v1/factors/{id}/verify - der Code wird geprueft.
    if (anfrage.method == 'POST' && pfad.endsWith('/verify')) {
      final koerper = jsonDecode(anfrage.body) as Map<String, dynamic>;
      verifizierteCodes.add(koerper['code'] as String);
      if (verifyStatus != 0) {
        return http.Response('{"msg":"Falscher Code"}', verifyStatus);
      }
      return _json(_sessionJson());
    }

    return http.Response('{}', 404);
  }
}

/// Baut einen eingeloggten Client gegen den Fake-Server.
///
/// DER GRUND FUER `setSession`: Der Service liest den Status aus der
/// aktuellen Session (`currentSession`/`currentUser`). Ohne Session
/// wuerde der Test nur den "nicht eingeloggt"-Zweig sehen.
Future<SupabaseClient> _eingeloggt(
  _FakeAuthServer server, {
  bool mitSession = true,
}) async {
  final client = SupabaseClient(
    'https://test.supabase.co',
    'test-key',
    httpClient: MockClient((anfrage) async => server.antworte(anfrage)),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  if (mitSession) {
    await client.auth.setSession(
      'refresh-token',
      accessToken: _jwt(aal: server.aal),
    );
  }
  return client;
}

void main() {
  group('MfaService.loadStatus', () {
    test('ohne Session: neutraler Initialzustand (keine Aussage)', () async {
      final server = _FakeAuthServer();
      final client = await _eingeloggt(server, mitSession: false);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(status.loaded, isFalse, reason: 'Ohne Session gibt es nichts');
      expect(status.currentAal, 'aal1');
      expect(status.hasVerifiedFactors, isFalse);
      expect(status.hasAnyFactor, isFalse);
      expect(status.needsChallenge, isFalse);
      expect(status.shouldPromptSetup, isFalse);
      expect(
        server.anfragen,
        isEmpty,
        reason: 'Ohne Session darf der Server gar nicht gefragt werden',
      );
    });

    test('AAL1 mit verifiziertem Faktor: Challenge wird noetig', () async {
      final server = _FakeAuthServer()..aal = 'aal1';
      server.faktoren.add(server.faktor('faktor-1'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(status.loaded, isTrue);
      expect(status.currentAal, 'aal1');
      expect(status.hasVerifiedFactors, isTrue);
      expect(status.hasAnyFactor, isTrue);
      expect(
        status.needsChallenge,
        isTrue,
        reason:
            'Ein verifizierter Faktor bei AAL1 heisst: Der Login muss noch '
            'per Code bestaetigt werden.',
      );
      expect(status.shouldPromptSetup, isFalse);
    });

    test('AAL2 mit verifiziertem Faktor: keine Challenge noetig', () async {
      final server = _FakeAuthServer()..aal = 'aal2';
      server.faktoren.add(server.faktor('faktor-1'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(status.currentAal, 'aal2');
      expect(status.hasVerifiedFactors, isTrue);
      expect(
        status.needsChallenge,
        isFalse,
        reason: 'Die Session ist bereits auf AAL2 gehoben',
      );
    });

    test('ohne Faktoren: der Einrichtungshinweis ist sinnvoll', () async {
      final server = _FakeAuthServer();
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(status.loaded, isTrue);
      expect(status.hasAnyFactor, isFalse);
      expect(status.hasVerifiedFactors, isFalse);
      expect(
        status.shouldPromptSetup,
        isTrue,
        reason: 'Ohne jeden Faktor soll der Router die 2FA einrichten',
      );
    });

    test('kaputte Serverantwort: Session wird aufgefrischt, Status neu '
        'geladen', () async {
      final server = _FakeAuthServer()..refreshKaputt = true;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(
        status.loaded,
        isTrue,
        reason:
            'Nach dem Refresh muss der Status erneut geladen werden - sonst '
            'zeigt die App faelschlich "2FA nicht eingerichtet".',
      );
      expect(
        server.refreshAnzahl,
        greaterThanOrEqualTo(2),
        reason:
            'Der erste Abruf muss gescheitert sein, damit der Retry '
            'ueberhaupt greift',
      );
    });

    test('Serverfehler: fail-closed, der Status bleibt "unbekannt"', () async {
      final server = _FakeAuthServer()..refreshStatus = 400;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final status = await MfaService(client).loadStatus();

      expect(
        status.loaded,
        isFalse,
        reason:
            'Bei einem Serverfehler gibt der Service KEINE Aussage: der '
            'Router soll weder die Einrichtung anbieten noch eine Challenge '
            'verlangen.',
      );
      expect(status.needsChallenge, isFalse);
      expect(status.shouldPromptSetup, isFalse);
    });
  });

  group('MfaService.startTotpEnroll', () {
    test(
      'ein Fehler beim Aufraeumen bricht die Einrichtung nicht ab',
      () async {
        final server = _FakeAuthServer()..refreshKaputt = true;
        final client = await _eingeloggt(server);
        addTearDown(client.dispose);

        // DER GRUND FUER DIESEN FALL: Das Aufraeumen der alten Faktoren ist
        // "best effort" - ein Fehler dabei ist kein Grund, den Nutzer ohne
        // Secret dastehen zu lassen. Die Serverantwort ist kaputt (der User
        // hat keine 'id'), der Enroll selbst laeuft normal.
        final ergebnis = await MfaService(client).startTotpEnroll();

        expect(
          ergebnis.secret,
          server.secret,
          reason:
              'Der Nutzer braucht das Secret auch dann, wenn das Aufraeumen '
              'gescheitert ist.',
        );
      },
    );

    test('raeumt unbestatigte Faktoren auf und liefert Secret + URI', () async {
      final server = _FakeAuthServer();
      // Ein verwaistes, unbestatigtes TOTP (abgebrochene Einrichtung) und
      // ein bestaetigtes Telefon-Faktor.
      server.faktoren.add(server.faktor('alt-1', status: 'unverified'));
      server.faktoren.add(server.faktor('tel-1', typ: 'phone'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      final ergebnis = await MfaService(client).startTotpEnroll();

      expect(
        server.anfragen,
        contains('DELETE /auth/v1/factors/alt-1'),
        reason:
            'Verwaiste Faktoren muessen weg, sonst lehnt Supabase neue '
            'Einrichtungen ab (Faktor-Limit).',
      );
      expect(
        server.anfragen.any(
          (a) => a.startsWith('DELETE') && a.contains('tel-1'),
        ),
        isFalse,
        reason: 'Ein verifizierter Faktor darf NICHT geloescht werden',
      );
      expect(ergebnis.secret, server.secret);
      expect(ergebnis.qrUri, contains('secret=${server.secret}'));
      expect(ergebnis.qrUri, contains('issuer=Thestia'));
      expect(
        server.enrollKoerper.single['factor_type'],
        'totp',
        reason: 'Es wird ausdruecklich nur TOTP angeboten (kein SMS)',
      );
      expect(server.enrollKoerper.single['issuer'], 'Thestia');
    });

    test('bereits verifizierter TOTP-Faktor: klare AuthException', () async {
      final server = _FakeAuthServer();
      server.faktoren.add(server.faktor('faktor-1'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).startTotpEnroll(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('bereits aktiviert'),
          ),
        ),
        reason:
            'Ein zweiter Faktor wird vom Server abgelehnt - der Nutzer muss '
            'eine verstaendliche Meldung sehen, nicht "Einrichtung konnte '
            'nicht gestartet werden".',
      );
      expect(
        server.anfragen.any(
          (a) => a.startsWith('POST') && a.endsWith('/auth/v1/factors'),
        ),
        isFalse,
        reason: 'Es darf kein zweites Enroll versucht werden',
      );
    });

    test('Enroll-Antwort ohne TOTP-Daten: StateError', () async {
      final server = _FakeAuthServer()..enrollOhneTotp = true;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).startTotpEnroll(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('keine Daten'),
          ),
        ),
      );
    });

    test('Enroll-Antwort mit leerem Secret: StateError', () async {
      final server = _FakeAuthServer()..enrollLeeresSecret = true;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).startTotpEnroll(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ohne Secret'),
          ),
        ),
      );
    });

    test('Serverfehler beim Enroll: der Fehler wird weitergegeben', () async {
      final server = _FakeAuthServer()..enrollStatus = 500;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).startTotpEnroll(),
        throwsA(isA<AuthException>()),
        reason:
            'Ein Serverfehler beim Enroll darf NICHT als Erfolg durchgehen - '
            'der Nutzer braucht eine Fehlermeldung.',
      );
    });

    test('Timeout beim Enroll: der Fehler wird weitergegeben', () async {
      final server = _FakeAuthServer()..enrollTimeout = true;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).startTotpEnroll(),
        throwsA(isA<AuthException>()),
        reason: 'Ein Netzwerkabbruch muss sichtbar fehlschlagen',
      );
    });
  });

  group('MfaService.verifyTotpEnroll', () {
    test('prueft den Code aus der Authenticator-App', () async {
      final server = _FakeAuthServer();
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await MfaService(
        client,
      ).verifyTotpEnroll(factorId: 'faktor-neu', code: '123456');

      expect(server.verifizierteCodes, [
        '123456',
      ], reason: 'Der eingegebene Code muss unveraendert beim Server landen');
      expect(
        server.anfragen.any((a) => a.endsWith('/challenge')),
        isTrue,
        reason: 'Vor dem Verify braucht es die Challenge des Servers',
      );
    });

    test('falscher Code: der Serverfehler wird weitergegeben', () async {
      final server = _FakeAuthServer()..verifyStatus = 400;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(
          client,
        ).verifyTotpEnroll(factorId: 'faktor-neu', code: '000000'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('MfaService.cancelEnroll', () {
    test('entfernt den Faktor wieder vom Server', () async {
      final server = _FakeAuthServer();
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await MfaService(client).cancelEnroll('faktor-neu');

      expect(server.anfragen, contains('DELETE /auth/v1/factors/faktor-neu'));
    });

    test('ein Fehler beim Entfernen wird geschluckt', () async {
      final server = _FakeAuthServer()..unenrollStatus = 500;
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).cancelEnroll('faktor-neu'),
        completes,
        reason:
            'Das Verwerfen einer Einrichtung ist eine Nebenhandlung - ein '
            'Fehler darf den Screen nicht zum Absturz bringen.',
      );
    });
  });

  group('MfaService.verifyChallenge', () {
    test('verifiziert den verifizierten TOTP-Faktor', () async {
      final server = _FakeAuthServer();
      server.faktoren.add(server.faktor('faktor-1'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await MfaService(client).verifyChallenge(code: '654321');

      expect(server.verifizierteCodes, ['654321']);
    });

    test('ohne verifizierten TOTP-Faktor: StateError', () async {
      final server = _FakeAuthServer();
      // Nur ein unbestatigter Faktor - es gibt nichts zu verifizieren.
      server.faktoren.add(server.faktor('faktor-1', status: 'unverified'));
      final client = await _eingeloggt(server);
      addTearDown(client.dispose);

      await expectLater(
        MfaService(client).verifyChallenge(code: '654321'),
        throwsA(isA<StateError>()),
        reason:
            'Ohne bestaetigten Faktor gibt es nichts, was bestaetigt werden '
            'koennte - das muss als Fehler auffallen, nicht als Erfolg.',
      );
    });
  });
}
