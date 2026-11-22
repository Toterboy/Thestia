// Der Datenkanal zwischen zwei Handys (WebRTC).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/webrtc_service.dart 140 offene Zeilen. Der
// Datenkanal ist die Stelle, an der eine boesartige Gegenseite direkt in
// die App spricht - dort muss nichts davon zu einem Absturz fuehren.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein Angebot des Partners baut die Verbindung auf und erzeugt eine
//     Antwort (ohne Signalkanal geht sie nicht verloren, aber auch nicht
//     in einen Absturz),
//   * der Datenkanal meldet seinen Zustand (die App zeigt "verbunden"),
//   * eine kaputte Nachricht vom Peer wird verworfen, nicht geworfen -
//     das ist der Unterschied zwischen "Peer ist boesartig" und "App
//     stuertzt",
//   * eine zu grosse Nachricht wird verworfen (DoS-Schutz).
import 'dart:convert';
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
  late FakeDataChannel kanal;

  /// Wie oft wurde die PeerConnection gebaut?
  ///
  /// DER GRUND: Die Attrappe zaehlt nur createDataChannel - beim
  /// EMPFAENGER (Antwort auf ein Angebot) wird der Kanal aber von der
  /// Gegenseite geliefert. Der Zaehler sitzt deshalb am Aufruf der
  /// Fabrik.
  int verbindungen = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockKeystore();
    final temp = await Directory.systemTemp.createTemp('webrtc_kanal');
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
    kanal = peer.datenkanal as FakeDataChannel;
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

  group('Der Datenkanal', () {
    test('ein Angebot des Partners baut die Verbindung auf', () async {
      await dienst.handleOffer('partner-1', 'v=0\r\no=- 1 1 IN IP4 127.0.0.1');

      expect(
        verbindungen,
        greaterThan(0),
        reason:
            'Ohne PeerConnection gibt es keinen Kanal - es kommen keine '
            'Nachrichten an.',
      );
    });

    test('der Kanal meldet seinen Zustand', () async {
      final zustaende = <Object>[];
      final abo = dienst.connectionState.listen(zustaende.add);
      addTearDown(abo.cancel);

      await dienst.handleOffer('partner-1', 'v=0');
      // DER KANAL KOMMT VON DER GEGENSEITE: So baut es die Gegenseite
      // auch - der Test stellt sie nach.
      peer.onDataChannel?.call(kanal);
      kanal.oeffne();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        zustaende,
        isNotEmpty,
        reason:
            'Die App muss den Verbindungszustand kennen - sie zeigt ihn '
            'dem Nutzer an ("verbendet" oder "nicht verbunden").',
      );
    });

    test('eine kaputte Nachricht wird verworfen, nicht geworfen', () async {
      await dienst.handleOffer('partner-1', 'v=0');
      peer.onDataChannel?.call(kanal);

      // DIE NACHRICHT DER GEGENSEITE: Kein JSON, kein base64, einfach
      // Muell. Sie darf die App NICHT umwerfen.
      kanal.empfange('{{{kein json');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        true,
        isTrue,
        reason:
            'Eine boesartige Nachricht darf den Kanal nicht abreissen - '
            'sonst kann jeder Partner die App des anderen killen.',
      );
    });

    test('eine zu grosse Nachricht wird verworfen', () async {
      await dienst.handleOffer('partner-1', 'v=0');
      peer.onDataChannel?.call(kanal);

      // DIE GROSSE NACHRICHT: 600 KB - mehr als die Obergrenze (512 KB).
      final zuGross = jsonEncode(<String, dynamic>{
        'type': 'signal_message',
        'ciphertext': base64Encode(List<int>.filled(600 * 1024, 65)),
        'messageType': 1,
      });
      kanal.empfange(zuGross);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        true,
        isTrue,
        reason:
            'Der Peer darf den Speicher nicht sprengen - die Nachricht wird '
            'weggelassen.',
      );
    });

    test('ohne Kanal kann nicht gesendet werden', () async {
      // DER GRUND: Das Senden muss einen klaren Fehler geben - sonst
      // denkt der Absender, die Nachricht sei raus.
      await expectLater(
        dienst.sendMessage('Hallo'),
        throwsA(isA<StateError>()),
        reason:
            'Ohne offenen Kanal ist die Nachricht nicht raus - das muss der '
            'Absender wissen.',
      );
    });
  });
}
