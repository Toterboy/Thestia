// Die Outbox des P2P-Chats (Nachrichten vor dem offenen Kanal).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/p2p_chat_service.dart 67 offene Zeilen. Der Dienst
// puffert Nachrichten, die geschrieben werden, BEVOR der DataChannel
// offen ist - das ist der Weg, den der QR-Chat und der Zufallschat
// gehen.
//
// DER WEG: Die Peer-Connection-Attrappe (test/support/fake_webrtc.dart)
// liefert den Kanal; der Dienst braucht noch den Verschluesselungs-
// Dienst (die Nachrichten werden verschluesselt gesendet).
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Nachricht vor dem offenen Kanal geht nicht verloren (sie
//     landet in der Outbox),
//   * das Leeren der Outbox verwirft die Warteschlange (Logout,
//     Kontowechsel - sonst kaeme eine Nachricht im falschen Chat an),
//   * der Relay-Weg leert die Warteschlange ueber den Server.
//
// NICHT DABEI: Der Flush beim offenen Kanal - dafuer braucht es eine
// aufgebaute Signal-Sitzung (ohne sie schlaegt die Verschluesselung
// fehl und die Nachricht bleibt in der Schlange). Das ist ein eigener
// Weg und wird im Signal-Test geprueft.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_webrtc.dart';
import '../support/plugin_mocks.dart';

void main() {
  late EncryptionService encryption;
  late WebRTCService webrtc;
  late P2PChatService dienst;
  late FakePeerConnection peer;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockKeystore();
    final temp = await Directory.systemTemp.createTemp('p2p_outbox');
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
    WebRTCService.peerConnectionFactory = (config) async => peer;
    webrtc = WebRTCService(encryption);
    dienst = P2PChatService(webrtc, PreKeyService(encryption));
  });

  tearDown(() {
    WebRTCService.peerConnectionFactory = null;
  });

  group('Die Outbox', () {
    test('eine Nachricht vor dem offenen Kanal geht nicht verloren', () async {
      final direkt = await dienst.trySendText('Hallo');

      expect(
        direkt,
        isFalse,
        reason:
            'Ohne offenen Kanal kann nicht direkt gesendet werden - der '
            'Aufrufer braucht das (er schaltet sonst auf das Relay um).',
      );
      expect(
        dienst.pendingCount,
        1,
        reason:
            'Die Nachricht muss in der Warteschlange landen - sonst geht '
            'sie verloren, wenn der Partner noch nicht online ist.',
      );
    });

    test('das Leeren verwirft die Warteschlange', () async {
      await dienst.trySendText('Hallo');
      expect(dienst.pendingCount, 1);

      dienst.clearOutbox();

      expect(
        dienst.pendingCount,
        0,
        reason:
            'Nach dem Leeren darf nichts mehr in der Schlange sein - '
            'sonst kaeme eine Nachricht des Vorgaengers im falschen Chat '
            'an.',
      );
    });

    test('der Relay-Weg leert die Warteschlange', () async {
      await dienst.trySendText('Hallo');

      final uebertragen = <String>[];
      await dienst.drainOutboxViaRelay((text) async {
        uebertragen.add(text);
      });

      expect(
        uebertragen,
        contains('Hallo'),
        reason:
            'Im Relay-Fall muss die Warteschlange ueber den Server gehen - '
            'sonst wartet die Nachricht auf einen Kanal, den es nie gibt.',
      );
      expect(dienst.pendingCount, 0);
    });
  });
}
