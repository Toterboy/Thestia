// Die Zustände des Chat-Bildschirms (der direkte Kanal und der Aufbau).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/parts/chatp2p.dart 73 offene Zeilen und für
// lib/screens/chat/parts/chatdetailaufbau.dart 70 offene Zeilen. Das
// sind genau die Wege, die im Alltag passieren, aber nie getestet waren:
// ein Bild oder eine Sprachnachricht über den direkten Kanal, ein
// eingehender Anruf, ein Wechsel des Identity-Keys (Sicherheit!) und die
// Karten, die der Bildschirm über dem Verlauf zeigt.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein Bild und eine Sprachnachricht aus dem direkten Kanal landen im
//     Verlauf,
//   * ein eingehender Anruf öffnet den Anruf-Screen,
//   * ein Wechsel des Identity-Keys wird NICHT still akzeptiert, sondern
//     muss bestätigt werden,
//   * die Probleme beim Verbindungsaufbau stehen in der Diagnose,
//   * das Partnerprofil wird vom Server nachgeladen,
//   * die Erinnerungs-Karte und der Freunde-Badge stehen da.
//
// OHNE ECHTE GERÄTE: Der P2P-Dienst ist eine Hand-Attrappe, die dem
// Test die eingehenden Nachrichten schiebt. Es geht keine Anfrage ins
// Netz (der Server ist ein Ersatz im RAM).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// webrtc_interface kommt als Transitivum über flutter_webrtc - der Test
// braucht nur die Zustände des Datenkanals. `MessageType` liefert
// webrtc_interface auch - das eigene des Chat-Modells gewinnt.
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/match.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/mood_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/services/server/mood_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
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

/// Der Profil-Speicher im RAM (ohne Klartext auf der Platte).
class _SpeicherFuerProfile extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Hand-Fake des P2P-Dienstes.
///
/// DER GRUND: Der echte Dienst braucht das WebRTC-Plugin - im Test gibt
/// es kein Gerät. Der Fake nimmt die eingehenden Nachrichten, Bilder,
/// Anrufe und Probleme entgegen und zählt die Verbindungsversuche.
class _FakeP2PChatService extends P2PChatService {
  _FakeP2PChatService(super.webrtc, super.prekey);

  /// Die eingehenden Textnachrichten.
  final StreamController<String> eingang = StreamController<String>.broadcast();

  /// Die eingehenden Binärdaten (Bilder, Sprache).
  final StreamController<
    ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
  >
  binaer =
      StreamController<
        ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
      >.broadcast();

  /// Die Anruf-Signalisierung.
  final StreamController<Map<String, dynamic>> anruf =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Die Probleme beim Verbindungsaufbau.
  final StreamController<String> probleme =
      StreamController<String>.broadcast();

  /// Der Zustand des Datenkanals.
  final StreamController<RTCDataChannelState> zustand =
      StreamController<RTCDataChannelState>.broadcast();

  /// Der ICE-Zustand.
  final StreamController<RTCIceConnectionState> ice =
      StreamController<RTCIceConnectionState>.broadcast();

  /// Der Fehler, mit dem [connect] scheitern soll (null = alles gut).
  String? verbindungsFehler;

  /// Wie oft wurde die Verbindung aufgebaut?
  int verbindungen = 0;

  /// Die gesendeten Anruf-Meldungen (z. B. "decline").
  final List<Map<String, dynamic>> anrufMeldungen = <Map<String, dynamic>>[];

  @override
  Stream<String> get incomingMessages => eingang.stream;

  @override
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
  get incomingBinary => binaer.stream;

  @override
  Stream<Map<String, dynamic>> get callControl => anruf.stream;

  @override
  Stream<String> get problems => probleme.stream;

  @override
  Stream<RTCDataChannelState> get connectionState => zustand.stream;

  @override
  Stream<RTCIceConnectionState> get iceConnectionState => ice.stream;

  @override
  bool get isConnected => false;

  @override
  bool get isDataChannelOpen => false;

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    verbindungen++;
    final fehler = verbindungsFehler;
    if (fehler != null) throw StateError(fehler);
  }

  @override
  Future<void> sendCallControl(Map<String, dynamic> payload) async {
    anrufMeldungen.add(payload);
  }

  @override
  Future<void> dispose() async {
    await eingang.close();
    await binaer.close();
    await anruf.close();
    await probleme.close();
    await zustand.close();
    await ice.close();
    await super.dispose();
  }
}

/// Der eigene Chat-Aufbau (das Ergebnis eines Testlaufs).
class _Aufbau {
  _Aufbau({required this.notifier, required this.match, required this.p2p});

