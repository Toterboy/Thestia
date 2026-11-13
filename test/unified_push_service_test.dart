// Unit-Tests fuer den UnifiedPush-Dienst (F-Droid-Push ohne Google).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Registrierung beim Connector (Distributor suchen, speichern,
//     registrieren) und die Fehlermeldung, wenn gar kein Distributor da ist,
//   * das Endpunkt-Handling: nur HTTPS-Endpunkte werden gespeichert
//     (Sicherheitsmassnahme, 03.11.2026),
//   * das Abschalten (abmelden + Endpunkt serverseitig loeschen),
//   * der Serverstand (ist UnifiedPush aktiv?),
//   * der eingehende Push: Payload auswerten, lokale Benachrichtigung
//     zeigen, Unterdrueckung bei offenem Chat.
//
// WIE DIE PLUGIN-AUFRUFE ABGESCHNITTEN WERDEN:
//   * UnifiedPush laeuft ueber `UnifiedPushPlatform.instance` - der Test
//     setzt dort einen handgeschriebenen Fake (der "Connector").
//   * Die lokale Benachrichtigung laeuft ueber
//     `FlutterLocalNotificationsPlatform.instance` - auch da ein Fake.
//   * Supabase laeuft ueber einen `http.Client` - der Test setzt einen
//     MockClient, der den "Server" spielt.
//
// Alles laeuft offline und deterministisch.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:thestia/services/unified_push_service.dart';

/// Baut ein JWT fuer die Test-Session.
///
/// DER GRUND: Der Supabase-Client braucht eine Session, damit der
/// Dienst das eigene Profil schreiben darf (RLS). Ohne Session waere
/// `SupabaseService.currentUser` null und der Endpunkt koennte gar nicht
/// gespeichert werden.
String _jwt() {
  String teil(Map<String, dynamic> inhalt) =>
      base64Url.encode(utf8.encode(jsonEncode(inhalt))).replaceAll('=', '');
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${teil({'alg': 'HS256', 'typ': 'JWT'})}'
      '.${teil({'sub': 'nutzer-1', 'exp': jetzt + 3600, 'iat': jetzt})}'
      '.c2ln';
}

/// Der "Server": beantwortet die Supabase-Anfragen des Dienstes.
class _FakeServer {
  /// Der Endpunkt, den der Server kennt (null = keiner hinterlegt).
  String? upEndpoint;

  /// HTTP-Status beim Lesen des Profils (0 = Erfolg).
  int profilLeseStatus = 0;

  /// HTTP-Status beim Schreiben des Profils (0 = Erfolg).
  int profilSchreibStatus = 0;

  /// Die Koerper der Profil-Schreibvorgaenge.
  final List<Map<String, dynamic>> profilUpdates = [];

  /// Alle Anfragen, die der Server gesehen hat.
  final List<String> anfragen = [];

  /// Setzt den Server fuer den naechsten Test zurueck.
  void zuruecksetzen() {
    upEndpoint = null;
    profilLeseStatus = 0;
    profilSchreibStatus = 0;
    profilUpdates.clear();
    anfragen.clear();
  }

  Map<String, dynamic> _userJson() => {
    'id': 'nutzer-1',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'lena@thestia.de',
    'created_at': '2026-01-01T00:00:00Z',
  };

  http.Response antworte(http.Request anfrage) {
    final pfad = anfrage.url.path;
    anfragen.add('${anfrage.method} $pfad');
    const header = {'content-type': 'application/json'};

    // WICHTIG: Das `request` muss mitgegeben werden - der PostgREST-Client
    // liest daraus die Methode (sonst knallt er mit einer Null-Assertion).
    http.Response antwort(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: header,
      request: anfrage,
    );

    // GET /auth/v1/user
    if (anfrage.method == 'GET' && pfad.endsWith('/auth/v1/user')) {
      return antwort(_userJson(), 200);
    }

    // GET /rest/v1/profiles - der eigene Endpunkt-Stand.
    if (anfrage.method == 'GET' && pfad.contains('/rest/v1/profiles')) {
      if (profilLeseStatus != 0) {
        return antwort({'msg': 'kaputt'}, profilLeseStatus);
      }
      return antwort([
        {'up_endpoint': upEndpoint},
      ], 200);
    }

    // PATCH /rest/v1/profiles - den Endpunkt speichern oder loeschen.
    if (anfrage.method == 'PATCH' && pfad.contains('/rest/v1/profiles')) {
      if (profilSchreibStatus != 0) {
        return antwort({'msg': 'kaputt'}, profilSchreibStatus);
      }
      profilUpdates.add(jsonDecode(anfrage.body) as Map<String, dynamic>);
      return antwort([], 200);
    }

    return antwort({}, 404);
  }
}

