// Das Signaling über den echten Realtime-Kanal.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/services/chat/webrtc_service.dart über 130 offene Zeilen - der
// größte Rest. Die Ursache: Der Dienst holt seinen Kanal über
// `Supabase.instance.client.channel(...)` und wartet auf die
// Bestätigung des Servers. Ohne Server bleibt der Kanal 15 Sekunden im
// Zustand "joining" - also war genau der sicherheitskritische Teil
// (Kanal, Einladung, eingehende Nachricht, Fehlerfall) nicht prüfbar.
//
// DER WEG: Der [FakeRealtimeServer] spricht das Phoenix-Protokoll des
// Realtime-Clients. Der Test sieht damit,
//   * was die App über den Kanal schickt (das Angebot, die Antwort,
//     den ICE-Kandidaten, den Relay-Ping),
//   * dass eine eingehende Nachricht wirklich bei der App ankommt,
//   * und was passiert, wenn kein Server erreichbar ist.
//
// DIE NAHTEN (unverändert in lib/): `peerConnectionFactory` liefert die
// PeerConnection-Attrappe, `routeSignalingForTesting` und
// `currentPeerIdForTesting` bleiben für die anderen Tests da.
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

/// Die PeerConnection, die zusätzlich mitzählt, was der Dienst
/// mit ihr macht.
///
/// DER WEG: Die Attrappe aus test/support/fake_webrtc.dart schluckt
/// alles - für den Test muss aber sichtbar sein, OB der Dienst die
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

  /// Der Dienst hat einen ICE-Kandidaten gefunden (der Weg über den
  /// Kanal in die andere Richtung).
  void meldeKandidat(RTCIceCandidate kandidat) {
    onIceCandidate?.call(kandidat);
  }

  /// Die ICE-Verbindung ist verloren gegangen.
  void verliere() {
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateFailed,
    );
  }

  /// Die ICE-Verbindung wurde geschlossen.
  void schliesse() {
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateClosed,
    );
  }
}

