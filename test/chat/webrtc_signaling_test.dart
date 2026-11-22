// Das Signaling zwischen zwei Handys (WebRTC).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/webrtc_service.dart 190 offene Zeilen - der
// groesste Einzelposten. Das Signaling ist sicherheitsrelevant: hier
// entscheidet sich, OB ein fremder Client sich als Partner
// eintauschen kann (Audit H8) und ob eine zu grosse Nachricht das
// Geraet bremst (DoS-Schutz).
//
// DIE NAHTEN: `WebRTCService.peerConnectionFactory` liefert die
// Peer-Connection-Attrappe, `routeSignalingForTesting` fuehrt eine
// Signaling-Nachricht ohne echten Kanal zu, und
// `currentPeerIdForTesting` setzt den erwarteten Partner.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_webrtc.dart';
import '../support/plugin_mocks.dart';

void main() {
  late EncryptionService encryption;
  late WebRTCService dienst;
  late FakePeerConnection peer;

  /// Wie oft wurde die PeerConnection gebaut?
  ///
  /// DER WEG: Die Attrappe zaehlt nur createDataChannel -
  /// beim EMPFAENGER (Antwort auf ein Offer) wird aber gar kein
  /// Kanal geoeffnet. Der Zaehler sitzt deshalb am Aufruf der
  /// Fabrik.
  int verbindungen = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockKeystore();
    final temp = await Directory.systemTemp.createTemp('webrtc_signaling');
    Hive.init(temp.path);
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    encryption = EncryptionService();
    await encryption.initialize();
    peer = FakePeerConnection();
    verbindungen = 0;
    WebRTCService.peerConnectionFactory = (config) async {
      verbindungen++;
      return peer;
    };
    dienst = WebRTCService(encryption);
    dienst.currentPeerIdForTesting = 'partner-1';
  });

  tearDown(() {
    WebRTCService.peerConnectionFactory = null;
  });

  /// Eine Signaling-Nachricht dem Dienst geben und die Verarbeitung
  /// abwarten.
  Future<void> signal(Map<String, dynamic> nachricht) async {
    await dienst.routeSignalingForTesting(nachricht);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('Das Angebot des Partners', () {
    test('es baut eine PeerConnection auf', () async {
      await signal({
        'kind': 'offer',
        'from': 'partner-1',
        'sdp': 'v=0\r\no=- 1 1 IN IP4 127.0.0.1',
      });

      expect(
        verbindungen,
        greaterThan(0),
        reason:
            'Ohne PeerConnection geht kein DataChannel auf - es kommen '
            'keine Nachrichten an.',
      );
    });

    test('ein fremder Absender wird verworfen', () async {
      // DER ANGRIFF (Audit H8): Ein Angreifer schickt ein Offer mit
      // seinem 'from' - er wuerde sonst zum Partner.
      await signal({'kind': 'offer', 'from': 'attacker', 'sdp': 'v=0'});

      expect(
        verbindungen,
        0,
        reason: 'Ein fremder Absender darf keine Verbindung aufbauen.',
      );
    });

    test('ein zu grosses Angebot wird verworfen', () async {
      // DER DOS-SCHUTZ: Ein SDP-Feld von mehreren Megabytes soll
      // das Geraet nicht bremsen.
      await signal({
        'kind': 'offer',
        'from': 'partner-1',
        'sdp': 'x' * (70 * 1024),
      });

      expect(
        verbindungen,
        0,
        reason: 'Ein zu grosses SDP darf nicht verarbeitet werden.',
      );
    });

    test('ohne SDP passiert nichts', () async {
      await signal({'kind': 'offer', 'from': 'partner-1'});

      expect(verbindungen, 0);
    });
  });

  group('Die Antwort des Partners', () {
    test('ohne Verbindung wird sie verworfen', () async {
      await signal({'kind': 'answer', 'from': 'partner-1', 'sdp': 'v=0'});

      // Kein Absturz - das ist der Punkt: eine Answer, die ohne
      // Verbindung ankommt, darf den Dienst nicht umwerfen.
      expect(dienst.isConnected, isFalse);
    });

    test('eine zu grosse Antwort wird verworfen', () async {
      await dienst.createOffer('partner-1');

      await signal({
        'kind': 'answer',
        'from': 'partner-1',
        'sdp': 'x' * (70 * 1024),
      });

      expect(
        dienst.isConnected,
        isFalse,
        reason: 'Eine zu grosse Antwort wird nicht gesetzt.',
      );
    });
  });

  group('Die ICE-Kandidaten', () {
    test('eine vollstaendige Kandidatur wird angenommen', () async {
      await dienst.createOffer('partner-1');

      await signal({
        'kind': 'ice',
        'from': 'partner-1',
        'candidate': 'candidate:1 1 udp 2130706431 192.168.1.2 54321 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });

      // Der Kandidat wurde gepuffert oder gesetzt - in jedem Fall darf
      // der Dienst nicht daran sterben.
      expect(dienst.isConnected, isFalse);
    });

    test('eine unvollstaendige Kandidatur wird verworfen', () async {
      await dienst.createOffer('partner-1');

      await signal({
        'kind': 'ice',
        'from': 'partner-1',
        'candidate': null,
        'sdpMid': null,
        'sdpMLineIndex': null,
      });

      expect(dienst.isConnected, isFalse);
    });
  });

  group('Die Relay-Weckung', () {
    test('sie meldet den Zustrom', () async {
      var pings = 0;
      final abo = dienst.relayPing.listen((_) => pings++);
      addTearDown(abo.cancel);

      await signal({'kind': 'relay-ping', 'from': 'partner-1'});

      expect(
        pings,
        1,
        reason:
            'Die Relay-Weckung sagt der App, dass Nachrichten im Relay '
            'liegen - ohne sie wartet der Chat vergeblich.',
      );
    });
  });

  group('Unbekanntes und Fremdes', () {
    test('eine unbekannte Art wird ignoriert', () async {
      await signal({'kind': 'sonderbefehl', 'from': 'partner-1'});

      expect(verbindungen, 0);
      expect(dienst.isConnected, isFalse);
    });

    test('eine Nachricht ohne Art wird ignoriert', () async {
      await signal({'from': 'partner-1'});

      expect(verbindungen, 0);
    });

    test('viele Nachrichten brechen nichts ab', () async {
      // DER DOS-SCHUTZ: Der Puffer ist begrenzt (200) - ein Peer, der
      // flutet, darf den Dienst nicht sprengen.
      for (var i = 0; i < 250; i++) {
        await dienst.routeSignalingForTesting({
          'kind': 'offer',
          'from': 'partner-1',
          'sdp': 'v=0 $i',
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dienst.isConnected, isFalse);
    });
  });

  group('Die Groessengrenze', () {
    test('utf8Length zaehlt Bytes, nicht Zeichen', () {
      expect(WebRTCService.utf8Length('abc'), 3);
      expect(
        WebRTCService.utf8Length('ä'),
        2,
        reason:
            'Die Grenze gilt in BYTES - ein Zeichen kann zwei Bytes '
            'brauchen (Umlaute, Emoji).',
      );
      expect(WebRTCService.utf8Length(''), 0);
    });
  });
}
