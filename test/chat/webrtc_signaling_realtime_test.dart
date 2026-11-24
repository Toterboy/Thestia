// Das Signaling ueber den echten Realtime-Kanal.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/webrtc_service.dart 130 offene Zeilen - der groesste
// Rest. Die Ursache: Der Dienst holt seinen Kanal ueber
// `Supabase.instance.client.channel(...)` und wartet auf die
// Bestaetigung des Servers. Ohne Server bleibt der Kanal 15 Sekunden im
// Zustand "joining" - also war genau der sicherheitskritische Teil
// (Kanal, Einladung, eingehende Nachricht, Fehlerfall) nicht pruefbar.
//
// DER WEG: Der [FakeRealtimeServer] spricht das Phoenix-Protokoll des
// Realtime-Clients. Der Test sieht damit,
//   * was die App ueber den Kanal schickt (das Angebot, die Antwort),
//   * dass eine eingehende Nachricht wirklich bei der App ankommt,
//   * und was passiert, wenn kein Server erreichbar ist.
//
// DIE NAHTEN (unveraendert in lib/): `peerConnectionFactory` liefert die
// PeerConnection-Attrappe, `routeSignalingForTesting` und
// `currentPeerIdForTesting` bleiben fuer die anderen Tests da.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_realtime_server.dart';
import '../support/fake_supabase_server.dart';
import '../support/fake_webrtc.dart';
import '../support/plugin_mocks.dart';

/// Die PeerConnection, die zusaetzlich mitzaehlt, was der Dienst
/// mit ihr macht.
///
/// DER WEG: Die Attrappe aus test/support/fake_webrtc.dart schluckt
/// alles - fuer den Test muss aber sichtbar sein, OB der Dienst die
/// Antwort gesetzt und den ICE-Kandidaten nachgereicht hat.
class _AufzeichnendeVerbindung extends FakePeerConnection {
  _AufzeichnendeVerbindung();

  /// Die gesetzten Remote-Beschreibungen (in der Reihenfolge).
  final List<RTCSessionDescription> remoteBeschreibungen =
      <RTCSessionDescription>[];

  /// Die nachgereichten ICE-Kandidaten (in der Reihenfolge).
  final List<RTCIceCandidate> kandidaten = <RTCIceCandidate>[];

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteBeschreibungen.add(description);
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    kandidaten.add(candidate);
  }
}

