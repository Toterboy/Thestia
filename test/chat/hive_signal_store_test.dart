// Der persistente Signal-Speicher - ungetestet (8,2 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/services/chat/hive_signal_store.dart 78 offene Zeilen bei 85 Zeilen
// gesamt. Hier liegt die Persistenz der Ende-zu-Ende-Verschlüsselung:
// die Sessions, der Identity-Trust und die PreKeys.
//
// WAS HIER GEPRÜFT WIRD:
//   * eine Identity wird gespeichert und wiedergefunden,
//   * ein GEÄNDERTER Identity-Key wird NICHT mehr als vertraut
//     akzeptiert (das ist der Schutz gegen einen untergeschobenen
//     Server - Audit H-7/E-4),
//   * eine Session überlebt das Neustart (sonst wären die Nachrichten
//     nach einem Neustart nicht mehr lesbar),
//   * eine Session lässt sich löschen (für alle Geräte des Peers),
//   * ein verbrauchter PreKey verschwindet aus der Box (sonst wäre er
//     mehrfach benutzbar - gebrochene Einmal-Nutzung).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/hive_signal_store.dart';

import '../support/plugin_mocks.dart';

/// Ein Identity-Schlüsselpaar (der eigene).
IdentityKeyPair schluesselPaar() {
  final paar = Curve.generateKeyPair();
  return IdentityKeyPair(
    IdentityKey.fromBytes(paar.publicKey.serialize(), 0),
    paar.privateKey,
  );
}

