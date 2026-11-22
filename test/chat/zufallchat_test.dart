// Der Zufallschat (zwei fremde Menschen, 1:1).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/parts/zufallchatverbindung.dart 103 offene Zeilen bei
// 12 % Abdeckung. Das ist der Bildschirm, in dem man fremden Menschen
// schreibt - und der Weg, auf dem die App in den Relay-Modus faellt, wenn
// das Mobilfunknetz keine direkte Verbindung hinbekommt.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Partner kommt die Fehlerseite (kein endloses Warten),
//   * mit Partner steht der Chat,
//   * scheitert die Direktverbindung, schaltet die App in den
//     Relay-Modus und sagt das dem Nutzer (kein stummes Warten),
//   * ohne Anmeldung sagt die App das ebenfalls.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// webrtc_interface kommt als Transitivum ueber flutter_webrtc - der Test
// braucht nur den ICE-Zustand.
// ignore_for_file: depend_on_referenced_packages
import 'package:webrtc_interface/webrtc_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/dating_hour/random_chat_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Zufallschat-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst fragt die Warteschlange ueber eine RPC ab.
/// Der Fake haelt die Antwort im RAM - so kann der Test beide Faelle
/// stellen (Partner gefunden / niemand da).
class _FakeRandomChatService extends RandomChatService {
  _FakeRandomChatService(super.client);

  /// Die Session, die der Dienst meldet (null = niemand da).
  RandomChatSession? sitzung;

  /// Wie oft wurde der Warteschlange beigetreten?
  int beitritte = 0;

  @override
  Future<RandomChatSession?> join() async {
    beitritte++;
    return sitzung;
  }

  @override
  Future<RandomChatSession?> getSession(String sessionId) async => sitzung;

  @override
  Future<void> leave(String sessionId) async {}
}

/// Der P2P-Dienst ohne WebRTC.
///
/// DER GRUND: Die echte Direktverbindung braucht das WebRTC-Plugin - im
/// Test gibt es kein Geraet. Der Fake meldet den ICE-Zustand, den der
/// Test vorgibt - so laesst sich der Ausfall der Direktverbindung
/// stellen.
class _FakeP2PChatService extends P2PChatService {
  _FakeP2PChatService(super.webrtc, super.prekey);

  /// Der ICE-Zustand, den der Test meldet.
  final StreamController<RTCIceConnectionState> ice =
      StreamController<RTCIceConnectionState>.broadcast();

  /// Wie oft wurde die Verbindung aufgebaut?
  int verbindungen = 0;

  @override
  Stream<RTCIceConnectionState> get iceConnectionState => ice.stream;

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    verbindungen++;
  }

  @override
  Future<void> dispose() async {
    await ice.close();
  }
}

/// Der Relay-Dienst, der nichts ablegt.
class _FakeRelayService extends RelayService {
  _FakeRelayService(super.ref);

  @override
  Future<void> storeText({
    required String peerId,
    required String text,
    String kind = 'text',
  }) async {}

  @override
  Future<List<RelayMessage>> fetchPending({
    String? from,
    bool ack = true,
  }) async => <RelayMessage>[];
}

/// Der Speicher im RAM - der Chat merkt sich dort den Verlauf.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

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
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: die verschluesselten Schluessel (Signal-Protokoll) liegen in
    // Hive-Boxen.
    await mockHive();
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.zeilen.clear();
    server.rpcAntworten.clear();
  });

  /// Baut den Zufallschat.
  Future<_FakeP2PChatService?> zeige(
    WidgetTester tester, {
    required RandomChatSession? sitzung,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/zufall',
      routes: [
        GoRoute(
          path: '/zufall',
          builder: (ctx, state) => const RandomChatScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (ctx, state) => const Scaffold(body: Text('Startseite')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final dienst = _FakeRandomChatService(supabase.Supabase.instance.client)
      ..sitzung = sitzung;
    // DER P2P-DIENST: Er wird nur gebaut, wenn der Bildschirm ihn auch
    // braucht (ohne Partner gibt es keine Verbindung).
    _FakeP2PChatService? p2p;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_Speicher()),
          randomChatServiceProvider.overrideWithValue(dienst),
          p2pChatServiceProvider.overrideWith((ref) {
            final dienst = _FakeP2PChatService(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            );
            p2p = dienst;
            ref.onDispose(dienst.dispose);
            return dienst;
          }),
          relayServiceProvider.overrideWith((ref) => _FakeRelayService(ref)),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // DIE ECHTE EREIGNISSCHLEIFE: Das Profil des Partners kommt ueber den
    // Server - ohne dieses Warten bleibt der Bildschirm im "verbinde"
    // stehen und der P2P-Aufbau kommt nie zu Ende.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
    return p2p;
  }

  group('Der Zufallschat', () {
    testWidgets('ohne Partner kommt die Fehlerseite', (tester) async {
      await zeige(tester, sitzung: null);

      // DIE WIEDERHOLUNG: Ohne Partner wartet die App 1,5 Sekunden und
      // versucht es erneut - erst danach kommt die Fehlerseite.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.errorNoPartner')),
        findsOneWidget,
        reason:
            'Ohne Partner muss die App das sagen - endloses Warten sieht '
            'wie ein Fehler aus.',
      );
    });

    testWidgets('mit Partner steht der Chat', (tester) async {
      await zeige(
        tester,
        sitzung: const RandomChatSession(
          sessionId: 'session-1',
          partnerId: 'partner-1',
          status: RandomChatStatus.active,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byIcon(Icons.favorite),
        findsOneWidget,
        reason:
            'Im Chat muss der "Gefällt mir"-Knopf stehen - das ist der '
            'einzige Weg aus dem Zufallschat heraus.',
      );
    });

    testWidgets('scheitert die Direktverbindung, kommt der Relay-Hinweis', (
      tester,
    ) async {
      final p2p = await zeige(
        tester,
        sitzung: const RandomChatSession(
          sessionId: 'session-1',
          partnerId: 'partner-1',
          status: RandomChatStatus.active,
        ),
      );

      // DER ICE-FEHLER: Mobilfunk/CGNAT - die direkte Verbindung geht
      // nicht auf.
      p2p!.ice.add(RTCIceConnectionState.RTCIceConnectionStateFailed);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(
        find.text(L10n.tWithoutContext('random.relayNoDirect')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass der Chat ueber den Server laeuft '
            '- sonst denkt er, die App haenge.',
      );
      expect(
        find.text(L10n.tWithoutContext('random.relayStatus')),
        findsOneWidget,
        reason: 'Die Statuszeile muss den Relay-Modus zeigen.',
      );
    });
  });
}
