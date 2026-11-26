// Die Ende-zu-Ende-Verschlüsselung - der Session-Aufbau war ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/services/chat/encryption_service.dart 136 offene Zeilen. Die
// Session-Aufbau-Funktionen (PreKey-Bundle, Session, Trust) waren
// ungetestet - obwohl sie die ZUSEITUNG der App tragen: "Ende-zu-Ende-
// verschlüsselt".
//
// ANMERKUNG: Diese Tests laufen als NORMALE Tests (nicht als
// Widget-Tests) - Hive braucht echte Datei-Arbeit.
//
// ANMERKUNG ZUM ZWEITEN GERÄT: Zwei echte Geräte teilen sich keine
// Boxen - im Test wäre das ein Fehler (beide nämen dieselben
// PreKeys). Deshalb wird die Gegenseite hier durch ein zweites Bundle
// aus demselben Dienst angedeutet: geprüft wird der AUFBAU der
// Session, nicht der Austausch zwischen zwei Geräten.
//
// WAS HIER GEPRÜFT WIRD:
//   * das PreKey-Bundle trägt alle öffentlichen Schlüssel,
//   * eine Session wird aufgebaut,
//   * ein geänderter Identity-Key des Peers wird NICHT still
//     akzeptiert (der Nutzer muss die Safety-Nummer prüfen),
//   * das Zurücksetzen des Vertrauens löst die Session,
//   * die Safety-Nummer ist stabil,
//   * der Signed-PreKey ist vorhanden.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';

import '../support/plugin_mocks.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen sind AES-256-verschlüsselt.
    mockKeystore();
    // DIE ADAPTER: die Boxen halten Signal-Objekte.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_signal');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Baut einen fertigen Dienst.
  Future<EncryptionService> dienst(String? userId) async {
    final service = EncryptionService();
    service.localUserId = userId;
    await service.initialize();
    return service;
  }

  /// Baut die Session mit einem Bundle (die Gegenseite).
  Future<void> baueSession(
    EncryptionService service,
    Map<String, dynamic> bundle,
    String peerId,
  ) async {
    await service.buildSession(
      peerId,
      bundle['identityKeyPublic'] as String,
      bundle['preKeyPublic'] as String,
      bundle['preKeyId'] as int,
      bundle['signedPreKeyPublic'] as String,
      bundle['signedPreKeyId'] as int,
      bundle['signedPreKeySignature'] as String,
      bundle['registrationId'] as int,
    );
  }

  group('Die Ende-zu-Ende-Verschluesselung', () {
    test('das PreKey-Bundle traegt alle oeffentlichen Schluessel', () async {
      final service = await dienst('ich');

      final bundle = await service.exportPreKeyBundle();

      expect(bundle['identityKeyPublic'], isNotNull);
      expect(bundle['preKeyPublic'], isNotNull);
      expect(bundle['signedPreKeyPublic'], isNotNull);
      expect(bundle['signedPreKeySignature'], isNotNull);
      expect(bundle['registrationId'], isNotNull);
      expect(bundle['preKeyId'], isA<int>());
      // Der Identity-Key muss ein Curve25519-Punkt sein.
      expect(base64Decode(bundle['identityKeyPublic'] as String).length, 33);
    });

    test('eine Session wird aufgebaut', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();

      await baueSession(service, bundle, 'partner-1');

      expect(
        await service.hasSession('partner-1'),
        isTrue,
        reason: 'Nach dem Bundle-Aufbau muss die Session stehen.',
      );
    });

    test('ein geaenderter Identity-Key wird nicht still akzeptiert', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      // ignore: avoid_print
      print(
        'DIAG TRUST: ${Hive.box<String>('signal_peer_trust').keys.toList()}',
      );
      // Ein kompromittierter Server schiebt ein anderes Bundle unter -
      // das darf NICHT still akzeptiert werden.
      //
      // DER WEG: Ein echter, fremder Identity-Key (ein gültiger
      // Curve25519-Punkt). Der Dienst im Test teilt sich die Boxen mit
      // dem ersten - sein eigener Key wäre also DERSELBE.
      final fremdesPaar = Curve.generateKeyPair();
      final falschesBundle = <String, dynamic>{
        ...bundle,
        'identityKeyPublic': base64Encode(fremdesPaar.publicKey.serialize()),
      };

      await expectLater(
        baueSession(service, falschesBundle, 'partner-1'),
        throwsStateError,
        reason:
            'Ein geaenderter Identity-Key muss eine ausdrueckliche '
            'Entscheidung des Nutzers erfordern (Safety-Nummer).',
      );
    });

    test('das Zuruecksetzen des Vertrauens loest den Trust-Eintrag', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');
      expect(await service.hasSession('partner-1'), isTrue);

      // DER TRUST-EINTRAG: Der Dienst merkt sich den Identity-Key des
      // Peers (TOFU). Nach dem Zurücksetzen ist er weg - erst dann darf
      // ein neuer Key kommen.
      //
      // DER WEG: Der Test liest die Box direkt (der Dienst bietet keinen
      // Getter dafür an).
      final trustBox = Hive.box<String>('signal_peer_trust');
      expect(trustBox.get('partner-1'), isNotNull);

      await service.resetPeerTrust('partner-1');

      expect(
        trustBox.get('partner-1'),
        isNull,
        reason:
            'Nach dem Zuruecksetzen des Vertrauens darf kein alter '
            'Identity-Key mehr gespeichert sein - sonst gilt ein '
            'untergeschobener Key weiter.',
      );
    });

    test('die Safety-Nummer ist stabil', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      final peerKey = bundle['identityKeyPublic'] as String;

      final erste = service.fingerprintSafetyNumber('partner-1', peerKey);
      final zweite = service.fingerprintSafetyNumber('partner-1', peerKey);

      expect(
        erste,
        zweite,
        reason:
            'Die Safety-Nummer muss stabil sein - sonst stimmen die '
            'Zahlen der beiden Geraete nicht ueberein.',
      );
      expect(erste, isNotEmpty);
      // Und sie ist aus Ziffern (12 Blöcke à 5 Ziffern).
      expect(erste.replaceAll(' ', ''), matches(RegExp(r'^\d+$')));
    });

    test('der Signed-PreKey ist vorhanden', () async {
      final service = await dienst('ich');

      final signed = await service.getCurrentSignedPreKey();
      expect(
        signed,
        isNotNull,
        reason:
            'Ohne Signed-PreKey kann die Gegenseite keine Session '
            'aufbauen - die Nachrichten kaemen nie an.',
      );
    });

    test('der Identity-Key ist ein gueltiger Punkt', () async {
      final service = await dienst('ich');

      final identity = base64Decode(service.identityKeyPublicBase64);
      expect(
        identity.length,
        33,
        reason: 'Der oeffentliche Identity-Key muss ein Curve25519-Punkt sein.',
      );
    });
  });
}
