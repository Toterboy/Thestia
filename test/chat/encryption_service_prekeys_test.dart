// Der PreKey-Vorrat des Verschluesselungs-Dienstes.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/encryption_service.dart 58 offene Zeilen. Der
// Vorrat an PreKeys war ungetestet - und er ist der Grund, warum ein
// Chat ueberhaupt funktioniert: ohne PreKeys kann der Empfaenger die
// erste Nachricht des Absenders nicht lesen.
//
// DER WEG: Der Dienst wird wie in den anderen Encryption-Tests
// aufgebaut (Hive mit den Adaptern, der Keystore als Attrappe).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Dienst fuellt den Vorrat beim Start,
//   * zwei Kontakte bekommen nie denselben PreKey (sonst koennte die
//     Nachricht des zweiten nicht gelesen werden),
//   * ein grosser Vorrat wird nicht unnoetig neu erzeugt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';

import '../support/plugin_mocks.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen sind AES-256-verschluesselt.
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
    temp = await Directory.systemTemp.createTemp('thesia_prekeys');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Baut einen fertigen Dienst.
  Future<EncryptionService> dienst() async {
    final service = EncryptionService();
    await service.initialize();
    return service;
  }

  group('Der PreKey-Vorrat', () {
    test('ist beim Start gefuellt', () async {
      final service = await dienst();

      expect(
        await service.availablePreKeyCount,
        greaterThan(0),
        reason:
            'Ohne PreKeys kann der Empfaenger die erste Nachricht nicht '
            'lesen - der Dienst muss sie beim Start bereitlegen.',
      );
    });

    test('zwei Kontakte bekommen nie denselben PreKey', () async {
      final service = await dienst();

      final erster = await service.getUnusedPreKey();
      final zweiter = await service.getUnusedPreKey();

      expect(erster, isNotNull, reason: 'Es muss einen PreKey geben.');
      expect(zweiter, isNotNull);
      expect(
        zweiter!.id,
        isNot(erster!.id),
        reason:
            'Jeder Kontakt braucht einen eigenen PreKey - mit demselben '
            'koennte die Nachricht des zweiten nicht gelesen werden.',
      );
    });

    test('ein grosser Vorrat wird nicht neu erzeugt', () async {
      final service = await dienst();
      final vorher = await service.availablePreKeyCount;

      await service.maybeRotatePreKeys();

      expect(
        await service.availablePreKeyCount,
        vorher,
        reason:
            'Der Vorrat ist noch voll - eine Neuerzeugung waere verschwendete '
            'Arbeit auf dem Geraet.',
      );
    });
  });
}
