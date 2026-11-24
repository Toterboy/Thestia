// Die Helfer fuer die Tests des Zufallschats.
//
// DER WEG: Die Testdatei fuer den Zufallschat waechst ueber die Grenze
// von 1000 Zeilen. Die Attrappen und der Aufbau liegen deshalb hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.
//
// OHNE ECHTE GERAETE: Der Zufallschat-Dienst, der P2P-Dienst und der
// Relay-Dienst sind Hand-Attrappen. Es geht keine Anfrage ins Netz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/services/dating_hour/random_chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';

/// Der Speicher im RAM.
class ZufallChatSpeicher implements LocalStorage {
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

/// Hand-Fake des Zufallschat-Dienstes (die Warteschlange liegt im RAM).
class FakeRandomChatService extends RandomChatService {
  FakeRandomChatService(super.client);

  /// Die Session, die [join] liefert.
  RandomChatSession? sitzung;

  /// Die Session, die [getSession] liefert.
  RandomChatSession? befragt;

  /// Wie oft wurde der Warteschlange beigetreten?
  int beitritte = 0;

  /// Wie oft wurde die Sitzung abgefragt?
  int abfragen = 0;

  @override
  Future<RandomChatSession?> join() async {
    beitritte++;
    return sitzung;
  }

  @override
  Future<RandomChatSession?> getSession(String sessionId) async {
    abfragen++;
    return befragt;
  }

  @override
  Future<void> leave(String sessionId) async {}
}

/// Hand-Fake des P2P-Dienstes (kein WebRTC-Plugin im Test).
///
/// DER GRUND: Der echte Dienst braucht das WebRTC-Plugin - im Test gibt
/// es kein Geraet. Der Fake meldet die Zustaende, die der Test vorgibt
/// (offener Datenkanal, ICE-Fehler, eingehende Nachricht, Wake-up-Ping).
class FakeP2PChatService extends P2PChatService {
  FakeP2PChatService(super.webrtc, super.prekey);

  /// Die eingehenden Textnachrichten.
  final StreamController<String> eingang = StreamController<String>.broadcast();

  /// Der Zustand des Datenkanals.
  final StreamController<RTCDataChannelState> kanalZustand =
      StreamController<RTCDataChannelState>.broadcast();

  /// Der ICE-Zustand.
  final StreamController<RTCIceConnectionState> iceZustand =
      StreamController<RTCIceConnectionState>.broadcast();

  /// Die Wake-up-Pings des Partners.
  final StreamController<void> pings = StreamController<void>.broadcast();

  /// Steht der Datenkanal?
  bool offen = false;

  /// Wie oft wurde die Verbindung aufgebaut?
  int verbindungen = 0;

  /// Wie oft wurde der Handshake erneut versucht?
  int wiederholungen = 0;

  /// Der Fehler, den [connect] werfen soll (null = alles gut).
  String? fehler;

  /// Die Texte, die vor dem offenen Kanal geschrieben wurden.
  ///
  /// DER GRUND: Beim Umschalten in den Relay-Modus wird die Outbox
  /// nachgeliefert - so sieht der Test, ob die Nachricht den Weg zum
  /// Server gefunden hat.
  final List<String> outbox = <String>[];

  @override
  Stream<String> get incomingMessages => eingang.stream;

  @override
  Stream<RTCDataChannelState> get connectionState => kanalZustand.stream;

  @override
  Stream<RTCIceConnectionState> get iceConnectionState => iceZustand.stream;

  @override
  Stream<void> get relayPing => pings.stream;

  @override
  bool get isConnected => offen;

  @override
  bool get isDataChannelOpen => offen;

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    verbindungen++;
    final fehler = this.fehler;
    if (fehler != null) throw StateError(fehler);
  }

  @override
  Future<void> ensureConnected({
    required String myUserId,
    required String peerId,
  }) async {
    wiederholungen++;
    final fehler = this.fehler;
    if (fehler != null) throw StateError(fehler);
  }

  @override
  Future<void> drainOutboxViaRelay(
    Future<void> Function(String text) send,
  ) async {
    for (final text in outbox) {
      await send(text);
    }
    outbox.clear();
  }

  /// Der Kanal geht auf (der Bildschirm zeigt dann "verbunden").
  void kanalOeffnen() {
    offen = true;
    kanalZustand.add(RTCDataChannelState.RTCDataChannelOpen);
  }

  /// Der Kanal geht wieder zu.
  void kanalSchliessen() {
    offen = false;
    kanalZustand.add(RTCDataChannelState.RTCDataChannelClosed);
  }

  /// Der Partner schickt eine Nachricht ueber den direkten Kanal.
  void empfange(String text) => eingang.add(text);

  /// Der Partner meldet: im Relay wartet etwas.
  void ping() => pings.add(null);

  @override
  Future<void> dispose() async {
    await eingang.close();
    await kanalZustand.close();
    await iceZustand.close();
    await pings.close();
    await super.dispose();
  }
}

/// Hand-Fake des Relay-Dienstes (der Server legt die Zeilen im RAM ab).
class FakeRelayService extends RelayService {
  FakeRelayService(super.ref);

  /// Die Nachrichten, die der Server bereit haelt.
  final List<RelayMessage> wartend = <RelayMessage>[];

  /// Wie oft wurde abgeholt?
  int abholungen = 0;

