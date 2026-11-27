// Die Umstellung der alten Chat-Boxen auf den Konto-Namensraum.
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/chat/chat_service.dart 55 offene Zeilen. Der Weg, der
// beim Anmelden die alten Boxen ("chat_history", "qr_contacts") in den
// Namensraum des Kontos überführt, lief komplett ins Leere.
//
// DER GRUND FÜR DIE UMSTELLUNG (Audit): Wer sich auf einem Gerät ab-
// meldet und ein anderes Konto anmeldet, darf die Verläufe des
// vorherigen Kontos nicht sehen. Deshalb heißen die Boxen jetzt
// "<basis>_<konto>".
//
// WAS HIER GEPRÜFT WIRD:
//   * der alte Verlauf wandert in die Box des Kontos,
//   * die alten QR-Kontakte wandern mit,
//   * gibt es die neue Box schon, wird der Rest gelöscht (und nichts
//     überschrieben),
//   * eine leere alte Box wird einfach gelöscht,
//   * ohne angemeldetes Konto wird nichts umgestellt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/secure_hive.dart';

import '../support/plugin_mocks.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen werden verschlüsselt (der Schlüssel liegt
    // im Keystore).
    mockKeystore();
  });

  setUp(() async {
    // Jeder Test bekommt ein eigenes Verzeichnis (die Boxen sind sonst
    // noch offen).
    temp = await Directory.systemTemp.createTemp('thesia_migration');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  /// Legt eine alte Box an (ohne Namensraum) und füllt sie.
  Future<void> legeAltBoxAn(String name, Map<String, String> inhalt) async {
    final box = await SecureHive.instance.openBox<String>(name);
    await box.putAll(inhalt);
    await box.flush();
    await box.close();
  }

  /// Liest den Inhalt einer Box (ohne sie offen zu lassen).
  Future<Map<String, String>> liesBox(String name) async {
    final box = await SecureHive.instance.openBox<String>(name);
    final inhalt = Map<String, String>.from(box.toMap());
    await box.close();
    return inhalt;
  }

  group('Die Umstellung beim Anmelden', () {
    test('der alte Verlauf wandert in die Box des Kontos', () async {
      await legeAltBoxAn('chat_history', <String, String>{'m-1': 'Hallo'});

      final service = ChatService();
      await service.setOwner('ich');

      final gewandert = await liesBox('chat_history_ich');
      expect(
        gewandert,
        containsPair('m-1', 'Hallo'),
        reason: 'Der alte Verlauf darf beim Anmelden nicht verloren gehen.',
      );
      expect(
        await Hive.boxExists('chat_history'),
        isFalse,
        reason: 'Die alte Box muss nach der Umstellung weg sein.',
      );
    });

    test('die alten QR-Kontakte wandern mit', () async {
      await legeAltBoxAn('qr_contacts', <String, String>{'k-1': '{"id":"x"}'});

      final service = ChatService();
      await service.setOwner('ich');

      final gewandert = await liesBox('qr_contacts_ich');
      expect(gewandert, containsPair('k-1', '{"id":"x"}'));
      expect(await Hive.boxExists('qr_contacts'), isFalse);
    });

    test('gibt es die neue Box schon, bleibt ihr Inhalt', () async {
      await legeAltBoxAn('chat_history', <String, String>{'alt': 'Rest'});
      await legeAltBoxAn('chat_history_ich', <String, String>{'neu': 'Behalt'});

      final service = ChatService();
      await service.setOwner('ich');

      final gewandert = await liesBox('chat_history_ich');
      expect(
        gewandert,
        containsPair('neu', 'Behalt'),
        reason: 'Der neue Bestand darf nicht überschrieben werden.',
      );
      expect(
        await Hive.boxExists('chat_history'),
        isFalse,
        reason: 'Der Rest der alten Box wird gelöscht.',
      );
    });

    test('eine leere alte Box wird gelöscht', () async {
      await legeAltBoxAn('chat_history', <String, String>{});

      final service = ChatService();
      await service.setOwner('ich');

      expect(await Hive.boxExists('chat_history'), isFalse);
    });

    test('ohne Konto wird nichts umgestellt', () async {
      await legeAltBoxAn('chat_history', <String, String>{'m-1': 'Hallo'});

      final service = ChatService();
      await service.setOwner(null);

      expect(
        await Hive.boxExists('chat_history'),
        isTrue,
        reason:
            'Ohne angemeldetes Konto bleibt der Altbestand liegen - er '
            'gehört vielleicht einem anderen Konto.',
      );
    });

    test('der alte Bestand landet nicht in einem fremden Konto', () async {
      await legeAltBoxAn('chat_history', <String, String>{'m-1': 'Hallo'});

      final erster = ChatService();
      await erster.setOwner('ich');
      final zweiter = ChatService();
      await zweiter.setOwner('sie');

      expect(await Hive.boxExists('chat_history_sie'), isFalse);
    });
  });

  group('Die Box-Namen', () {
    test('ohne Konto ist es der alte Name', () {
      expect(ChatService.historyBoxNameFor(null), 'chat_history');
      expect(ChatService.qrBoxNameFor(null), 'qr_contacts');
    });

    test('mit Konto ist der Name um den Konto-Namen erweitert', () {
      expect(ChatService.historyBoxNameFor('ich'), 'chat_history_ich');
      expect(ChatService.qrBoxNameFor('ich'), 'qr_contacts_ich');
    });

    test('zwei Konten haben zwei verschiedene Boxen', () {
      expect(
        ChatService.historyBoxNameFor('ich'),
        isNot(ChatService.historyBoxNameFor('sie')),
      );
    });
  });
}