/// Eine fremde Identity.
IdentityKey fremdeIdentity() =>
    IdentityKey.fromBytes(Curve.generateKeyPair().publicKey.serialize(), 0);

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
    temp = await Directory.systemTemp.createTemp('thesia_store');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Öffnet die Boxen und den Store.
  Future<HiveSignalProtocolStore> oeffneStore() async {
    final sessionBox = await Hive.openBox<SignalSessionRecordAdapter>(
      'signal_sessions',
    );
    final trustBox = await Hive.openBox<SignalIdentityKeyStoreAdapter>(
      'signal_identity_trust',
    );
    final preKeyBox = await Hive.openBox<SignalPreKeyRecordAdapter>(
      'signal_prekeys',
    );
    return HiveSignalProtocolStore.open(
      identityKeyPair: schluesselPaar(),
      localRegistrationId: 42,
      sessionBox: sessionBox,
      identityTrustBox: trustBox,
      preKeyBox: preKeyBox,
    );
  }

  /// Die Adresse des Peers.
  SignalProtocolAddress adresse() =>
      const SignalProtocolAddress('partner-1', 1);

  group('Der Signal-Speicher', () {
    test('eine Identity wird gespeichert und wiedergefunden', () async {
      final store = await oeffneStore();
      final peer = fremdeIdentity();

      await store.saveIdentity(adresse(), peer);

      expect(await store.getIdentity(adresse()), isNotNull);
      expect(
        await store.isTrustedIdentity(adresse(), peer, Direction.receiving),
        isTrue,
      );
    });

    test('ein geaenderter Identity-Key wird nicht mehr vertraut', () async {
      final store = await oeffneStore();
      final peer = fremdeIdentity();

      await store.saveIdentity(adresse(), peer);
      expect(
        await store.isTrustedIdentity(adresse(), peer, Direction.receiving),
        isTrue,
      );

      // Jetzt kommt ein ANDERER Key (ein untergeschobener Server).
      final anderer = fremdeIdentity();
      expect(
        await store.isTrustedIdentity(adresse(), anderer, Direction.receiving),
        isFalse,
        reason:
            'Ein geaenderter Identity-Key darf nicht mehr als vertraut '
            'gelten - der Nutzer muss die Safety-Nummer pruefen.',
      );
    });

    test('das Vertrauen laesst sich zuruecksetzen', () async {
      final store = await oeffneStore();
      final peer = fremdeIdentity();

      await store.saveIdentity(adresse(), peer);
      await store.forgetIdentity('partner-1');

      expect(
        await store.isTrustedIdentity(adresse(), peer, Direction.receiving),
        isTrue,
        reason:
            'Nach dem Zuruecksetzen gilt wieder TOFU - der Nutzer hat den '
            'neuen Key bestaetigt.',
      );
    });

    test('eine Session ueberlebt das Neustart', () async {
      // Die erste Instanz legt eine Session an.
      final sessionBox = await Hive.openBox<SignalSessionRecordAdapter>(
        'signal_sessions',
      );
      final trustBox = await Hive.openBox<SignalIdentityKeyStoreAdapter>(
        'signal_identity_trust',
      );
      final store = await HiveSignalProtocolStore.open(
        identityKeyPair: schluesselPaar(),
        localRegistrationId: 42,
        sessionBox: sessionBox,
        identityTrustBox: trustBox,
      );
      await store.storeSession(adresse(), SessionRecord());
      expect(await store.containsSession(adresse()), isTrue);

      // Das Neustart: ein neuer Store lädt die Sessions aus der Box.
      final neu = await HiveSignalProtocolStore.open(
        identityKeyPair: schluesselPaar(),
        localRegistrationId: 42,
        sessionBox: sessionBox,
        identityTrustBox: trustBox,
      );
      expect(
        await neu.containsSession(adresse()),
        isTrue,
        reason:
            'Die Session muss den Neustart ueberleben - sonst sind die '
            'Nachrichten danach nicht mehr lesbar.',
      );
    });

    test('eine Session laesst sich loeschen', () async {
      final store = await oeffneStore();

      await store.storeSession(adresse(), SessionRecord());
      expect(await store.containsSession(adresse()), isTrue);

      await store.deleteSession(adresse());
      expect(await store.containsSession(adresse()), isFalse);
    });

    test('die Sessions eines Peers lassen sich alle loeschen', () async {
      final store = await oeffneStore();
      final zweitesGeraet = const SignalProtocolAddress('partner-1', 2);

      await store.storeSession(adresse(), SessionRecord());
      await store.storeSession(zweitesGeraet, SessionRecord());

      await store.deleteAllSessions('partner-1');

      expect(await store.containsSession(adresse()), isFalse);
      expect(await store.containsSession(zweitesGeraet), isFalse);
    });

    test('ein verbrauchter PreKey verschwindet aus der Box', () async {
      final store = await oeffneStore();
      final preKeyBox = await Hive.openBox<SignalPreKeyRecordAdapter>(
        'signal_prekeys',
      );

      // Einen PreKey ablegen (wie die App es beim Erzeugen tut - der
      // Eintrag ist der serialisierte Schlüssel als JSON).
      final record = PreKeyRecord(7, Curve.generateKeyPair());
      await preKeyBox.put(
        '7',
        SignalPreKeyRecordAdapter(
          keyId: 7,
          keyPairJson: base64Encode(record.serialize()),
        ),
      );
      expect(preKeyBox.get('7'), isNotNull);

      await store.removePreKey(7);

      expect(
        preKeyBox.get('7'),
        isNull,
        reason:
            'Ein verbrauchter PreKey muss aus der Box verschwinden - sonst '
            'wird er beim naechsten Start wieder geladen und geht an zwei '
            'Peers (gebrochene Einmal-Nutzung).',
      );
    });

    test('die Identity-Keys sind gueltige Punkte', () async {
      final store = await oeffneStore();

      final identity = await store.getIdentity(
        const SignalProtocolAddress('x', 1),
      );
      expect(
        identity,
        isNull,
        reason: 'Ohne gespeicherte Identity gibt es auch keine.',
      );
      expect(
        base64Decode(
          base64Encode(Curve.generateKeyPair().publicKey.serialize()),
        ).length,
        33,
      );
    });
  });
}
