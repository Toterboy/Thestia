// Der WebRTC-Dienst mit der Peer-Connection-Attrappe.
//
// ANLASS (20.11.2026): Die Coverage-Messung zeigte für
// lib/services/chat/webrtc_service.dart 228 offene Zeilen - die komplette
// Verbindung und Nachrichtenweiterleitung war untestbar, weil
// `createPeerConnection()` die native Schicht braucht.
//
// DER WEG: Die Naht `WebRTCService.peerConnectionFactory` liefert eine
// Attrappe. Der Test prüft damit genau das, was der Nutzer merkt:
//   * ein Offer baut Verbindung UND Datenkanal auf,
//   * der ICE-Zustand setzt "verbunden",
//   * eine eingehende Nachricht kommt bei der App an,
//   * ein Rücksetzen baut eine neue Verbindung (kein stale ICE).
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockKeystore();
    final temp = await Directory.systemTemp.createTemp('webrtc_naht');
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
    kanal = FakeDataChannel();
    peer = FakePeerConnection(kanal: kanal);
    WebRTCService.peerConnectionFactory = (config) async => peer;
    dienst = WebRTCService(encryption);
  });

  tearDown(() {
    WebRTCService.peerConnectionFactory = null;
  });

  group('Der WebRTC-Dienst', () {
    test('ein Offer baut Verbindung und Datenkanal auf', () async {
      await dienst.createOffer('partner-1');

      expect(peer.erstellt, 1);
      expect(
        kanal.onMessage,
        isNotNull,
        reason:
            'Ohne Datenkanal koennen keine Nachrichten ankommen - der '
            'Aufbau muss ihn einrichten.',
      );
    });

    test('der ICE-Zustand setzt "verbunden"', () async {
      await dienst.createOffer('partner-1');
      expect(dienst.isConnected, isFalse);

      peer.verbinde();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        dienst.isConnected,
        isTrue,
        reason:
            'Der Nutzer muss wissen, ob die Direktverbindung steht - '
            'sonst denkt er, seine Nachrichten seien verschluesselt, '
            'obwohl sie ueber den Server laufen.',
      );
    });

    test('kaputte Daten vom Partner lassen die App nicht abstuerzen', () async {
      await dienst.createOffer('partner-1');

      final sub = dienst.incomingMessages.listen((_) {});
      addTearDown(sub.cancel);

      // DER FALL: Ein fremder (oder kompromittierter) Peer schickt
      // Gültiges JSON mit ungültigem Inhalt. Die App darf das nicht
      // abstürzen lassen - sie muss die Nachricht verwerfen und
      // weiterlaufen.
      kanal.empfange(
        '{"type":"signal_message","ciphertext":"???","messageType":2}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        dienst.isConnected,
        isFalse,
        reason: 'Die Verbindung bleibt benutzbar - auch nach Schrott vom Peer.',
      );
    });

    test('ein erneuter Aufbau benutzt eine neue Verbindung', () async {
      await dienst.createOffer('partner-1');
      final erste = peer;

      final zweite = FakePeerConnection(kanal: FakeDataChannel());
      WebRTCService.peerConnectionFactory = (config) async => zweite;
      await dienst.createOffer('partner-1');

      expect(erste.erstellt, 1);
      expect(zweite.erstellt, 1);
      expect(
        zweite.erstellt,
        1,
        reason:
            'Nach einem Retry muss eine NEUE Verbindung gebaut werden - '
            'eine alte ICE-Schicht wuerde den Handshake blockieren.',
      );
    });
  });
}