/// Wartet, bis [bedingung] wahr ist (oder die Zeit abgelaufen ist).
///
/// DER GRUND: Der Weg ueber den Kanal laeuft ueber mehrere asynchrone
/// Schritte (Socket, Join, Broadcast). Ein fester Sleep waere wackelig -
/// der Test wartet darum auf das ERGEBNIS.
Future<bool> warteAuf(
  bool Function() bedingung, {
  Duration hoechstens = const Duration(seconds: 5),
}) async {
  final ende = DateTime.now().add(hoechstens);
  while (DateTime.now().isBefore(ende)) {
    if (bedingung()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return bedingung();
}

void main() {
  late FakeRealtimeServer server;
  late EncryptionService encryption;
  late _AufzeichnendeVerbindung peer;
  late WebRTCService dienst;

  /// Wie oft wurde die PeerConnection gebaut?
  ///
  /// DER WEG: Die Attrappe zaehlt nur das Anlegen des Datenkanals -
  /// beim Empfaenger (Antwort auf ein Angebot) wird aber gar keiner
  /// geoeffnet. Der Zaehler sitzt deshalb am Aufruf der Fabrik.
  int verbindungen = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER ECHTE NETZZUGANG: Das Test-Binding ersetzt den HttpClient
    // durch einen Ersatz, der immer 400 liefert. Der Realtime-Client
    // braucht aber eine echte WebSocket-Verbindung zum Ersatz-Server -
    // deshalb wird der Override entfernt (wie im Live-Test).
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    // HIVE: der Verschluesselungs-Dienst oeffnet seine Boxen - ohne
    // initialisiertes Hive schlaegt der Aufbau fehl.
    final temp = await Directory.systemTemp.createTemp('webrtc_realtime');
    Hive.init(temp.path);
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());

    // DER ERSATZ-SERVER: Der Supabase-Client zeigt auf seinen Port -
    // der Realtime-Client verbindet sich dann mit
    // ws://127.0.0.1:<port>/realtime/v1/websocket.
    server = await FakeRealtimeServer.starten();
    await supabase.Supabase.initialize(
      url: server.url,
      publishableKey: 'test-key',
      httpClient: FakeSupabaseServer(userId: 'ich'),
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  tearDownAll(() async {
    await supabase.Supabase.instance.dispose();
    await server.stoppen();
    await Hive.close();
  });

  setUp(() async {
    server.vergessen();
    server.verbindungVerweigern = false;
    server.joinBeantworten = true;
    encryption = EncryptionService();
    await encryption.initialize();
    peer = _AufzeichnendeVerbindung();
    verbindungen = 0;
    WebRTCService.peerConnectionFactory = (config) async {
      verbindungen++;
      return peer;
    };
    dienst = WebRTCService(encryption);
  });

  tearDown(() async {
    WebRTCService.peerConnectionFactory = null;
    await dienst.dispose();
  });

  group('Der Kanal zum Partner', () {
    test('er verbindet sich mit dem Server', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      expect(
        dienst.hasSignalingChannel,
        isTrue,
        reason:
            'Ohne Kanal laeuft keine Einladung ueber den Kanal - die '
            'Gegenseite wuerde nie erfahren, dass es geht.',
      );
      expect(
        server.beigetreteneTopics,
        contains('realtime:signaling:partner-1:user-1'),
        reason:
            'Der Kanalname muss sortiert unddeterministisch sein - beide '
            'Seiten muessen denselben Kanal finden.',
      );
    });

    test('das Angebot geht ueber den Kanal raus', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      await dienst.createOffer('partner-1');

      // DER WEG UEBER DEN KANAL ist asynchron: das Senden wird nicht
      // abgewartet - der Test wartet deshalb auf das Angebot.
      expect(
        await warteAuf(() => server.broadcastsMitArt('offer').isNotEmpty),
        isTrue,
        reason:
            'Das Angebot MUSS ueber den Kanal gehen - der Peer sieht es '
            'sonst nie und der DataChannel bleibt zu.',
      );
      final angebote = server.broadcastsMitArt('offer');
      final angebot = angebote.first;
      expect(
        angebot['from'],
        'user-1',
        reason:
            'Der Absender ist die EIGENE User-ID - mit der des Partners '
            'kann sich ein Angreifer als Partner ausgeben.',
      );
      expect(angebot['type'], 'broadcast');
      expect(angebot['event'], 'signal');
      expect(angebot['sdp'], isNotNull);
    });

    test('die Relay-Weckung geht ueber den Kanal raus', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      await dienst.sendRelayPing();

      expect(
        await warteAuf(() => server.broadcastsMitArt('relay-ping').isNotEmpty),
        isTrue,
        reason:
            'Ohne Weckung wartet der Empfaenger vergeblich auf die '
            'Nachricht im Relay.',
      );
      final pings = server.broadcastsMitArt('relay-ping');
      expect(pings.first['from'], 'user-1');
    });

    test('ein erneuter Handshake schickt ein zweites Angebot', () async {
      // DER GRUND: Nach einem Timeout muss der Aufbau ohne neuen Kanal
      // und ohne neue Sitzung wiederholt werden koennen.
      await dienst.connect(myUserId: 'aaa-ich', peerId: 'zzz-partner');
      await dienst.createOffer('zzz-partner');
      expect(
        await warteAuf(() => server.broadcastsMitArt('offer').isNotEmpty),
        isTrue,
      );

      await dienst.retryHandshake();

      expect(
        await warteAuf(() => server.broadcastsMitArt('offer').length >= 2),
        isTrue,
        reason:
            'Der Retry muss ein neues Angebot schicken - sonst wartet der '
            'Partner ewig auf eine Antwort.',
      );
    });
  });

  group('Die eingehende Nachricht', () {
    test('sie wird geroutet', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
      var pings = 0;
      final abo = dienst.relayPing.listen((_) => pings++);
      addTearDown(abo.cancel);

      server.sendeBroadcast(
        topic: server.beigetreteneTopics.last,
        event: 'signal',
        nutzlast: <String, dynamic>{
          'type': 'broadcast',
          'event': 'signal',
          'kind': 'relay-ping',
          'from': 'partner-1',
        },
      );

      expect(
        await warteAuf(() => pings > 0),
        isTrue,
        reason:
            'Die Nachricht aus dem Kanal muss bei der App ankommen - '
            'sonst weiss die App nicht, dass der Partner da ist.',
      );
      expect(pings, 1);
    });

    test('ein Angebot des Partners baut die Verbindung auf', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      server.sendeBroadcast(
        topic: server.beigetreteneTopics.last,
        event: 'signal',
        nutzlast: <String, dynamic>{
          'type': 'broadcast',
          'event': 'signal',
          'kind': 'offer',
          'from': 'partner-1',
          'sdp': 'v=0\r\no=- 1 1 IN IP4 127.0.0.1',
        },
      );

      expect(
        await warteAuf(() => verbindungen > 0),
        isTrue,
        reason:
            'Ohne PeerConnection gibt es keinen Datenkanal - es kommen '
            'keine Nachrichten an.',
      );
      expect(
        await warteAuf(() => server.broadcastsMitArt('answer').isNotEmpty),
        isTrue,
        reason:
            'Die Antwort muss zurueck - ohne sie bleibt der Partner auf '
            'seinem Angebot sitzen.',
      );
    });

    test(
      'die Antwort und der ICE-Kandidat des Partners werden uebernommen',
      () async {
        await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
        await dienst.createOffer('partner-1');
        await warteAuf(() => server.broadcastsMitArt('offer').isNotEmpty);

        // DIE ANTWORT ZUERST: Erst danach ist die Remote-Beschreibung
        // gesetzt - dann wird der ICE-Kandidat nicht mehr gepuffert,
        // sondern direkt nachgereicht.
        server.sendeBroadcast(
          topic: server.beigetreteneTopics.last,
          event: 'signal',
          nutzlast: <String, dynamic>{
            'type': 'broadcast',
            'event': 'signal',
            'kind': 'answer',
            'from': 'partner-1',
            'sdp': 'v=0\r\no=- 2 2 IN IP4 127.0.0.1',
          },
        );

        expect(
          await warteAuf(() => peer.remoteBeschreibungen.isNotEmpty),
          isTrue,
          reason:
              'Die Antwort des Partners muss gesetzt werden - sonst bleibt '
              'die Verbindung auf "checking" und es kommen keine Nachrichten '
              'an.',
        );

        server.sendeBroadcast(
          topic: server.beigetreteneTopics.last,
          event: 'signal',
          nutzlast: <String, dynamic>{
            'type': 'broadcast',
            'event': 'signal',
            'kind': 'ice',
            'from': 'partner-1',
            'candidate':
                'candidate:1 1 udp 2130706431 192.168.1.2 54321 typ host',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        );

        expect(
          await warteAuf(() => peer.kandidaten.isNotEmpty),
          isTrue,
          reason:
              'Der ICE-Kandidat muss nachgereicht werden - ein verlorener '
              'Kandidat laesst die Verbindung ewig auf "checking".',
        );
      },
    );

    test('eine fremde Nachricht wird verworfen', () async {
      // DER ANGRIFF (Audit H8): Ein Angreifer schickt ein Angebot mit
      // seinem 'from' - er wuerde sonst zum Partner.
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      server.sendeBroadcast(
        topic: server.beigetreteneTopics.last,
        event: 'signal',
        nutzlast: <String, dynamic>{
          'type': 'broadcast',
          'event': 'signal',
          'kind': 'offer',
          'from': 'attacker',
          'sdp': 'v=0',
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        verbindungen,
        0,
        reason: 'Ein fremder Absender darf keine Verbindung aufbauen.',
      );
    });
  });

  group('Der Fehlerfall', () {
    test('ohne Server bleibt der Aufbau nicht haengen', () async {
      // DER SERVER VERWEIGERT: Der Client darf nicht 15 Sekunden
      // warten - der Nutzer muss eine Meldung bekommen.
      await supabase.Supabase.instance.client.realtime.disconnect();
      server.verbindungVerweigern = true;

      final start = DateTime.now();
      await expectLater(
        dienst.connect(myUserId: 'user-1', peerId: 'partner-1'),
        throwsA(isA<StateError>()),
        reason:
            'Ohne Kanal darf der Aufbau nicht "erfolgreich" sein - die App '
            'wuerde auf eine Verbindung warten, die nie kommt.',
      );
      final dauer = DateTime.now().difference(start);

      expect(
        dauer,
        lessThan(const Duration(seconds: 5)),
        reason:
            'Der Aufbau darf nicht haengen - die 15 Sekunden des Dienstes '
            'sind fuer den Nutzer zu lang.',
      );
      expect(
        dienst.hasSignalingChannel,
        isFalse,
        reason:
            'Nach dem Fehler darf kein toter Kanal zurueckbleiben - der '
            'naechste Versuch muss wieder sauber aufbauen.',
      );
    });
  });
}