  /// Die Texte, die ueber den Relay abgelegt wurden.
  final List<String> abgelegt = <String>[];

  @override
  Future<List<RelayMessage>> fetchPending({
    String? from,
    bool ack = true,
  }) async {
    abholungen++;
    if (from == null) return List<RelayMessage>.from(wartend);
    return wartend.where((m) => m.senderId == from).toList();
  }

  @override
  Future<void> storeText({
    required String peerId,
    required String text,
    String kind = 'text',
  }) async {
    abgelegt.add(text);
  }
}

/// Das Ergebnis eines Testlaufs (der Bildschirm und die Attrappen).
class ZufallChatAufbau {
  ZufallChatAufbau({
    required this.container,
    required this.dienst,
    required this.p2p,
    required this.relay,
    required this.notifier,
  });

  final ProviderContainer container;
  final FakeRandomChatService dienst;
  final FakeP2PChatService p2p;
  final FakeRelayService relay;
  final ChatNotifier notifier;
}

/// Der Ersatz-Server (die Antworten kommen aus dem RAM).
///
/// DER GRUND: Supabase ist ein Singleton - der Aufruf darf nur einmal je
/// Testdatei laufen. Deshalb liegt der Server hier.
final FakeSupabaseServer zufallChatServer = FakeSupabaseServer(userId: 'ich');

/// Richtet den Ersatz-Server ein (Supabase ist ein Singleton).
///
/// DER GRUND: Der Bildschirm liest `Supabase.instance` (den globalen
/// Client) - ein eigener Client waere dort nicht sichtbar.
Future<void> initZufallChatServer() async {
  await supabase.Supabase.initialize(
    url: 'https://example.supabase.co',
    publishableKey: 'test-key',
    httpClient: zufallChatServer,
    authOptions: const supabase.FlutterAuthClientOptions(
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUri: false,
    ),
  );
  await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
}

/// Die Session, in der ein Partner wartet.
const RandomChatSession partnerSession = RandomChatSession(
  sessionId: 'session-1',
  partnerId: 'partner-1',
  status: RandomChatStatus.active,
);

/// Baut den Zufallschat.
///
/// [partnerName] ist der Name, den der Server fuer den Partner meldet
/// (null = der Server kennt das Profil nicht).
///
/// [fehler] ist der Fehler, mit dem der Verbindungsaufbau scheitert
/// (null = der Aufbau klappt).
Future<ZufallChatAufbau> baueZufallChat(
  WidgetTester tester, {
  RandomChatSession? sitzung,
  String? partnerName = 'Mira',
  String? fehler,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  if (partnerName != null) {
    zufallChatServer.rpcAntworten['get_public_profile'] = <String, dynamic>{
      'id': 'partner-1',
      'name': partnerName,
    };
  }

  final router = GoRouter(
    initialLocation: _startRoute,
    routes: <RouteBase>[
      GoRoute(
        path: _startRoute,
        builder: (context, state) => const RandomChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.swipeModeSelection,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Modus-Auswahl'))),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Startseite'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  final dienst = FakeRandomChatService(supabase.Supabase.instance.client)
    ..sitzung = sitzung;
  final notifier = ChatNotifier(ChatService());

  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(ZufallChatSpeicher()),
      randomChatServiceProvider.overrideWithValue(dienst),
      chatProvider.overrideWith((ref) => notifier),
      p2pChatServiceProvider.overrideWith((ref) {
        final dienst = FakeP2PChatService(
          ref.watch(webRTCServiceProvider),
          ref.watch(preKeyServiceProvider),
        );
        dienst.fehler = fehler;
        ref.onDispose(dienst.dispose);
        return dienst;
      }),
      relayServiceProvider.overrideWith((ref) => FakeRelayService(ref)),
    ],
  );
  addTearDown(container.dispose);

  // DIE ATTRAPPEN SOFORT BAUEN: Die Provider sind sonst erst beim
  // ersten Zugriff da - der Test braucht sie aber sofort (z. B. um
  // eine Relay-Nachricht einzuschieben).
  final p2p = container.read(p2pChatServiceProvider) as FakeP2PChatService;
  final relay = container.read(relayServiceProvider) as FakeRelayService;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  // DIE ECHTE EREIGNISSCHLEIFE: Das Partnerprofil kommt ueber den
  // Server - ohne dieses Warten bleibt der Bildschirm im "verbinde".
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 80));
  }
  return ZufallChatAufbau(
    container: container,
    dienst: dienst,
    p2p: p2p,
    relay: relay,
    notifier: notifier,
  );
}

/// Setzt den Lebenszyklus der App.
///
/// DER GRUND: Das Framework (der AppLifecycleListener) meldet jeden
/// Sprung als Fehler - der Weg muss also ueber inactive und hidden
/// gehen. Diese Hilfsfunktion nimmt den Umweg.
void setzeLebenszyklus(WidgetTester tester, AppLifecycleState ziel) {
  final aktuell = tester.binding.lifecycleState;
  // ZUERST WIEDER "WACH": paused -> hidden -> inactive -> resumed.
  if (aktuell == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (aktuell == AppLifecycleState.paused ||
      aktuell == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (aktuell != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  // Und dann in den Hintergrund: resumed -> inactive -> hidden -> paused.
  if (ziel == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
}

/// Die Route, auf der der Screen im Test liegt.
const String _startRoute = '/zufallschat';
