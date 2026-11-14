// Unit-Tests fuer die Geraete-Verwaltung ("Wo bin ich eingeloggt?").
//
// WAS HIER GEPRUEFT WIRD:
//   * die stabile Geraete-ID (lazy erzeugt, einmal gespeichert),
//   * der lesbare Geraetename,
//   * das Modell [DeviceSession] (Label, "aktuelles Geraet", Zeitstempel),
//   * die Registrierung des Geraets beim Server,
//   * die Liste der angemeldeten Geraete,
//   * das "ueberall abmelden" und das Deregistrieren.
//
// WIE DER SERVER ERSETZT WIRD:
//   Der Service spricht mit Supabase ueber HTTP. Statt eines Servers
//   laeuft ein handgeschriebener Fake ([_FakeServer]), der genau die
//   Endpunkte beantwortet, die der Dienst braucht (auth_devices +
//   Auth-Token). So bleibt der Test offline und deterministisch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
// DER GRUND FUER "hide LocalStorage": supabase_flutter exportiert einen
// gleichnamigen Storage - ohne "hide" waere der Name doppelt belegt.
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:thestia/services/device_session_service.dart';
import 'package:thestia/services/local_storage.dart';

/// Baut ein JWT (der Client braucht einen Access-Token fuer die
/// Session).
String _jwt({String sub = 'nutzer-1'}) {
  String teil(Map<String, dynamic> inhalt) =>
      base64Url.encode(utf8.encode(jsonEncode(inhalt))).replaceAll('=', '');
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${teil({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${teil({'sub': sub, 'exp': jetzt + 3600, 'iat': jetzt})}.c2ln';
}

/// Der In-Memory-Speicher fuer die Geraete-ID (kein Keystore, kein
/// Geraet).
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

/// Der handgeschriebene Supabase-Server fuer die Geraete-Tabelle.
class _FakeServer {
  _FakeServer();

  /// Die Zeilen der Geraete-Tabelle (so, wie der Server sie liefert).
  List<Map<String, dynamic>> geraete = [];

  /// Alle Anfragen, die der Server gesehen hat (inkl. Query).
  final List<String> anfragen = [];

  /// Die Koerper der Geraete-Upserts.
  final List<Map<String, dynamic>> upserts = [];

  /// Wenn true, liefert das Listen der Geraete einen Serverfehler.
  bool listenFehler = false;

  /// Wenn true, schlaegt das Loeschen der Geraete fehl.
  bool loeschenFehler = false;

  /// Wenn true, schlaegt das serverseitige Abmelden fehl.
  bool logoutFehler = false;

  /// Wie oft und mit welchem Umfang abgemeldet wurde.
  final List<String> abmeldungen = [];

  Map<String, dynamic> _sessionJson() => {
    'access_token': _jwt(),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-token',
    'user': {
      'id': '11111111-1111-4111-8111-111111111111',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'lena@thestia.de',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };

  http.Response _json(Object inhalt, [int status = 200]) => http.Response(
    jsonEncode(inhalt),
    status,
    headers: {'content-type': 'application/json'},
    // DER GRUND: PostgREST liest die Methode aus "response.request" - ohne
    // das Feld stuerzt der Client auf einem Null-Check ab.
    request: _aktuell,
  );

  /// Die Anfrage, die gerade beantwortet wird.
  http.Request? _aktuell;

  /// Beantwortet einen Aufruf des Supabase-Clients.
  http.Response antworte(http.Request anfrage) {
    _aktuell = anfrage;
    final pfad = anfrage.url.path;
    final query = anfrage.url.query;
    anfragen.add('${anfrage.method} $pfad${query.isEmpty ? '' : '?$query'}');

    // POST /auth/v1/token - der Refresh der Session.
    if (pfad.endsWith('/auth/v1/token')) {
      return _json(_sessionJson());
    }

    // GET /auth/v1/user - der Nutzer zur bestehenden Session.
    if (pfad.endsWith('/auth/v1/user')) {
      return _json(_sessionJson()['user']);
    }

    // POST /auth/v1/logout - das serverseitige Abmelden.
    if (pfad.endsWith('/auth/v1/logout')) {
      abmeldungen.add(query);
      if (logoutFehler) {
        return _json({'msg': 'Serverfehler'}, 500);
      }
      return http.Response('', 204, request: anfrage);
    }

    if (pfad.endsWith('/rest/v1/auth_devices')) {
      if (anfrage.method == 'GET') {
        if (listenFehler) {
          return _json({'code': 'PGRST205', 'message': 'not found'}, 404);
        }
        return _json(geraete);
      }
      if (anfrage.method == 'POST') {
        final koerper = jsonDecode(anfrage.body) as Map<String, dynamic>;
        upserts.add(koerper);
        return _json([koerper], 201);
      }
      if (anfrage.method == 'DELETE') {
        if (loeschenFehler) {
          return _json({'code': '42501', 'message': 'denied'}, 403);
        }
        return http.Response('', 204, request: anfrage);
      }
    }

    return _json({}, 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;
  late _FakeLocalStorage storage;

  setUpAll(() async {
    server = _FakeServer();
    // DER GRUND: supabase_flutter legt beim Start einen PKCE-Speicher in
    // den SharedPreferences an. Im Test gibt es kein Plugin - die
    // Mock-Werte sorgen dafuer, dass es nicht an einem
    // MissingPluginException scheitert.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Supabase ist ein Singleton: er wird genau einmal fuer den ganzen
    // Testprozess eingerichtet. Der MockClient haengt daran.
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((anfrage) async => server.antworte(anfrage)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      // Kein automatisches Wiederholen: ein Serverfehler soll sofort
      // sichtbar sein (und der Test soll schnell bleiben).
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    // Einloggen: die Geraete-Zeilen gehoeren zu einem eingeloggten Konto.
    await Supabase.instance.client.auth.setSession(
      'refresh-token',
      accessToken: _jwt(),
    );
  });

  setUp(() {
    server.geraete = [];
    server.anfragen.clear();
    server.upserts.clear();
    server.abmeldungen.clear();
    server.listenFehler = false;
    server.loeschenFehler = false;
    server.logoutFehler = false;
    storage = _FakeLocalStorage();
    PackageInfo.setMockInitialValues(
      appName: 'Thestia',
      packageName: 'de.thestia.app',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
  });

  group('DeviceSessionService.getDeviceId', () {
    test('die ID wird beim ersten Aufruf erzeugt und gespeichert', () async {
      final service = DeviceSessionService(storage);

      final id = await service.getDeviceId();

      expect(id, startsWith('dev-'), reason: 'Das Format der ID ist "dev-..."');
      expect(
        await storage.getString('auth_device_id'),
        id,
        reason:
            'Die ID muss in den lokalen Speicher - sonst waere sie nach '
            'einem Neustart eine andere und die Geraete-Liste waere voller '
            'Geistergeraete.',
      );
    });

    test('die ID bleibt ueber mehrere Aufrufe stabil', () async {
      final service = DeviceSessionService(storage);

      final erste = await service.getDeviceId();
      final zweite = await service.getDeviceId();

      expect(zweite, erste, reason: 'Ein Geraet muss immer dieselbe ID haben.');
    });

    test(
      'eine bereits gespeicherte ID wird unveraendert uebernommen',
      () async {
        await storage.saveString('auth_device_id', 'dev-vorgegeben-1');
        final service = DeviceSessionService(storage);

        expect(await service.getDeviceId(), 'dev-vorgegeben-1');
      },
    );

    test('eine leere gespeicherte ID wird ersetzt', () async {
      // DER GRUND: Ein leerer Eintrag (z. B. aus einem abgebrochenen
      // Schreibvorgang) ist keine gueltige ID - sonst waere das Geraet
      // nicht mehr vom anderen unterscheidbar.
      await storage.saveString('auth_device_id', '');
      final service = DeviceSessionService(storage);

      final id = await service.getDeviceId();

      expect(id, isNotEmpty);
      expect(id, isNot(''));
    });
  });

  group('DeviceSessionService.describeDevice', () {
    test('liefert einen lesbaren Geraetenamen', () {
      final name = DeviceSessionService.describeDevice();

      expect(name, isNotEmpty);
      expect(
        name,
        isNot(contains('Exception')),
        reason: 'Im Fehlerfall gibt es "Gerät" zurueck, kein Exception-Text',
      );
      if (Platform.operatingSystem == 'windows') {
        expect(name, startsWith('Windows'));
      }
    });
  });

  group('DeviceSession', () {
    test('das echte Geraetemodell gewinnt gegen den Geraetenamen', () {
      // DER GRUND: "Samsung SM-S921B" sagt mehr als "Android (SDK 34)" -
      // nach einer Neuinstallation ist nur so erkennbar, ob es das
      // selbe Geraet ist.
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'device_name': 'Android (SDK 34)',
        'platform': 'android',
        'device_model': 'Samsung SM-S921B',
      });

      expect(sitzung.label, 'Samsung SM-S921B');
    });

    test('ohne Modell gewinnt der Geraetename', () {
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'device_name': 'Windows 10',
        'platform': 'windows',
      });

      expect(sitzung.label, 'Windows 10');
    });

    test('ohne Modell und ohne Namen gewinnt die Plattform', () {
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'device_name': '   ',
        'platform': 'linux',
      });

      expect(sitzung.label, 'linux');
    });

    test('ohne jede Angabe: "Unbekanntes Gerät"', () {
      final sitzung = DeviceSession.fromMap(const {});

      expect(sitzung.label, 'Unbekanntes Gerät');
      expect(sitzung.deviceId, '');
      expect(sitzung.platform, '');
    });

    test('das aktuelle Geraet wird markiert', () {
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'device_name': 'Pixel',
      }, currentDeviceId: 'dev-1');

      expect(sitzung.isCurrent, isTrue);
    });

    test('ein fremdes Geraet wird nicht markiert', () {
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-2',
        'device_name': 'Pixel',
      }, currentDeviceId: 'dev-1');

      expect(sitzung.isCurrent, isFalse);
    });

    test('ohne bekannte aktuelle ID ist nichts markiert', () {
      final sitzung = DeviceSession.fromMap({'device_id': 'dev-1'});

      expect(sitzung.isCurrent, isFalse);
    });

    test('ein kaputter Zeitstempel faellt auf "jetzt" zurueck', () {
      // DER GRUND: Ein unlesbarer Zeitstempel darf die Geraete-Liste
      // nicht sprengen - der Nutzer sieht dann eben "gerade eben".
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'last_seen_at': 'kein-datum',
        'created_at': 'kein-datum',
      });

      expect(
        sitzung.lastSeenAt.difference(DateTime.now()).inMinutes.abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        sitzung.createdAt.difference(DateTime.now()).inMinutes.abs(),
        lessThanOrEqualTo(1),
      );
    });

    test('ein gueltiger Zeitstempel wird gelesen', () {
      final sitzung = DeviceSession.fromMap({
        'device_id': 'dev-1',
        'last_seen_at': '2026-11-01T10:00:00Z',
        'created_at': '2026-10-01T10:00:00Z',
      });

      expect(sitzung.lastSeenAt.toUtc(), DateTime.utc(2026, 11, 1, 10));
      expect(sitzung.createdAt.toUtc(), DateTime.utc(2026, 10, 1, 10));
    });
  });

  group('DeviceSessionService.listDevices', () {
    test('die Geraete des Kontos kommen vom Server', () async {
      server.geraete = [
        {
          'device_id': 'dev-1',
          'device_name': 'Windows 10',
          'platform': 'windows',
          'device_model': 'Surface',
          'last_seen_at': '2026-11-02T10:00:00Z',
          'created_at': '2026-10-01T10:00:00Z',
        },
        {
          'device_id': 'dev-2',
          'device_name': 'Android (SDK 34)',
          'platform': 'android',
          'last_seen_at': '2026-11-01T10:00:00Z',
          'created_at': '2026-10-02T10:00:00Z',
        },
      ];
      final service = DeviceSessionService(storage);

      final liste = await service.listDevices();

      expect(liste.length, 2);
      expect(liste.first.deviceId, 'dev-1');
      expect(liste.first.label, 'Surface');
      expect(
        liste.every((g) => !g.isCurrent),
        isTrue,
        reason:
            'Ohne passende aktuelle ID ist kein Geraet "das aktuelle" - '
            'sonst wuerde der Bildschirm ein falsches Geraet hervorheben.',
      );
    });

    test('das eigene Geraet wird als aktuelles markiert', () async {
      await storage.saveString('auth_device_id', 'dev-2');
      server.geraete = [
        {'device_id': 'dev-1', 'device_name': 'Windows 10', 'platform': 'w'},
        {'device_id': 'dev-2', 'device_name': 'Android', 'platform': 'android'},
      ];
      final service = DeviceSessionService(storage);

      final liste = await service.listDevices();

      expect(liste.where((g) => g.isCurrent).length, 1);
      expect(liste.firstWhere((g) => g.isCurrent).deviceId, 'dev-2');
    });

    test('eine leere Liste ist kein Fehler', () async {
      final service = DeviceSessionService(storage);

      expect(await service.listDevices(), isEmpty);
    });
  });

  group('DeviceSessionService.enrollCurrentDevice', () {
    test('das Geraet wird mit ID, Namen und Version registriert', () async {
      final service = DeviceSessionService(storage);

      await service.enrollCurrentDevice();

      expect(server.upserts.length, 1);
      final upsert = server.upserts.single;
      expect(upsert['device_id'], await service.getDeviceId());
      expect(upsert['device_name'], DeviceSessionService.describeDevice());
      expect(upsert['platform'], Platform.operatingSystem);
      expect(
        upsert['app_version'],
        '1.2.3 (45)',
        reason:
            'Ohne App-Version kann der Support nicht sagen, ob ein Geraet '
            'noch unterstuetzt wird.',
      );
      expect(upsert.containsKey('last_seen_at'), isTrue);
    });
  });

  group('DeviceSessionService.logoutEverywhereExceptCurrent', () {
    test(
      'die anderen Sitzungen werden abgemeldet, das eigene bleibt',
      () async {
        await storage.saveString('auth_device_id', 'dev-1');
        final service = DeviceSessionService(storage);

        await service.logoutEverywhereExceptCurrent();

        expect(
          server.abmeldungen,
          ['scope=others'],
          reason:
              'Nur die ANDEREN Sitzungen duerfen beendet werden - das eigene '
              'Geraet bleibt angemeldet.',
        );
        expect(
          server.anfragen.any(
            (a) => a.startsWith('DELETE') && a.contains('device_id=neq.dev-1'),
          ),
          isTrue,
          reason:
              'Die Zeilen der anderen Geraete muessen aus der Liste '
              'verschwinden.',
        );
      },
    );

    test(
      'schlaegt der Logout fehl, bleiben die Geraete-Zeilen stehen',
      () async {
        // DER GRUND FUER DIE REIHENFOLGE: Erst die Server-Sessions
        // invalidieren, dann die Liste aufräumen. Schlaegt der Logout fehl,
        // sind die anderen Sitzungen noch aktiv - ihre Zeilen zu loeschen
        // waere eine Luege in der Geraete-Liste.
        await storage.saveString('auth_device_id', 'dev-1');
        server.logoutFehler = true;
        final service = DeviceSessionService(storage);

        await expectLater(
          service.logoutEverywhereExceptCurrent(),
          throwsA(isA<AuthException>()),
        );
        expect(
          server.anfragen.any((a) => a.startsWith('DELETE')),
          isFalse,
          reason:
              'Die Geraete-Zeilen wurden geloescht, obwohl die anderen '
              'Sitzungen noch aktiv sind.',
        );
      },
    );
  });

  group('DeviceSessionService.deregisterCurrentDevice', () {
    test('die eigene Zeile wird geloescht', () async {
      await storage.saveString('auth_device_id', 'dev-1');
      final service = DeviceSessionService(storage);

      await service.deregisterCurrentDevice();

      expect(
        server.anfragen.any(
          (a) => a.startsWith('DELETE') && a.contains('device_id=eq.dev-1'),
        ),
        isTrue,
        reason: 'Beim Ausloggen muss die eigene Geraete-Zeile weg.',
      );
    });

    test('ein Serverfehler wird geschluckt (best effort)', () async {
      // DER GRUND: Das Deregistrieren ist eine Nebenhandlung. Wenn es
      // scheitert (kein Netz), darf der Logout nicht hängen bleiben -
      // der Eintrag verschwindet spaetestens mit der abgelaufenen
      // Session.
      await storage.saveString('auth_device_id', 'dev-1');
      server.loeschenFehler = true;
      final service = DeviceSessionService(storage);

      await expectLater(service.deregisterCurrentDevice(), completes);
    });
  });
}
