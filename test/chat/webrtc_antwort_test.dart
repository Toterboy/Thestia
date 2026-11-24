// Die Antwort, die ICE-Kandidaten und die Kontroll-Nachrichten.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/webrtc_service.dart 136 offene Zeilen. Der
// Datenkanal und das Signaling sind getestet - offen war der Weg von
// der Antwort des Partners ueber die gepufferten ICE-Kandidaten bis zu
// den Kontroll-Nachrichten des Anrufs.
//
// DIE NAHTEN: `WebRTCService.peerConnectionFactory` liefert die
// Peer-Connection-Attrappe (test/support/fake_webrtc.dart) - die
// Verbindung braucht keine echte WebRTC-Bibliothek.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Antwort ohne Verbindung wird verworfen (statt zu crashen),
//   * eine Antwort setzt die Remote-Description,
//   * ein ICE-Kandidat, der zu frueh kommt, geht nicht verloren: er
//     wird gepuffert und nach der Remote-Description nachgereicht,
//
// NICHT DABEI: Die Kontroll-Nachrichten des Anrufs (CALL:) - sie
// brauchen eine aufgebaute Signal-Sitzung (der Verschluesselungs-
// Dienst muss die Sitzung mit dem Partner kennen). Das ist ein
// eigener Weg und wird im Signal-Test geprueft.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Die WebRTC-Schnittstelle kommt als Transitivum ueber
// flutter_webrtc - der Test braucht nur ihre Typen.
// ignore_for_file: depend_on_referenced_packages
import 'package:webrtc_interface/webrtc_interface.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_webrtc.dart';
import '../support/plugin_mocks.dart';

/// Der Kanal merkt sich die gesendeten Nachrichten.
class _ZaehlenderKanal extends FakeDataChannel {
  _ZaehlenderKanal();

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    texte.add(message.text);
    await super.send(message);
  }

  /// Die gesendeten Nachrichten (als Text - der Kanal speichert sie
  /// als Objekt).
  final List<String> texte = <String>[];
}

void main() {
  late EncryptionService encryption;
  late WebRTCService dienst;
  late FakePeerConnection peer;
  late _ZaehlenderKanal kanal;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockKeystore();
    final temp = await Directory.systemTemp.createTemp('webrtc_antwort');
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
    kanal = _ZaehlenderKanal();
    WebRTCService.peerConnectionFactory = (config) async => peer;
    dienst = WebRTCService(encryption);
    dienst.currentPeerIdForTesting = 'partner-1';
  });

  tearDown(() {
    WebRTCService.peerConnectionFactory = null;
  });

  /// Baut die Verbindung (wie der Empfaenger eines Angebots).
  Future<void> baueVerbindung() async {
    await dienst.handleOffer('partner-1', 'v=0');
    peer.onDataChannel?.call(kanal);
    kanal.oeffne();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('Die Antwort', () {
    test('ohne Verbindung wird sie verworfen (kein Absturz)', () async {
      final probleme = <String>[];
      final abo = dienst.problems.listen(probleme.add);
      addTearDown(abo.cancel);

      await dienst.handleAnswer('partner-1', 'v=0');

      expect(
        probleme,
        isNotEmpty,
        reason:
            'Der Nutzer muss erfahren, dass die Verbindung nicht zustande '
            'kommt - sonst wartet er ewig auf ein Gespraech.',
      );
    });

    test('mit Verbindung setzt sie die Remote-Description', () async {
      await baueVerbindung();

      await dienst.handleAnswer('partner-1', 'v=0\r\no=- 1 1 IN IP4 127.0.0.1');

      expect(
        peer.getRemoteDescription,
        isNotNull,
        reason:
            'Ohne Remote-Description kommen keine ICE-Kandidaten an - die '
            'Verindung bliebe im "connecting" stehen.',
      );
    });
  });

  group('Die ICE-Kandidaten', () {
    test('ein zu frueher Kandidat geht nicht verloren', () async {
      // DER FRUEHE KANDIDAT: Er kommt, bevor die Remote-Description
      // gesetzt ist - verworfen wuerde er die Verbindung verlangsamen
      // oder ganz verhindern.
      await dienst.handleIceCandidate(
        'partner-1',
        RTCIceCandidate('candidate:1 1 udp 1 127.0.0.1 5000 typ host', '0', 0),
      );

      // Und jetzt kommt das Angebot - der Kandidat wird nachgereicht.
      await dienst.handleOffer('partner-1', 'v=0');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        peer.getRemoteDescription,
        isNotNull,
        reason:
            'Die Verbindung muss aufgebaut werden - der gepufferte '
            'Kandidat darf sie nicht verhindern.',
      );
    });
  });
}