  final ChatNotifier notifier;
  final Match match;
  final _FakeP2PChatService p2p;
}

/// Ein winziges PNG (1x1 Pixel) - ein echtes Bild, das der Decoder liest.
final List<int> _kleinesPng = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99,
  0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

void main() {
  late FakeSupabaseServer server;
  late supabase.SupabaseClient stimmungsClient;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    mockAufnahme();
    mockAudioPlayer();
    mockZeitzone();
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
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.zeilen.clear();
    // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
    // Client schlägt der Aufbau fehl.
    stimmungsClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
  });

  tearDown(() async {
    await stimmungsClient.dispose();
  });

  /// Baut den Chat-Bildschirm.
  ///
  /// [serverMatch] ist der Funke, den der Server kennt (null = der
  /// Server kennt keinen). [vorstellung] ist die Vorstellung des
  /// Partners. [verbindungsFehler] lässt den Verbindungsaufbau
  /// scheitern.
  Future<_Aufbau> baue(
    WidgetTester tester, {
    String matchId = '7',
    bool alsServerFunke = true,
    Map<String, dynamic>? serverMatch,
    String? vorstellung,
    String? verbindungsFehler,
  }) async {
    // GROSS GENUG: Das komplette "mehr"-Menü hat viele Einträge - bei
    // kleiner Höhe liegt der letzte außerhalb des Bildschirms.
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final speicher = _Speicher();
    // Der Hinweis auf den Chat-Hintergrund kommt beim ersten Chat - im
    // Test stört er nur, also ist er als "gesehen" markiert.
    speicher.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
    );

    // DER SERVER-FUNKE: Die Antwort muss VOR dem Aufbau da sein - der
    // Bildschirm holt sie beim Start (das Match wiederherstellen, die
    // Herzensstärken, die Löschungen).
    if (serverMatch != null) {
      server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[
        serverMatch,
      ];
    }

    final service = ChatService();
    final partner = UserProfile(
      id: 'partner-1',
      name: 'Mira',
      bio: '',
      birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
      introText: vorstellung ?? '',
    );
    final match = alsServerFunke
        ? service.restoreServerMatch(matchId, partner, DateTime.now())!
        : service.createMatch(partner);
    final notifier = ChatNotifier(service);
    late _FakeP2PChatService p2p;

    final router = GoRouter(
      initialLocation: '/chat/$matchId',
      routes: <RouteBase>[
        GoRoute(
          path: '/chat/:matchId',
          builder: (ctx, state) =>
              ChatDetailScreen(matchId: state.pathParameters['matchId']!),
        ),
        // DIE PLATZHALTER: Der Bildschirm navigiert nach "/interessen",
        // zu den Fragensammlungen, zum Profil und ins Quiz.
        GoRoute(
          path: '/interessen',
          builder: (ctx, state) => const Scaffold(body: Text('Interessen')),
        ),
        GoRoute(
          path: '/spice/:matchId',
          builder: (ctx, state) => const Scaffold(body: Text('Fragensammlung')),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (ctx, state) => const Scaffold(body: Text('Profil')),
        ),
        GoRoute(
          path: '/safety-center',
          builder: (ctx, state) =>
              const Scaffold(body: Text('Sicherheitscenter')),
        ),
        GoRoute(
          path: '/quiz/:matchId',
          builder: (ctx, state) => const Scaffold(body: Text('Quiz')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(speicher),
          secureProfileStoreProvider.overrideWithValue(_SpeicherFuerProfile()),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(speicher, _SpeicherFuerProfile());
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: 'Hallo',
                birthDate: DateTime(1995, 6, 1),
              ),
            );
            return notifier;
          }),
          moodServiceProvider.overrideWithValue(MoodService(stimmungsClient)),
          chatProvider.overrideWith((ref) => notifier),
          p2pChatServiceProvider.overrideWith((ref) {
            p2p = _FakeP2PChatService(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            );
            p2p.verbindungsFehler = verbindungsFehler;
            ref.onDispose(p2p.dispose);
            return p2p;
          }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Die echte Ereignisschleife: der Server liefert das Profil, den
    // Server-Funke und die Löschungen.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    // NOCH EIN FRAME: Ein Dialog oder eine neue Seite liegt für einen
    // Frame auf der Seite (der Hero-Controller misst erst die Größen) -
    // erst danach ist sie sichtbar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return _Aufbau(notifier: notifier, match: match, p2p: p2p);
  }

  /// Der Server-Funke, den der Chat kennt.
  Map<String, dynamic> serverFunke({
    int matchId = 7,
    String kind = 'spark',
    bool mitFreunde = false,
  }) {
    return <String, dynamic>{
      'matchId': matchId,
      'status': 'active',
      'kind': kind,
      'createdAt': DateTime.now().toIso8601String(),
      'profile': <String, dynamic>{
        'id': 'partner-1',
        'name': 'Mira',
        'bio': 'Liest gern',
      },
    };
  }

  group('Der direkte Kanal (Bilder und Sprache)', () {
    testWidgets('ein Bild aus dem Kanal landet im Verlauf', (tester) async {
      final aufbau = await baue(tester);

      // DER PARTNER schickt ein Bild (über den direkten Kanal).
      aufbau.p2p.binaer.add((
        data: Uint8List.fromList(_kleinesPng),
        contentType: 'image/jpeg',
        metadata: null,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      final bilder = aufbau.notifier
          .messagesFor(aufbau.match.id)
          .where((m) => m.type == MessageType.image)
          .toList();
      expect(
        bilder,
        hasLength(1),
        reason:
            'Ein Bild ueber den direkten Kanal muss im Verlauf stehen - es '
            'kommt nicht ueber den Server.',
      );
      // Das Bild kommt als Daten-URL an (so wird es auch angezeigt).
      expect(bilder.first.mediaUrl, startsWith('data:image/jpeg;base64,'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('eine Sprachnachricht aus dem Kanal landet im Verlauf', (
      tester,
    ) async {
      final aufbau = await baue(tester);

      aufbau.p2p.binaer.add((
        data: Uint8List.fromList(<int>[1, 2, 3, 4]),
        contentType: 'audio/mp4',
        metadata: <String, dynamic>{'durationSeconds': 7},
      ));
      // DER ECHTE DATEIZUGRIFF: Die Sprachbytes werden in eine Datei
      // geschrieben - das geht nur außerhalb der Test-Uhr.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(tester.takeException(), isNull);
      final stimmen = aufbau.notifier
          .messagesFor(aufbau.match.id)
          .where((m) => m.type == MessageType.voice)
          .toList();
      expect(
        stimmen,
        hasLength(1),
        reason:
            'Eine Sprachnachricht ueber den direkten Kanal muss im Verlauf '
            'stehen - sonst hoert der Nutzer die Antwort nicht.',
      );
      expect(stimmen.first.durationSeconds, 7);
      expect(stimmen.first.mediaUrl, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der eingehende Anruf', () {
    testWidgets('der Anruf-Screen geht auf', (tester) async {
      final aufbau = await baue(tester);

      // DER PARTNER ruft an.
      aufbau.p2p.anruf.add(<String, dynamic>{
        'type': 'invite',
        'callId': 'call-1',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // NOCH EIN FRAME: Der Hero-Controller legt die neue Route für
      // einen Frame auf die Seite (bis er die Größen kennt) - erst
      // danach ist der Anruf-Screen sichtbar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CallScreen),
        findsOneWidget,
        reason:
            'Ein Anruf muss den Anruf-Screen oeffnen - sonst sieht der '
            'Nutzer den Anruf nicht.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('ohne callId passiert nichts', (tester) async {
      final aufbau = await baue(tester);

      // Eine kaputte Einladung (ohne callId) darf keinen "Geister-Anruf"
      // öffnen.
      aufbau.p2p.anruf.add(<String, dynamic>{'type': 'invite'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(CallScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der Wechsel des Identity-Keys', () {
    testWidgets('die App fragt nach, statt es still zu akzeptieren', (
      tester,
    ) async {
      // Der Peer hat seinen Schlüssel gewechselt.
      await baue(
        tester,
        serverMatch: serverFunke(),
        verbindungsFehler: 'peer_identity_changed',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.safetyChangedTitle')),
        findsOneWidget,
        reason:
            'Ein neuer Identity-Key muss bestaetigt werden - ein stilles '
            'Akzeptieren waere ein Mittelaengriff.',
      );

      // Und der Dialog lässt sich ablehnen (der Nutzer will erst
      // vergleichen, nicht einfach bestätigen).
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.safetyChangedCancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('das Bestaetigen baut die Verbindung neu auf', (tester) async {
      // Der Peer hat seinen Schlüssel gewechselt.
      await baue(
        tester,
        serverMatch: serverFunke(),
        verbindungsFehler: 'peer_identity_changed',
      );

      expect(
        find.text(L10n.tWithoutContext('chat.safetyChangedTitle')),
        findsOneWidget,
      );

      // Der Nutzer bestätigt den neuen Schlüssel.
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.safetyChangedAccept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der zweite Versuch scheitert auch - dann sagt die App das dem
      // Nutzer, statt es zu verschweigen.
      expect(
        find.textContaining(L10n.tWithoutContext('chat.reconnectStillFailing')),
        findsOneWidget,
        reason:
            'Wenn der neue Aufbau auch scheitert, muss der Nutzer das '
            'wissen - sonst schreibt er ins Leere.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Die Diagnose', () {
    testWidgets('das Problem beim Aufbau steht in der Karte', (tester) async {
      final aufbau = await baue(tester);

      // Das Problem kommt aus dem WebRTC-Dienst.
      aufbau.p2p.probleme.add(
        'Das Senden der Signalisierung ist fehlgeschlagen',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);

      // Die Karte aufklappen - dort steht die technische Diagnose.
      final hinweis = find.text(L10n.tWithoutContext('chat.relayBannerShort'));
      await tester.ensureVisible(hinweis);
      await tester.pump();
      await tester.tap(hinweis);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Das Senden der Signalisierung ist fehlgeschlagen'),
        findsWidgets,
        reason:
            'Der letzte Fehler muss sichtbar sein - nur so weiss der '
            'Nutzer (und der Support), wo der Aufbau haengt.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Das Partnerprofil', () {
    testWidgets('es wird vom Server nachgeladen', (tester) async {
      // Der Server kennt das Profil des Partners.
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'partner-1',
        'name': 'Mira vom Server',
        'bio': 'Liest gern',
      };

      await baue(tester, serverMatch: serverFunke());

      expect(tester.takeException(), isNull);
      // Der Name aus dem Server steht in der Kopfzeile.
      expect(
        find.textContaining('Mira vom Server'),
        findsWidgets,
        reason:
            'Das Profil des Partners muss vom Server kommen - lokal steht '
            'oft nur ein Platzhalter.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Die Karten ueber dem Verlauf', () {
    testWidgets('die Erinnerungs-Karte steht da und laesst sich wegklicken', (
      tester,
    ) async {
      await baue(tester, serverMatch: serverFunke());

      expect(tester.takeException(), isNull);
      // Der Moment (der Tag des Funkens) steht als Karte da.
      expect(
        find.textContaining(L10n.tWithoutContext('milestone.title')),
        findsOneWidget,
        reason:
            'Ein anstehender Erinnerungs-Moment muss sichtbar sein - er '
            'erinnert an den Tag, an dem der Funke entstand.',
      );

      // Und er lässt sich wegklicken (der Hinweis ist nicht aufdringlich).
      final karte = find.ancestor(
        of: find.textContaining(L10n.tWithoutContext('milestone.title')),
        matching: find.byType(Card),
      );
      final knopf = find.descendant(
        of: karte,
        matching: find.byTooltip(L10n.tWithoutContext('milestone.dismiss')),
      );
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(L10n.tWithoutContext('milestone.title')),
        findsNothing,
        reason: 'Nach dem Wegklicken kommt die Karte nicht wieder.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('der Freunde-Badge steht da', (tester) async {
      await baue(tester, serverMatch: serverFunke(kind: 'friends'));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('friends.badge')),
        findsOneWidget,
        reason:
            'Wer nach Freundschaften sucht, soll das sehen - sonst '
            'verwechselt die Person den Chat-Zweck.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('die Vorstellung des Partners steht da', (tester) async {
      await baue(
        tester,
        vorstellung: 'Ich bin Mira und mag lange Spaziergänge',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Ich bin Mira'),
        findsOneWidget,
        reason:
            'Die Vorstellung hilft beim Kennenlernen - sie soll im Chat '
            'stehen, nicht nur im Profil.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Das Menue', () {
    testWidgets('der Kontext-Eisbrecher laesst sich umschalten', (
      tester,
    ) async {
      await baue(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Der Eintrag bietet das ABSCHALTEN an (der Eisbrecher ist von
      // Haus aus an).
      final eintrag = find.text(L10n.tWithoutContext('chat.icebreakerOff'));
      await tester.ensureVisible(eintrag);
      await tester.pump();
      await tester.tap(eintrag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Und danach bietet das Menü das Anschalten an (das Menü wird
      // nach der Auswahl geschlossen - also wieder öffnen).
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(L10n.tWithoutContext('chat.icebreakerOn')),
        findsOneWidget,
        reason:
            'Der Schalter muss den Zustand zeigen - sonst weiss der Nutzer '
            'nicht, ob der Eisbrecher an ist.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('der Titel fuehrt zum Profil des Partners', (tester) async {
      await baue(tester);

      // Der Name in der Kopfzeile ist der Weg zum Profil.
      await tester.tap(find.text('Mira'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Profil'),
        findsOneWidget,
        reason:
            'Der Name in der Kopfzeile muss zum Profil fuehren - das ist der '
            'schnellste Weg, mehr ueber die Person zu erfahren.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
