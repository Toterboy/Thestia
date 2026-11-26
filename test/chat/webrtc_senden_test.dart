// Das Senden über den Datenkanal (mit echter Signal-Sitzung).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/services/chat/webrtc_service.dart 61 offene Zeilen - darunter
// `sendMessage`, `sendControl` und `sendCallAudio`. Diese Wege brauchen
// eine aufgebaute Signal-Sitzung (ohne sie schlägt die Verschlüsselung
// fehl und der Sendeweg ist nicht erreichbar).
//
// DER WEG: Der Dienst kann sein eigenes öffentliches PreKey-Bundle
// exportieren. Mit diesem Bundle baut der Test eine Sitzung - der
// "Partner" trägt dabei denselben Schlüsselsatz (in einer echten
// Sitzung wäre es der des Geräts des anderen).
//
// ACHTUNG: Mit dieser symmetrischen Sitzung lässt sich nicht wieder
// entschlüsseln (der Ratchet hat nur eine Kette - der Empfänger
// wäre ein zweites Gerät). Geprüft wird deshalb die HÜLLE, die
// über den Kanal geht: Sie muss verschlüsselt sein, und sie trägt die
// Metadaten.
//
// WAS HIER GEPRÜFT WIRD:
//   * eine Textnachricht geht verschlüsselt über den Kanal (der
//     Klartext darf nicht mitgehen),
//   * eine Kontroll-Nachricht des Anrufs geht raus,
//   * ein Sprachpaket geht als Binärhülle raus (mit der Art des Pakets).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final temp = await Directory.systemTemp.createTemp('webrtc_senden');
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
    WebRTCService.peerConnectionFactory = (config) async => peer;
    dienst = WebRTCService(encryption);
    dienst.currentPeerIdForTesting = 'partner-1';
    encryption.localUserId = 'ich';

    // DIE SITZUNG: Ohne sie schlägt die Verschlüsselung fehl.
    final bundle = await encryption.exportPreKeyBundle();
    await encryption.buildSession(
      'partner-1',
      bundle['identityKeyPublic']! as String,
      bundle['preKeyPublic']! as String,
      bundle['preKeyId']! as int,
      bundle['signedPreKeyPublic']! as String,
      bundle['signedPreKeyId']! as int,
      bundle['signedPreKeySignature']! as String,
      bundle['registrationId']! as int,
    );
  });

  tearDown(() {
    WebRTCService.peerConnectionFactory = null;
  });

  /// Öffnet den Kanal (die Gegenseite liefert ihn).
  Future<void> oeffneKanal() async {
    await dienst.handleOffer('partner-1', 'v=0');
    peer.onDataChannel?.call(kanal);
    kanal.oeffne();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Die Hülle der letzten gesendeten Nachricht.
  Map<String, dynamic> letzteHuelle() {
    expect(kanal.gesendet, isNotEmpty);
    return jsonDecode(kanal.gesendet.last.text) as Map<String, dynamic>;
  }

  group('Das Senden', () {
    test('eine Textnachricht geht verschluesselt ueber den Kanal', () async {
      await oeffneKanal();

      await dienst.sendMessage('Hallo');

      final huelle = letzteHuelle();
      expect(
        huelle['ciphertext'],
        isNotNull,
        reason:
            'Die Nachricht muss verschluesselt ueber den Kanal - im Klartext '
            'koennte jeder mitlesen, der die Leitung sieht.',
      );
      expect(
        huelle['ciphertext'],
        isNot(contains('Hallo')),
        reason: 'Der Klartext darf nicht mitgehen.',
      );
      expect(
        huelle['type'],
        'signal_message',
        reason:
            'Die Huelle muss als Nachricht gekennzeichnet sein - sonst '
            'verwirft der Empfaenger sie.',
      );
    });

    test('eine Kontroll-Nachricht des Anrufs geht raus', () async {
      await oeffneKanal();

      await dienst.sendControl(<String, dynamic>{'type': 'accept'});

      final huelle = letzteHuelle();
      expect(
        huelle['ciphertext'],
        isNotNull,
        reason:
            'Die Kontroll-Nachricht des Anrufs geht ueber denselben Kanal - '
            'aber verschluesselt (der Praefix "CALL:" liegt im Chiffrat).',
      );
      expect(huelle['type'], 'signal_message');
    });

    test('ein Sprachpaket geht als Binaerhuelle ueber den Kanal', () async {
      await oeffneKanal();

      await dienst.sendCallAudio(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        metadata: <String, dynamic>{'kind': 'opus'},
      );

      final huelle = letzteHuelle();
      expect(huelle['ciphertext'], isNotNull);
      expect(
        (huelle['metadata'] as Map?)?['kind'],
        'opus',
        reason:
            'Die Art des Pakets muss mitgehen - sonst kann der Empfaenger '
            'Sprache und Bild nicht unterscheiden.',
      );
    });
  });
}
