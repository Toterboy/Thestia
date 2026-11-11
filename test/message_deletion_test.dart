// Test fuer die Nachrichten-Loeschung "fuer alle" (v0.10.1).
//
// BEFUND (11.11.2026, Betreiber): "3. Ist kein Nachrichtenloeschen wie bei
// z. B. Whatsapp moeglich? Also da kann man die Nachricht ja irgendwie fuer
// beide loeschen, aber ein Hinweis steht dann da, dass es fuer alle
// geloescht wurde. Ist das gegen den Datenschutz? Wenn ja nicht machen."
//
// DIE ANTWORT: Nein - solange der Server NUR die Tatsache speichert
// (kein Inhalt). Dieser Test haelt fest, dass die lokale Seite die
// Nachricht durch einen HINWEIS ersetzt (nicht durch einen Text, der
// verraten wuerde, was drin stand).
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/services/chat_service.dart';

UserProfile _profil([String id = 'partner']) {
  return UserProfile(
    id: id,
    name: 'Testperson',
    birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
    bio: '',
  );
}

void main() {
  group('Nachricht fuer alle loeschen (lokal)', () {
    late ChatService service;
    late ChatNotifier notifier;

    setUp(() {
      service = ChatService();
      notifier = ChatNotifier(service);
    });

    test('die Nachricht wird durch einen Hinweis ersetzt', () {
      final match = service.createMatch(_profil());
      notifier.addMessage(
        match.id,
        Message(
          id: 'm_1',
          senderId: 'anderer',
          receiverId: 'ich',
          text: 'Das ist ein Geheimnis',
          timestamp: DateTime.now(),
        ),
      );
      expect(service.getMessages(match.id).length, 1);

      final geaendert = notifier.applyDeletion(
        match.id,
        'm_1',
        noticeText: 'Diese Nachricht wurde gelöscht.',
      );

      expect(geaendert, isTrue);
      final liste = service.getMessages(match.id);
      expect(liste.length, 1);
      expect(liste.first.type, MessageType.notice);
      expect(liste.first.text, 'Diese Nachricht wurde gelöscht.');
      // Der Originaltext ist WEG - genau das ist der Zweck.
      expect(liste.first.text, isNot(contains('Geheimnis')));
    });

    test('eine unbekannte Nachricht aendert nichts', () {
      final match = service.createMatch(_profil());
      final geaendert = notifier.applyDeletion(
        match.id,
        'gibt_es_nicht',
        noticeText: 'Diese Nachricht wurde gelöscht.',
      );
      expect(geaendert, isFalse);
      expect(service.getMessages(match.id), isEmpty);
    });

    test('zweimal loeschen aendert nichts mehr', () {
      final match = service.createMatch(_profil());
      notifier.addMessage(
        match.id,
        Message(
          id: 'm_2',
          senderId: 'anderer',
          receiverId: 'ich',
          text: 'Text',
          timestamp: DateTime.now(),
        ),
      );
      expect(
        notifier.applyDeletion(
          match.id,
          'm_2',
          noticeText: 'Diese Nachricht wurde gelöscht.',
        ),
        isTrue,
      );
      // Der Hinweis ist schon da - er wird nicht doppelt gesetzt.
      expect(
        notifier.applyDeletion(
          match.id,
          'm_2',
          noticeText: 'Diese Nachricht wurde gelöscht.',
        ),
        isFalse,
      );
      expect(service.getMessages(match.id).length, 1);
    });
  });
}