/// Der Fake des UnifiedPush-Connectors ("Distributor").
///
/// DER GRUND: `UnifiedPushPlatform.instance` ist im Test die einzige
/// Stelle, an der der Dienst den Connector erreicht. Der Fake merkt sich
/// die Callbacks, die der Dienst verdrahtet - so kann der Test sie
/// ausloesen, so wie es der echte Connector tut.
class _FakeUnifiedPush extends UnifiedPushPlatform {
  /// Der Distributor, den der Connector kennt (null = keiner).
  String? gespeicherterDistributor;

  /// Die auf dem Geraet installierten Distributoren.
  List<String> distributoren = const [];

  /// Wurde sich beim Distributor registriert?
  bool registriert = false;

  /// Wurde sich abgemeldet?
  bool abgemeldet = false;

  /// Der Callback fuer einen neuen Endpunkt (vom Dienst verdrahtet).
  ///
  /// DER GRUND FUER DEN `dynamic`-CAST: `UnifiedPush` kapselt den Callback
  /// in einen asynchronen Wrapper, dessen statischer Typ trotzdem `void`
  /// ist. Nur ueber den Cast kann der Test auf das ENDE der Arbeit
  /// warten (der Dienst schreibt den Endpunkt serverseitig).
  Future<void> Function(PushEndpoint endpoint, String instance)?
  onNeuerEndpunkt;

  /// Der Callback fuer eine eingehende Nachricht.
  Future<void> Function(PushMessage message, String instance)? onNachricht;

  @override
  Future<List<String>> getDistributors(List<String> features) async =>
      distributoren;

  @override
  Future<String?> getDistributor() async => gespeicherterDistributor;

  @override
  Future<void> saveDistributor(String distributor) async {
    gespeicherterDistributor = distributor;
  }

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async {
    registriert = true;
  }

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async => false;

  @override
  Future<void> unregister(String instance) async {
    abgemeldet = true;
  }

  @override
  Future<void> initializeCallback({
    void Function(PushEndpoint endpoint, String instance)? onNewEndpoint,
    void Function(FailedReason reason, String instance)? onRegistrationFailed,
    void Function(String instance)? onUnregistered,
    void Function(PushMessage message, String instance)? onMessage,
  }) async {
    onNeuerEndpunkt = (endpoint, instance) async {
      final callback = onNewEndpoint as dynamic;
      await callback?.call(endpoint, instance);
    };
    onNachricht = (message, instance) async {
      final callback = onMessage as dynamic;
      await callback?.call(message, instance);
    };
  }

  @override
  Future<void> initializeOnTempUnavailable(
    void Function(String instance)? onTempUnavailable,
  ) async {}

  @override
  void setLinuxOptions(LinuxOptions options) {}
}

