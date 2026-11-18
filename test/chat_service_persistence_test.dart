// Der Chat-Speicher (Verlauf und QR-Kontakte) - ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat_service.dart 102 offene Zeilen. Der Verlauf wird
// OPT-IN verschluesselt gespeichert (SecureHive, Schluessel im
// Keystore) - das ist die Zusage "der Verlauf bleibt auf dem Geraet und
// niemand sonst sieht ihn".
//
// ANMERKUNG: Diese Tests laufen als NORMALE Tests (nicht als
// Widget-Tests). Der Grund: Hive braucht echte Datei-Arbeit - im
// Widget-Test (Test-Uhr) kommt der Dateizugriff nie zu Ende, die Box
// bleibt offen und der Test laeuft in den Timeout.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Verlauf wird gespeichert und beim naechsten Start wieder
//     geladen,
//   * die Boxen sind pro Konto getrennt (Kontowechsel),
//   * das Ausschalten leert die gespeicherte Historie,
//   * der Export enthaelt die Nachrichten,
//   * die QR-Kontakte ueberleben einen Neustart,
//   * die Account-Loeschung nimmt alles mit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/chat_service.dart';

import 'support/plugin_mocks.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen werden verschluesselt (der Schluessel liegt
    // im Keystore).
    mockKeystore();
  });

  setUp(() async {
    // Jeder Test bekommt ein eigenes Verzeichnis (die Boxen sind sonst
    // noch offen).
    temp = await Directory.systemTemp.createTemp('thesia_chat');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Eine Nachricht.
  Message nachricht(String id, String text) => Message(
    id: id,
    senderId: 'partner-1',
    receiverId: 'ich',
    text: text,
    timestamp: DateTime.now(),
  );

  group('Der Chat-Verlauf', () {
    test('wird gespeichert und wieder geladen', () async {
      final service = ChatService();
      await service.setOwner('ich');
      service.setHistoryPersistence(true);

      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(match.id, nachricht('m1', 'Hallo'));

      // Der Verlauf liegt in der Box (verschluesselt).
      final boxName = ChatService.historyBoxNameFor('ich');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        Hive.isBoxOpen(boxName),
        isTrue,
        reason: 'Die Verlaufs-Box muss offen sein.',
      );
      expect(Hive.box<String>(boxName).get(match.id), isNotNull);

      // Ein neuer Dienst (wie ein App-Neustart) laedt ihn wieder.
      final neu = ChatService();
      await neu.setOwner('ich');
      neu.setHistoryPersistence(true);
      await neu.hydrateHistory(match.id);

      final nachrichten = neu.getMessages(match.id);
      expect(
        nachrichten.map((m) => m.text),
        contains('Hallo'),
        reason:
            'Der Verlauf muss nach dem Neustart wieder da sein - das ist '
            'die Zusage des Opt-in.',
      );
    });

    test('die Boxen sind pro Konto getrennt', () async {
      expect(ChatService.historyBoxNameFor('konto-a'), 'chat_history_konto-a');
      expect(ChatService.historyBoxNameFor('konto-b'), 'chat_history_konto-b');
      expect(
        ChatService.historyBoxNameFor('konto-a'),
        isNot(ChatService.historyBoxNameFor('konto-b')),
        reason:
            'Auf demselben Geraet darf Konto B die Daten von Konto A nie '
            'sehen.',
      );
      expect(ChatService.qrBoxNameFor('konto-a'), 'qr_contacts_konto-a');
    });

    test('das Ausschalten leert die Historie', () async {
      final service = ChatService();
      await service.setOwner('ich');
      service.setHistoryPersistence(true);

      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(match.id, nachricht('m1', 'Hallo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Jetzt ausschalten.
      service.setHistoryPersistence(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final boxName = ChatService.historyBoxNameFor('ich');
      expect(
        Hive.isBoxOpen(boxName)
            ? Hive.box<String>(boxName).get(match.id)
            : null,
        isNull,
        reason:
            'Nach dem Ausschalten darf kein Verlauf auf dem Geraet liegen - '
            'das war der Grund fuer das Opt-in.',
      );
    });

    test('der Export enthaelt die Nachrichten', () async {
      final service = ChatService();
      await service.setOwner('ich');
      service.setHistoryPersistence(true);

      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(match.id, nachricht('m1', 'Hallo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final export = await service.exportHistory();
      expect(export, isNotEmpty);
      expect(export.containsKey(match.id), isTrue);
      expect(
        export[match.id]!.any((m) => m['text'] == 'Hallo'),
        isTrue,
        reason: 'Der Export muss die Nachrichten enthalten.',
      );
    });

    test('die QR-Kontakte ueberleben einen Neustart', () async {
      final service = ChatService();
      await service.setOwner('ich');

      // DER WEG: Nur `createQrContact` speichert den Kontakt dauerhaft
      // (`createMatch` legt ihn nur im Speicher an).
      service.createQrContact(
        const UserProfile(id: 'partner-2', name: 'Toni', bio: ''),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Ein neuer Dienst laedt sie wieder.
      final neu = ChatService();
      await neu.setOwner('ich');
      await neu.restoreQrContacts();

      expect(
        neu.getMatches().any((m) => m.partner.id == 'partner-2'),
        isTrue,
        reason:
            'Ein gespeicherter Kontakt muss den App-Neustart ueberleben - '
            'sonst verliert der Nutzer ihn.',
      );
    });

    test('die Account-Loeschung nimmt alles mit', () async {
      final service = ChatService();
      await service.setOwner('ich');
      service.setHistoryPersistence(true);

      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(match.id, nachricht('m1', 'Hallo'));
      service.createMatch(
        const UserProfile(id: 'partner-2', name: 'Toni', bio: ''),
        isQrContact: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.deleteOwnedData('ich');

      expect(service.getMatches(), isEmpty);
      expect(service.getMessages(match.id), isEmpty);
    });
  });
}
