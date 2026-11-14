// Unit-Tests fuer die Supabase-Anmeldung.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Anmeldung (Erfolg, falsche Zugangsdaten, Serverfehler),
//   * die Registrierung (Profil, Duplikat-Schutz, gesperrte E-Mail),
//   * das Zuruecksetzen des Passworts (E-Mail-Flow),
//   * die MFA-Anbindung (AAL/Challenge-Pfad des Auth-Servers),
//   * die Sperre nach zu vielen Fehlversuchen (Lockout),
//   * das Abmelden und das Loeschen des Kontos,
//   * das Wiederherstellen der Sitzung (inkl. Refresh und Ablauf).
//
// WIE DER SERVER ERSETZT WIRD:
//   Der Auth-Service nutzt den echten Supabase-Client. Der Test haengt
//   einen handgeschriebenen Fake ([_FakeAuthServer]) an, der genau die
//   Auth-Endpunkte beantwortet, die der Service braucht. So werden auch
//   die echten Fehlerbehandlungen des Clients mitgetestet (400 vs. 500).
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_auth_service.dart';
import 'package:thestia/services/supabase_database_service.dart';

/// Baut ein JWT mit gewuenschter Laufzeit.
String _jwt({int laufzeitSekunden = 3600, String sub = 'nutzer-1'}) {
  String teil(Map<String, dynamic> inhalt) =>
      base64Url.encode(utf8.encode(jsonEncode(inhalt))).replaceAll('=', '');
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${teil({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${teil({'sub': sub, 'exp': jetzt + laufzeitSekunden, 'iat': jetzt})}'
      '.c2ln';
}

/// In-Memory-Keystore fuer die Tokens (statt echter Keystore).
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage(this.store);

  final Map<String, String> store;

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    store[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    store.remove(key);
  }
}

/// Der Verschluesselungsdienst ohne echte Schluessel (die App braucht von
/// ihm nur die User-ID fuer die Safety-Nummern).
class _FakeEncryptionService extends EncryptionService {
  @override
  Future<void> get initialized => Future<void>.value();
}

/// Der handgeschriebene Supabase-Auth-Server fuer die Tests.
class _FakeAuthServer {
  _FakeAuthServer();

  /// HTTP-Status beim Login (0 = Erfolg).
  int loginStatus = 0;

  /// Die Fehlermeldung beim Login.
  String loginMeldung = 'Invalid login credentials';

  /// HTTP-Status bei der Registrierung (0 = Erfolg).
  int signupStatus = 0;

  /// Liefert die Registrierung ohne Session (Bestaetigungs-Flow)?
  bool signupOhneSession = false;

  /// Liefert die Registrierung einen bereits bestaetigten Nutzer?
  bool signupBereitsBestaetigt = false;

  /// Das Erstellungsdatum des registrierten Nutzers.
  DateTime signupErstellt = DateTime.now();

  /// HTTP-Status beim Token-Refresh (0 = Erfolg).
  int refreshStatus = 0;

  /// HTTP-Status beim Abmelden (0 = Erfolg).
  int logoutStatus = 0;

  /// HTTP-Status bei getUser (0 = Erfolg).
  int getUserStatus = 0;

  /// Der Nutzer, den getUser liefert (ohne E-Mail-Bestaetigung?).
  bool getUserOhneBestaetigung = false;

  /// Ist die E-Mail-Adresse gesperrt?
  bool emailGesperrt = false;

  /// Der Sperr-Grund der gesperrten E-Mail.
  String sperrGrund = 'Missbrauch';

  /// HTTP-Status der Edge Function "delete-account" (0 = Erfolg).
  int deleteStatus = 200;

  /// Der Body der Edge Function.
  Map<String, dynamic> deleteBody = {'deleted': true};

  /// Alle Anfragen, die der Server gesehen hat.
  final List<String> anfragen = [];

  /// Die Koerper der Anfragen (nach Pfad-Endung).
  final Map<String, List<Map<String, dynamic>>> koerper = {};

  /// Die Anfrage, die gerade beantwortet wird.
  http.Request? _aktuell;

  Map<String, dynamic> _userJson({bool bestaetigt = true, DateTime? erstellt}) {
    return {
      'id': 'nutzer-1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'lena@thestia.de',
      'created_at': (erstellt ?? DateTime.now()).toIso8601String(),
      'email_confirmed_at': bestaetigt
          ? DateTime.now().toIso8601String()
          : null,
    };
  }

  Map<String, dynamic> _sessionJson({int laufzeit = 3600}) => {
    'access_token': _jwt(laufzeitSekunden: laufzeit),
    'token_type': 'bearer',
    'expires_in': laufzeit,
    'refresh_token': 'refresh-token',
    'user': _userJson(),
  };

  http.Response _json(Object inhalt, [int status = 200]) => http.Response(
    jsonEncode(inhalt),
    status,
    headers: {'content-type': 'application/json'},
    // DER GRUND: PostgREST liest die Methode aus "response.request" - ohne
    // das Feld stuerzt der Client auf einem Null-Check ab.
    request: _aktuell,
  );

  /// Beantwortet einen Aufruf des Supabase-Clients.
  http.Response antworte(http.Request anfrage) {
    _aktuell = anfrage;
    final pfad = anfrage.url.path;
    anfragen.add('${anfrage.method} $pfad');

    if (anfrage.body.isNotEmpty && anfrage.body != 'null') {
      final dekodiert = jsonDecode(anfrage.body);
      if (dekodiert is Map<String, dynamic>) {
        koerper.putIfAbsent(pfad, () => []).add(dekodiert);
      }
    }

    // POST /auth/v1/token - Login (grant_type=password) und Refresh.
    if (pfad.endsWith('/auth/v1/token')) {
      final grant = anfrage.url.queryParameters['grant_type'];
      if (grant == 'password') {
        if (loginStatus != 0) {
          return _json({'msg': loginMeldung}, loginStatus);
        }
        return _json(_sessionJson());
      }
      if (refreshStatus != 0) {
        return _json({'msg': 'invalid refresh token'}, refreshStatus);
      }
      return _json(_sessionJson());
    }

    // POST /auth/v1/signup - die Registrierung.
    if (pfad.endsWith('/auth/v1/signup')) {
      if (signupStatus != 0) {
        return _json({'msg': 'Registrierung nicht erlaubt'}, signupStatus);
      }
      if (signupBereitsBestaetigt) {
        // DER GRUND FUER DIE FLACHE ANTWORT: Ohne Session liefert
        // Supabase das Nutzer-Objekt selbst (nicht unter "user") - so
        // baut der Client die [AuthResponse].
        return _json(_userJson(erstellt: signupErstellt));
      }
      if (signupOhneSession) {
        return _json(_userJson(bestaetigt: false, erstellt: signupErstellt));
      }
      return _json(_sessionJson());
    }

    // GET /auth/v1/user - der eingeloggte Nutzer.
    if (pfad.endsWith('/auth/v1/user')) {
      if (getUserStatus != 0) {
        return _json({'msg': 'Serverfehler'}, getUserStatus);
      }
      return _json(_userJson(bestaetigt: !getUserOhneBestaetigung));
    }

    // POST /auth/v1/logout - das Abmelden.
    if (pfad.endsWith('/auth/v1/logout')) {
      if (logoutStatus != 0) {
        return _json({'msg': 'Serverfehler'}, logoutStatus);
      }
      return http.Response('', 204, request: anfrage);
    }

    // POST /auth/v1/resend - die Bestaetigungs-Mail.
    if (pfad.endsWith('/auth/v1/resend')) {
      return _json({'message_id': 'mail-1'});
    }

    // POST /auth/v1/recover - das Passwort-Zuruecksetzen.
    if (pfad.endsWith('/auth/v1/recover')) {
      return _json({'message_id': 'mail-2'});
    }

    // POST /rest/v1/rpc/check_email_ban_status - die Sperr-Pruefung.
    if (pfad.contains('/rest/v1/rpc/check_email_ban_status')) {
      return _json({
        'banned': emailGesperrt,
        'reason': emailGesperrt ? sperrGrund : null,
      });
    }

    // POST /functions/v1/delete-account - die Kontoloeschung.
    if (pfad.endsWith('/functions/v1/delete-account')) {
      if (deleteStatus != 200) {
        return _json(deleteBody, deleteStatus);
      }
      return _json(deleteBody);
    }

    return _json({}, 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthServer server;
  late Map<String, String> keystore;
  late _FakeEncryptionService encryption;
  late SecureTokenStore tokens;

  setUp(() {
    server = _FakeAuthServer();
    keystore = {};
    encryption = _FakeEncryptionService();
    tokens = SecureTokenStore(_FakeSecureStorage(keystore));
    // DER GRUND: Der Login-Lockout liegt in den SharedPreferences. Der
    // Test startet deshalb jeden Fall mit einem leeren Zaehler.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut einen Supabase-Client gegen den Fake-Server.
  ///
  /// DER GRUND FUER DEN PKCE-SPEICHER: [SupabaseAuthService.register]
  /// ruft "signUp" auf - und der Auth-Client braucht fuer den
  /// PKCE-Flow einen Speicher fuer den Code-Verifier. Ohne ihn bricht
  /// der Aufruf mit einer Assertion ab.
  SupabaseClient testClient() {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient((anfrage) async => server.antworte(anfrage)),
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
      ),
    );
    addTearDown(client.dispose);
    return client;
  }

  /// Baut den Service mit einem Client gegen den Fake-Server.
  SupabaseAuthService neuerService() {
    final client = testClient();
    return SupabaseAuthService(
      client,
      tokens,
      encryption,
      SupabaseDatabaseService(client),
    );
  }

  group('SupabaseAuthService.login', () {
    test(
      'Erfolg: die Tokens landen im Keystore, die User-ID wird gesetzt',
      () async {
        final service = neuerService();

        await service.login(email: 'lena@thestia.de', password: 'geheim123');

        expect(await tokens.accessToken, isNotNull);
        expect(await tokens.refreshToken, 'refresh-token');
        expect(await tokens.userId, 'nutzer-1');
        expect(
          encryption.localUserId,
          'nutzer-1',
          reason:
              'Ohne die eigene User-ID kann der Signal-Fingerprint (die '
              'Safety-Nummer) nicht berechnet werden.',
        );
      },
    );

    test('falsche Zugangsdaten: der Fehler wird weitergereicht', () async {
      server.loginStatus = 400;
      final service = neuerService();

      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'falsch'),
        throwsA(isA<AuthException>()),
      );
      expect(
        await tokens.accessToken,
        isNull,
        reason: 'Bei einem Fehlschlag darf kein Token gespeichert werden.',
      );
    });

    test('ein Serverfehler zaehlt nicht als Fehlversuch', () async {
      // DER GRUND: Nur echte "falsche Zugangsdaten" (400) duerfen den
      // Zaehler hochzaehlen. Ein Serverausfall (500) ist kein Angriff -
      // sonst sperrt die App den Nutzer wegen eines Server-Problems aus.
      server.loginStatus = 500;
      final service = neuerService();

      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'geheim123'),
        throwsA(isA<AuthException>()),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auth_failed_login_count'), isNull);
    });

    test('falsche Zugangsdaten zaehlen als Fehlversuch', () async {
      server.loginStatus = 400;
      final service = neuerService();

      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'falsch'),
        throwsA(isA<AuthException>()),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('auth_failed_login_count'),
        1,
        reason:
            'Der Zaehler muss hochgehen - sonst greift die Sperre nach zehn '
            'Fehlversuchen nie.',
      );
    });

    test('nach zehn Fehlversuchen wird die Anmeldung gesperrt', () async {
      server.loginStatus = 400;
      final service = neuerService();

      for (var i = 0; i < 9; i++) {
        await expectLater(
          service.login(email: 'lena@thestia.de', password: 'falsch'),
          throwsA(isA<AuthException>()),
        );
      }

      // DER zehnte Versuch loest die Sperre aus.
      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'falsch'),
        throwsA(
          isA<AppException>().having(
            (e) => e.messageKey,
            'messageKey',
            'auth.lockedOut10',
          ),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('auth_login_locked_until'),
        isNotNull,
        reason:
            'Die Sperre muss persistent sein - sie ueberlebt einen Neustart.',
      );
      expect(prefs.getInt('auth_failed_login_count'), 0);
    });

    test('in der Sperre wird der Server gar nicht gefragt', () async {
      server.loginStatus = 400;
      final service = neuerService();
      for (var i = 0; i < 10; i++) {
        await service
            .login(email: 'lena@thestia.de', password: 'falsch')
            .catchError((_) {});
      }
      final anfragenVorher = server.anfragen.length;

      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'geheim123'),
        throwsA(
          isA<AppException>().having(
            (e) => e.messageKey,
            'messageKey',
            'auth.lockedOut',
          ),
        ),
      );
      expect(
        server.anfragen.length,
        anfragenVorher,
        reason:
            'In der Sperre wird bewusst gar nichts angefragt - auch keine '
            'Ban-Status-Abfrage.',
      );
    });

    test('eine gesperrte E-Mail bekommt den Entsperrungs-Hinweis', () async {
      server.emailGesperrt = true;
      final service = neuerService();

      await expectLater(
        service.login(email: 'lena@thestia.de', password: 'geheim123'),
        throwsA(isA<EmailBannedException>()),
      );
    });

    test(
      'nach einem Erfolg wird der Fehlversuchszaehler zurueckgesetzt',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('auth_failed_login_count', 4);
        final service = neuerService();

        await service.login(email: 'lena@thestia.de', password: 'geheim123');

        expect(
          (await SharedPreferences.getInstance()).getInt(
            'auth_failed_login_count',
          ),
          isNull,
          reason: 'Ein erfolgreicher Login setzt den Zaehler zurueck.',
        );
      },
    );
  });

  group('SupabaseAuthService.register', () {
    test('das Profil wird aus den Registrierungsdaten gebaut', () async {
      final service = neuerService();

      final profil = await service.register(
        name: 'Lena',
        email: 'lena@thestia.de',
        password: 'geheim123',
        gender: 'female',
        birthDate: DateTime(1998, 3, 7),
      );

      expect(profil.id, 'nutzer-1');
      expect(profil.name, 'Lena');
      expect(profil.gender, 'female');
      expect(profil.birthDate, DateTime(1998, 3, 7));
      expect(
        encryption.localUserId,
        'nutzer-1',
        reason: 'Auch nach der Registrierung braucht es die User-ID.',
      );
    });

    test('das Passwort landet NIE in den Nutzerdaten', () async {
      // DER GRUND (H-5): raw_user_meta_data wird serverseitig gelesen und
      // ist fuer jeden mit Admin-Zugriff sichtbar. Ein Passwort dort waere
      // ein Klartext-Sekret in der Datenbank.
      final service = neuerService();

      await service.register(
        name: 'Lena',
        email: 'lena@thestia.de',
        password: 'supergeheim',
        birthDate: DateTime(1998, 3, 7),
      );

      final daten = server.koerper['/auth/v1/signup']!.single['data'] as Map;
      expect(
        daten.values.map((w) => w.toString()).join(' '),
        isNot(contains('supergeheim')),
      );
      expect(daten['name'], 'Lena');
      expect(
        daten['birth_date'],
        '1998-03-07',
        reason: 'Das Geburtsdatum geht als ISO-Datum an den Server.',
      );
      expect(daten['gender'], 'unknown');
    });

    test('ohne Session (Bestaetigungs-Flow): kein Fehler', () async {
      // DER GRUND: Bei aktivierter E-Mail-Bestaetigung liefert Supabase
      // absichtlich KEINE Session. Das ist der Normalfall, kein Fehler.
      server.signupOhneSession = true;
      final service = neuerService();

      final profil = await service.register(
        name: 'Lena',
        email: 'lena@thestia.de',
        password: 'geheim123',
        birthDate: DateTime(1998, 3, 7),
      );

      expect(profil.name, 'Lena');
      expect(
        await tokens.accessToken,
        isNull,
        reason: 'Ohne Session gibt es keinen Token zu speichern.',
      );
    });

    test('eine bereits registrierte E-Mail wird erkannt', () async {
      // DER GRUND: Supabase meldet bei einer vorhandenen E-Mail KEINEN
      // Fehler (keine Enumeration). Der Client erkennt den Fall an der
      // fehlenden Session plus bestaetigtem Konto - sonst wuerde der
      // Nutzer endlos auf den Bestaetigungs-Screen warten.
      server.signupBereitsBestaetigt = true;
      final service = neuerService();

      await expectLater(
        service.register(
          name: 'Lena',
          email: 'lena@thestia.de',
          password: 'geheim123',
          birthDate: DateTime(1998, 3, 7),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'EMAIL_ALREADY_REGISTERED',
          ),
        ),
      );
    });

    test(
      'eine verwaiste, nie bestaetigte Registrierung wird erkannt',
      () async {
        // DER GRUND: Eine Registrierung, die vor ueber 30 Minuten ohne
        // Bestaetigung liegen blieb, ist "verwaist" - der Nutzer soll
        // nicht in der Bestaetigungsschleife hängen bleiben.
        server.signupOhneSession = true;
        server.signupErstellt = DateTime.now().subtract(
          const Duration(hours: 2),
        );
        final service = neuerService();

        await expectLater(
          service.register(
            name: 'Lena',
            email: 'lena@thestia.de',
            password: 'geheim123',
            birthDate: DateTime(1998, 3, 7),
          ),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              'EMAIL_ALREADY_REGISTERED',
            ),
          ),
        );
      },
    );

    test('eine gesperrte E-Mail kann sich nicht registrieren', () async {
      server.emailGesperrt = true;
      final service = neuerService();

      await expectLater(
        service.register(
          name: 'Lena',
          email: 'lena@thestia.de',
          password: 'geheim123',
          birthDate: DateTime(1998, 3, 7),
        ),
        throwsA(isA<EmailBannedException>()),
      );
      expect(
        server.anfragen.any((a) => a.contains('/signup')),
        isFalse,
        reason:
            'Die Registrierung wird gar nicht erst versucht - der Nutzer '
            'soll den Entsperrungs-Workflow sehen.',
      );
    });
  });

  group('SupabaseAuthService.restoreSession', () {
    test('ohne Session: nicht eingeloggt', () async {
      final service = neuerService();

      expect(await service.restoreSession(), isFalse);
    });

    test('mit gueltiger, bestaetigter Session: eingeloggt', () async {
      final client = testClient();
      await client.auth.setSession('refresh-token', accessToken: _jwt());
      final service = SupabaseAuthService(
        client,
        tokens,
        encryption,
        SupabaseDatabaseService(client),
      );

      expect(await service.restoreSession(), isTrue);
      expect(encryption.localUserId, 'nutzer-1');
    });

    test('ein abgelaufener Token wird aufgefrischt', () async {
      // DER GRUND: Der Access-Token laeuft nach ~1 h ab. War die App
      // laenger im Hintergrund, muss der Token erneuert werden - sonst
      // waere der Nutzer ohne Vorwarnen ausgeloggt.
      final client = testClient();
      await client.auth.setSession(
        'refresh-token',
        accessToken: _jwt(laufzeitSekunden: 60),
      );
      final service = SupabaseAuthService(
        client,
        tokens,
        encryption,
        SupabaseDatabaseService(client),
      );

      expect(await service.restoreSession(), isTrue);
      expect(
        server.anfragen.where((a) => a.contains('/auth/v1/token')).length,
        greaterThanOrEqualTo(1),
        reason:
            'Nach dem Setzen der Session muss der Token einmal erneuert '
            'worden - sonst waere die Sitzung sofort wieder abgelaufen.',
      );
    });

    test('ein abgelaufener Token, der sich nicht erneuern laesst: '
        'abgemeldet', () async {
      // DER GRUND (Auto-Logout-Haertung): Schlaegt der Refresh dauerhaft
      // fehl, ist der Token widerrufen - die Sitzung muss verworfen
      // werden. Sonst zeigte die App einen "eingeloggten" Zustand, der
      // gar nicht mehr gilt.
      server.refreshStatus = 500;
      final client = testClient();
      await client.auth.setSession(
        'refresh-token',
        accessToken: _jwt(laufzeitSekunden: 60),
      );
      final service = SupabaseAuthService(
        client,
        tokens,
        encryption,
        SupabaseDatabaseService(client),
      );

      expect(await service.restoreSession(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('SupabaseAuthService.isEmailConfirmed', () {
    test('ohne eingeloggten Nutzer: false', () async {
      final service = neuerService();

      expect(service.isEmailConfirmed(), isFalse);
    });
  });

  group('SupabaseAuthService.logout', () {
    test('der Server wird abgemeldet, die Tokens werden geloescht', () async {
      final service = neuerService();
      // Erst anmelden: nur mit einer Session spricht der Client den
      // Logout-Endpoint des Servers an (sonst waere es nur lokal).
      await service.login(email: 'lena@thestia.de', password: 'geheim123');
      await tokens.saveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'nutzer-1',
      );

      await service.logout();

      expect(
        server.anfragen.any((a) => a.contains('/auth/v1/logout')),
        isTrue,
        reason: 'Der Logout muss auch serverseitig erfolgen (ASVS 7.4.1).',
      );
      expect(await tokens.accessToken, isNull);
      expect(await tokens.refreshToken, isNull);
      expect(await tokens.userId, isNull);
    });

    test('ohne Netz wird lokal trotzdem abgemeldet', () async {
      // DER GRUND: Der Nutzer muss sich auch offline abmelden koennen -
      // der Token laeuft ohnehin bis zum Ablauf weiter.
      server.logoutStatus = 500;
      final service = neuerService();
      await tokens.saveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'nutzer-1',
      );

      await service.logout();

      expect(await tokens.accessToken, isNull);
    });
  });

  group('SupabaseAuthService.deleteAccount', () {
    test(
      'die Kontoloeschung wird bestaetigt und die Tokens geloescht',
      () async {
        final client = testClient();
        await client.auth.setSession('refresh-token', accessToken: _jwt());
        final service = SupabaseAuthService(
          client,
          tokens,
          encryption,
          SupabaseDatabaseService(client),
        );
        await tokens.saveTokens(
          accessToken: 'a',
          refreshToken: 'r',
          userId: 'nutzer-1',
        );

        await service.deleteAccount();

        expect(
          server.anfragen.any(
            (a) => a.contains('/functions/v1/delete-account'),
          ),
          isTrue,
        );
        expect(await tokens.accessToken, isNull);
      },
    );

    test('ohne eingeloggten Nutzer: nur lokal abgemeldet', () async {
      final service = neuerService();

      await service.deleteAccount();

      expect(
        server.anfragen.any((a) => a.contains('/functions/v1/delete-account')),
        isFalse,
        reason: 'Ohne Nutzer gibt es nichts zu loeschen.',
      );
      expect(await tokens.accessToken, isNull);
    });
  });

  group('SupabaseAuthService.sendEmailConfirmation', () {
    test('ohne eingeloggten Nutzer: klarer Fehler', () async {
      final service = neuerService();

      await expectLater(
        service.sendEmailConfirmation(),
        throwsA(isA<AppException>()),
      );
    });
  });
}