/// Wartet, bis [bedingung] wahr ist (oder die Zeit abgelaufen ist).
///
/// DER GRUND: Der Weg über den Kanal läuft über mehrere asynchrone
/// Schritte (Socket, Join, Broadcast). Ein fester Sleep wäre wackelig -
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
  /// DER WEG: Die Attrappe zählt nur das Anlegen des Datenkanals -
  /// beim Empfänger (Antwort auf ein Angebot) wird aber gar keiner
  /// geöffnet. Der Zähler sitzt deshalb am Aufruf der Fabrik.
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

    // HIVE: der Verschlüsselungs-Dienst öffnet seine Boxen - ohne
    // initialisiertes Hive schlägt der Aufbau fehl.
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
    // ws://127.0.0.1:PORT/realtime/v1/websocket.
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
    // DIE SITZUNG: In der App ist immer ein Konto angemeldet - nur dann
    // trägt der Join das User-Token (sonst verweigert die RLS-Policy
    // den Beitritt zum privaten Kanal).
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
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

    test('der Join traegt das Token des Kontos', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      final join = server.empfangeneFrames.firstWhere(
        (frame) => frame['event'] == 'phx_join',
      );
      final nutzlast = join['payload'] as Map<String, dynamic>;
      expect(
        nutzlast['access_token'],
        isNotNull,
        reason:
            'Der Join braucht das User-Token - ohne ihn verweigert die '
            'RLS-Policy den Beitritt zum privaten Kanal.',
      );
    });

    test('das Angebot geht ueber den Kanal raus', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      await dienst.createOffer('partner-1');

      // DER WEG ÜBER DEN KANAL ist asynchron: das Senden wird nicht
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
      // und ohne neue Sitzung wiederholt werden können.
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
          'gen': 7,
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
      expect(
        server.broadcastsMitArt('answer').first['gen'],
        7,
        reason:
            'Die Nummer des Angebots muss in der Antwort wiederkehren - '
            'sonst haelt der Absender die Antwort fuer veraltet.',
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

    test('eine Antwort zu einem alten Angebot wird verworfen', () async {
      // DER GRUND (06.11.2026): Nach einem Retry gehört eine noch
      // fliegende ALTE Antwort zur hinweggelegten PeerConnection - sie
      // darf die neue nicht setzen, sonst wird die echte Antwort
      // verworfen und die Verbindung ist unreparierbar.
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
      await dienst.createOffer('partner-1');
      await warteAuf(() => server.broadcastsMitArt('offer').isNotEmpty);

      server.sendeBroadcast(
        topic: server.beigetreteneTopics.last,
        event: 'signal',
        nutzlast: <String, dynamic>{
          'type': 'broadcast',
          'event': 'signal',
          'kind': 'answer',
          'from': 'partner-1',
          'sdp': 'v=0\r\no=- 3 3 IN IP4 127.0.0.1',
          'gen': 99,
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        peer.remoteBeschreibungen,
        isEmpty,
        reason:
            'Eine Antwort zu einem alten Angebot darf die aktuelle '
            'Verbindung nicht setzen.',
      );
    });

    test('eine kaputte Nachricht bringt den Dienst nicht um', () async {
      // DER ANGRIFF: 'from' ist keine Text, sondern eine Zahl. Der
      // Dienst darf daran nicht sterben - er muss weiterlaufen.
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');

      server.sendeBroadcast(
        topic: server.beigetreteneTopics.last,
        event: 'signal',
        nutzlast: <String, dynamic>{
          'type': 'broadcast',
          'event': 'signal',
          'kind': 'offer',
          'from': 42,
          'sdp': 'v=0',
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        verbindungen,
        0,
        reason: 'Eine kaputte Nachricht darf keine Verbindung aufbauen.',
      );
      expect(dienst.isConnected, isFalse);
    });

    test('eine fremde Nachricht wird verworfen', () async {
      // DER ANGRIFF (Audit H8): Ein Angreifer schickt ein Angebot mit
      // seinem 'from' - er würde sonst zum Partner.
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
      final probleme = <String>[];
      final abo = dienst.problems.listen(probleme.add);
      addTearDown(abo.cancel);

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
      expect(
        probleme.any((text) => text.contains('fremde')),
        isTrue,
        reason:
            'Der Nutzer muss sehen, dass eine fremde Nachricht kam - '
            'sonst haelt er die Verbindung fuer ruhig.',
      );
    });
  });

  group('Der ICE-Zustand', () {
    test('ein Kandidat geht ueber den Kanal raus', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
      await dienst.createOffer('partner-1');

      expect(
        dienst.isDataChannelOpen,
        isTrue,
        reason:
            'Der Datenkanal muss offen sein - der Anruf-Invite wartet '
            'darauf und scheitert sonst sofort.',
      );

      peer.meldeKandidat(
        RTCIceCandidate(
          'candidate:1 1 udp 2130706431 192.168.1.2 54321 typ host',
          '0',
          0,
        ),
      );

      expect(
        await warteAuf(() => server.broadcastsMitArt('ice').isNotEmpty),
        isTrue,
        reason:
            'Der Kandidat muss zum Partner - ohne ihn finden sich die '
            'Geraete nicht.',
      );
      final kandidaten = server.broadcastsMitArt('ice');
      expect(kandidaten.first['from'], 'user-1');
      expect(kandidaten.first['sdpMid'], '0');
    });

    test('ein verlorener Zustand beendet die Verbindung', () async {
      await dienst.connect(myUserId: 'user-1', peerId: 'partner-1');
      await dienst.createOffer('partner-1');
      final zustaende = <RTCIceConnectionState>[];
      final abo = dienst.iceConnectionState.listen(zustaende.add);
      addTearDown(abo.cancel);

      peer.verliere();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(dienst.isConnected, isFalse);
      expect(dienst.lastIceConnectionState, isNotNull);
      expect(zustaende, isNotEmpty, reason: 'Die App muss den Zustand sehen.');

      // UND DER GESCHLOSSENE KANAL: Auch der Zustand "geschlossen" muss
      // die Verbindung beenden - sonst zeigt die App weiterhin
      // "verbunden", obwohl der Kanal tot ist.
      peer.schliesse();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(dienst.isConnected, isFalse);
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

  group('Der Dienst', () {
    test('er bietet alle Straeme an', () {
      // DIE API: Die Bildschirme lauschen auf diesen Strömen - fehlt
      // einer, wartet der Bildschirm vergeblich auf seine Nachricht.
      expect(dienst.incomingMessages, isNotNull);
      expect(dienst.incomingBinary, isNotNull);
      expect(dienst.callControl, isNotNull);
      expect(dienst.callAudio, isNotNull);
      expect(dienst.connectionState, isNotNull);
      expect(dienst.iceConnectionState, isNotNull);
      expect(dienst.problems, isNotNull);
      expect(dienst.relayPing, isNotNull);
    });
  });
}
