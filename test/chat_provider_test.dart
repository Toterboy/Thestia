import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _createPartner({String id = 'p1', String name = 'Mira'}) {
  return UserProfile(
    id: id,
    name: name,
    birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
    bio: '',
  );
}

void main() {
  group('ChatService', () {
    test('createMatch erzeugt Match mit korrekten Defaults', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      expect(match.partner, equals(partner));
      expect(match.matchedAt, isNotNull);
      expect(match.photosUnlocked, isTrue);
      expect(match.unreadCount, 0);
    });

    test('getMatches liefert alle Matches', () {
      final service = ChatService();
      final p1 = _createPartner(id: 'p1', name: 'Mira');
      final p2 = _createPartner(id: 'p2', name: 'Lena');

      service.createMatch(p1);
      service.createMatch(p2);

      final matches = service.getMatches();
      expect(matches.length, 2);
      expect(matches.map((m) => m.partner.name), containsAll(['Mira', 'Lena']));
    });

    test('getMatchById findet Match', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      final found = service.getMatchById(match.id);
      expect(found, isNotNull);
      expect(found!.id, match.id);
    });

    test('getMatchById liefert null fuer unbekannte ID', () {
      final service = ChatService();
      expect(service.getMatchById('unknown'), isNull);
    });

    test('getMessages liefert leere Liste fuer neues Match', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      expect(service.getMessages(match.id), isEmpty);
    });

    test('addMessage fuegt Nachricht hinzu ohne Auto-Antwort', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      final msg = Message(
        id: 'msg_1',
        senderId: 'me',
        receiverId: match.id,
        text: 'Hallo',
        timestamp: DateTime.now(),
      );
      service.addMessage(match.id, msg);

      final messages = service.getMessages(match.id);
      expect(messages.length, 1);
      expect(messages.first.text, 'Hallo');
    });

    test('markRead setzt unreadCount auf 0', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      // Match mit ungelesenem Zähler simulieren: über den Notifier-Zustand
      // prüfbar ist markRead über das Provider-Setup unten.
      service.markRead(match.id);
      final found = service.getMatchById(match.id);
      expect(found!.unreadCount, 0);
    });

    test('dissolveMatch entfernt Match und Nachrichten', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      expect(service.dissolveMatch(match.id), isTrue);
      expect(service.getMatchById(match.id), isNull);
      expect(service.getMessages(match.id), isEmpty);
    });

    test('dissolveMatch liefert false fuer unbekannte ID', () {
      final service = ChatService();
      expect(service.dissolveMatch('unknown'), isFalse);
    });

    test('resetMatch entfernt altes Match und erstellt neues bei Partner', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      service.addMessage(match.id, Message(
        id: 'msg_1',
        senderId: 'me',
        receiverId: match.id,
        text: 'Alt',
        timestamp: DateTime.now(),
      ));

      final newPartner = _createPartner(id: 'p2', name: 'Neu');
      service.resetMatch(match.id, partner: newPartner);

      expect(service.getMatchById(match.id), isNull);
      final newMatch = service.getMatches().firstWhere((m) => m.partner.id == 'p2');
      expect(newMatch.partner.name, 'Neu');
      expect(service.getMessages(newMatch.id), isEmpty);
    });

    test('resetMatch ohne Partner entfernt nur altes Match', () {
      final service = ChatService();
      final partner = _createPartner();
      final match = service.createMatch(partner);

      service.resetMatch(match.id);

      expect(service.getMatches(), isEmpty);
      expect(service.getMessages(match.id), isEmpty);
    });
  });

  group('ChatNotifier', () {
    test('addMatch erzeugt Match und fuehrt es in der Liste', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final matches = container.read(chatProvider);
      expect(matches.length, 1);
      expect(matches.first.partner.name, 'Mira');
      expect(matches.first.photosUnlocked, isTrue);
    });

    test('findOrCreateMatch legt QR-Kontakt an', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      final match = notifier.findOrCreateMatch('peer_1')!;
      expect(match.isQrContact, isTrue);
      expect(match.partner.id, 'peer_1');
      expect(container.read(chatProvider).length, 1);
      expect(container.read(chatProvider).first.isQrContact, isTrue);

      // Zweiter Scan derselben Person: WIEDER das gleiche Match
      // (per Partner-ID gesucht - die Chat-Route braucht die Match-ID,
      // damit der Detail-Screen das Match findet).
      final again = notifier.findOrCreateMatch('peer_1')!;
      expect(again.id, match.id);
      expect(container.read(chatProvider).length, 1);
    });

    test('findOrCreateMatch navigierbare Match-ID: Chat-Detail findet Match',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      final match = notifier.findOrCreateMatch('peer_1')!;
      // Regression v0.9.0: vor der Fix wurde die PARTNER-ID navigiert
      // (/chat/<peerId>), der Screen fand das Match anhand seiner
      // generierten ID nicht -> "Dieser Chat existiert nicht mehr".
      expect(notifier.getMatchById(match.id), isNotNull);
      expect(notifier.getMatchById(match.id)!.partner.id, 'peer_1');
    });

    test('updatePartner ersetzt das Partner-Profil (QR-Server-Fetch)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      final match = notifier.findOrCreateMatch('peer_1')!;
      notifier.updatePartner(match.id, _createPartner(id: 'peer_1', name: 'Lia'));

      final updated = notifier.getMatchById(match.id)!;
      expect(updated.partner.name, 'Lia');
      expect(updated.isQrContact, isTrue);
    });

    test('Maximal 5 gespeicherte Profile - 6ter wird abgelehnt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      for (var i = 1; i <= 5; i++) {
        expect(notifier.findOrCreateMatch('peer_$i'), isNotNull,
            reason: 'Kontakt $i muss bis zum Limit anlegbar sein');
      }
      // Sechster Kontakt: Maximum erreicht -> null (kein stilles Verdrängen).
      expect(notifier.findOrCreateMatch('peer_6'), isNull);
      expect(
        container.read(chatProvider).where((m) => m.isQrContact).length,
        5,
      );
    });

    test('deleteQrContact gibt wieder einen Slot frei', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);

      for (var i = 1; i <= 5; i++) {
        notifier.findOrCreateMatch('peer_$i');
      }
      expect(notifier.findOrCreateMatch('peer_6'), isNull);

      final fifth =
          container.read(chatProvider).where((m) => m.isQrContact).first;
      notifier.deleteQrContact(fifth.id);
      expect(container.read(chatProvider).where((m) => m.isQrContact).length, 4);

      // Slot frei -> neuer Kontakt geht wieder.
      expect(notifier.findOrCreateMatch('peer_6'), isNotNull);
    });

    test('addMessage fuegt P2P-Nachricht hinzu ohne Auto-Antwort', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final match = container.read(chatProvider).first;

      notifier.addMessage(match.id, Message(
        id: 'p2p_1',
        senderId: 'other',
        receiverId: 'me',
        text: 'Hey',
        timestamp: DateTime.now(),
      ));

      final messages = notifier.messagesFor(match.id);
      expect(messages.length, 1);
      expect(messages.first.text, 'Hey');
      expect(messages.first.senderId, 'other');
    });

    test('getMatchById findet Match', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final match = container.read(chatProvider).first;

      final found = notifier.getMatchById(match.id);
      expect(found, isNotNull);
      expect(found!.id, match.id);
    });

    test('getMatchById liefert null fuer unbekannte ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      expect(notifier.getMatchById('unknown'), isNull);
    });

    test('markRead setzt unreadCount auf 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final match = container.read(chatProvider).first;

      notifier.markRead(match.id);
      final updated = container.read(chatProvider).first;
      expect(updated.unreadCount, 0);
    });

    test('dissolveMatch entfernt Match', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final match = container.read(chatProvider).first;
      expect(container.read(chatProvider).length, 1);

      final success = notifier.dissolveMatch(match.id);
      expect(success, isTrue);
      expect(container.read(chatProvider).isEmpty, isTrue);
    });

    test('dissolveMatch liefert false fuer unbekannte ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      expect(notifier.dissolveMatch('unknown'), isFalse);
    });

    test('resetMatch entfernt altes Match und erstellt neues', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final partner = _createPartner();

      notifier.addMatch(partner);
      final match = container.read(chatProvider).first;

      final newPartner = _createPartner(id: 'p2', name: 'Neu');
      notifier.resetMatch(match.id, partner: newPartner);

      expect(notifier.getMatchById(match.id), isNull);
      final matches = container.read(chatProvider);
      expect(matches.length, 1);
      expect(matches.first.partner.name, 'Neu');
    });
  });
}