/// Der Android-Fake des Benachrichtigungs-Plugins.
class _FakeNotificationsPlugin extends AndroidFlutterLocalNotificationsPlugin {
  /// Die Benachrichtigungen, die gezeigt wurden.
  final List<({int id, String? title, String? body})> gezeigt = [];

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    gezeigt.add((id: id, title: title, body: body));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;
  late _FakeUnifiedPush connector;
  late _FakeNotificationsPlugin plugin;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    server = _FakeServer();
    // Supabase ist ein Singleton: er wird genau einmal fuer den ganzen
    // Testprozess eingerichtet. Der MockClient haengt daran - deshalb
    // arbeitet der Test mit einem gemeinsamen [_FakeServer], dessen
    // Zustand pro Test zurueckgesetzt wird.
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
    // Einloggen: der Dienst darf nur das eigene Profil aendern.
    await Supabase.instance.client.auth.setSession(
      'refresh-token',
      accessToken: _jwt(),
    );
  });

  setUp(() {
    server.zuruecksetzen();
    connector = _FakeUnifiedPush();
    // Standardmaessig ist ein Distributor installiert (wie auf einem Geraet
    // mit ntfy). Die Tests ohne Distributor setzen das explizit auf leer.
    connector.distributoren = const ['org.example.ntfy'];
    UnifiedPushPlatform.instance = connector;
    plugin = _FakeNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = plugin;
  });

  tearDown(() {
    UnifiedPushService.suppressCheck = null;
  });

  /// Fuehrt den Testkoerper im Android-Zweig des Plugins aus.
  ///
  /// DER GRUND: `debugDefaultTargetPlatformOverride` muss am Ende eines
  /// Tests wieder auf null stehen (das prueft das Test-Framework) -
  /// deshalb wird es hier im `finally` zurueckgesetzt.
  Future<void> alsAndroid(Future<void> Function() koerper) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await koerper();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('UnifiedPushService.enable', () {
    test('ohne Distributor: klare Fehlermeldung fuer die UI', () async {
      await alsAndroid(() async {
        // Auf dem Geraet ist kein Distributor installiert.
        connector.distributoren = const [];

        await expectLater(
          UnifiedPushService.enable(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Distributor'),
            ),
          ),
          reason:
              'Ohne Distributor kann die App keinen Push empfangen - der '
              'Nutzer muss einen Hinweis bekommen.',
        );
        expect(
          UnifiedPushService.lastError,
          contains('Distributor'),
          reason: 'Die UI liest den Fehler aus lastError',
        );
        expect(
          connector.registriert,
          isFalse,
          reason: 'Ohne Distributor kann man sich auch nicht registrieren',
        );
      });
    });

    test('mit Distributor: speichern und registrieren', () async {
      await alsAndroid(() async {
        connector.distributoren = const ['org.example.ntfy'];

        await UnifiedPushService.enable();

        expect(
          connector.gespeicherterDistributor,
          'org.example.ntfy',
          reason: 'Der gewaehlte Distributor muss gespeichert werden',
        );
        expect(
          connector.registriert,
          isTrue,
          reason: 'Ohne Registrierung kommt kein Push an',
        );
        expect(UnifiedPushService.lastError, isNull);
      });
    });

    test(
      'mit bereits gespeichertem Distributor: direkt registrieren',
      () async {
        await alsAndroid(() async {
          connector.gespeicherterDistributor = 'org.example.ntfy';
          connector.distributoren = const ['org.example.ntfy', 'org.anderes'];

          await UnifiedPushService.enable();

          expect(
            connector.gespeicherterDistributor,
            'org.example.ntfy',
            reason:
                'Ein gespeicherter Distributor wird nicht ueberschrieben - der '
                'Nutzer hat ihn bewusst gewaehlt.',
          );
          expect(connector.registriert, isTrue);
        });
      },
    );
  });

  group('UnifiedPushService - Endpunkt', () {
    test('ein HTTPS-Endpunkt wird gespeichert', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();
        connector.distributoren = const ['org.example.ntfy'];

        await connector.onNeuerEndpunkt!(
          PushEndpoint('https://ntfy.sh/up-abc', null),
          'default',
        );

        expect(
          server.profilUpdates.single['up_endpoint'],
          'https://ntfy.sh/up-abc',
          reason:
              'Der Endpunkt muss serverseitig stehen - die Edge Function '
              'notify-user schickt die Metadaten dorthin.',
        );
      });
    });

    test('ein http-Endpunkt wird verworfen (Klartext)', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await connector.onNeuerEndpunkt!(
          PushEndpoint('http://ntfy.sh/up-abc', null),
          'default',
        );

        expect(
          server.profilUpdates,
          isEmpty,
          reason:
              'SICHERHEIT: Der UnifiedPush-Connector bringt exportierte '
              'Komponenten mit, die jede App ansprechen kann. Ein Endpunkt '
              'auf http:// wuerde die Push-Metadaten im Klartext uebertragen '
              '- deshalb wird er verworfen.',
        );
      });
    });

    test('ein Endpunkt ohne Host wird verworfen', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await connector.onNeuerEndpunkt!(
          PushEndpoint('https://', null),
          'default',
        );

        expect(server.profilUpdates, isEmpty);
      });
    });

    test('ein leerer Endpunkt wird verworfen', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await connector.onNeuerEndpunkt!(PushEndpoint('', null), 'default');

        expect(server.profilUpdates, isEmpty);
      });
    });

    test('ein Serverfehler beim Speichern bringt nichts zum Absturz', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();
        server.profilSchreibStatus = 500;

        await expectLater(
          connector.onNeuerEndpunkt!(
            PushEndpoint('https://ntfy.sh/up-abc', null),
            'default',
          ),
          completes,
          reason:
              'Der Endpunkt-Sync ist eine Nebenhandlung - ein Fehler darf die '
              'App nicht zum Absturz bringen.',
        );
      });
    });
  });

  group('UnifiedPushService.disable', () {
    test('meldet ab und loescht den Endpunkt serverseitig', () async {
      await alsAndroid(() async {
        await UnifiedPushService.disable();

        expect(
          connector.abgemeldet,
          isTrue,
          reason: 'Ohne Abmeldung bekommt die App weiter Pushes',
        );
        expect(
          server.profilUpdates.single['up_endpoint'],
          isNull,
          reason:
              'Der Endpunkt muss weg - sonst schickt die Edge Function weiter '
              'Metadaten an den Distributor.',
        );
      });
    });
  });

  group('UnifiedPushService.isEnabled', () {
    test('true, wenn der Server einen Endpunkt kennt', () async {
      server.upEndpoint = 'https://ntfy.sh/up-abc';

      expect(await UnifiedPushService.isEnabled(), isTrue);
    });

    test('false, wenn kein Endpunkt hinterlegt ist', () async {
      server.upEndpoint = null;

      expect(await UnifiedPushService.isEnabled(), isFalse);
    });

    test('false bei einem Serverfehler', () async {
      server.profilLeseStatus = 400;

      expect(
        await UnifiedPushService.isEnabled(),
        isFalse,
        reason:
            'Ein Serverfehler darf den Schalter nicht auf "aktiv" springen '
            'lassen - der Nutzer wuerde denkt, UnifiedPush laeufe.',
      );
    });
  });

  group('UnifiedPushService - eingehender Push', () {
    test('der JSON-Payload wird als lokale Benachrichtigung gezeigt', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await connector.onNachricht!(
          PushMessage(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'title': 'Neue Nachricht',
                  'message': 'Hallo, hast du Zeit?',
                  'kind': 'messages',
                  'from_user_id': 'partner-1',
                }),
              ),
            ),
            true,
          ),
          'default',
        );

        expect(plugin.gezeigt.length, 1);
        expect(plugin.gezeigt.single.title, 'Neue Nachricht');
        expect(plugin.gezeigt.single.body, 'Hallo, hast du Zeit?');
      });
    });

    test('ein reiner Text wird als Nachrichtentext uebernommen', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await connector.onNachricht!(
          PushMessage(Uint8List.fromList(utf8.encode('Nur Text')), true),
          'default',
        );

        expect(plugin.gezeigt.single.body, 'Nur Text');
        expect(
          plugin.gezeigt.single.title,
          'Thestia',
          reason: 'Ohne Titel in der Payload bleibt der Standardtitel',
        );
      });
    });

    test('ist der Chat offen, wird die Benachrichtigung unterdrueckt', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();
        UnifiedPushService.suppressCheck = (von) => von == 'partner-1';

        await connector.onNachricht!(
          PushMessage(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'title': 'Neue Nachricht',
                  'message': 'Hallo',
                  'kind': 'messages',
                  'from_user_id': 'partner-1',
                }),
              ),
            ),
            true,
          ),
          'default',
        );

        expect(
          plugin.gezeigt,
          isEmpty,
          reason:
              'Der Chat ist gerade offen - eine zusaetzliche Benachrichtigung '
              'waere nur stoerend.',
        );
      });
    });

    test('eine kaputte Nachricht fuehrt nicht zum Absturz', () async {
      await alsAndroid(() async {
        await UnifiedPushService.enable();

        await expectLater(
          connector.onNachricht!(
            // Kein gueltiges JSON - der Decoder stolpert darueber.
            PushMessage(Uint8List.fromList(utf8.encode('{kaputt')), true),
            'default',
          ),
          completes,
          reason:
              'Eine kaputte Push-Nachricht darf die App nicht zum Absturz '
              'bringen - der Fehler wird geloggt, nicht weitergegeben.',
        );
      });
    });
  });
}
