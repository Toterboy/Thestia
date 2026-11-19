// Unit-Tests fuer das Modell der Zufallschat-Sitzung.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Status-Umrechnung des serverseitigen Matching (waiting/active/ended),
//   * das Auslesen der RPC-Antwort (join_random_chat,
//     get_random_chat_session),
//   * die Paarungs-Bedingung [RandomChatSession.isMatched].
//
// WARUM DAS EIGENTLICH WICHTIG IST:
//   Der Zufallschat entscheidet ueber die Paarung. Ein falsch gelesener
//   Status heisst: Die App zeigt eine Partnerin an, mit der es gar keine
//   Verbindung gibt - oder sie wartet endlos, obwohl der Server längst
//   gepaart hat. Die Status-Umrechnung ist deshalb fail-safe gebaut:
//   Unbekanntes wird "waiting" (nicht "active") - im Zweifel wartet die
//   App, statt dem Nutzer eine falsche Partnerin zu zeigen.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/random_chat_session.dart';

void main() {
  group('RandomChatStatus.fromString', () {
    test('die drei Server-Zustaende werden richtig erkannt', () {
      expect(RandomChatStatus.fromString('active'), RandomChatStatus.active);
      expect(RandomChatStatus.fromString('ended'), RandomChatStatus.ended);
      expect(RandomChatStatus.fromString('waiting'), RandomChatStatus.waiting);
    });

    test('unbekannter oder fehlender Status heisst "waiting"', () {
      // DER GRUND FUER DEN FAIL-SAFE: Ein neuer Server-Status (oder ein
      // fehlendes Feld) darf die App NICHT in den Zustand "gepaart" bringen.
      // Sonst wuerde der Chat einen Partner anzeigen, den es nicht gibt.
      expect(RandomChatStatus.fromString(null), RandomChatStatus.waiting);
      expect(RandomChatStatus.fromString(''), RandomChatStatus.waiting);
      expect(
        RandomChatStatus.fromString('irgendwas'),
        RandomChatStatus.waiting,
      );
    });
  });

  group('RandomChatSession.fromJson', () {
    test('liest Session, Partner und Status aus der RPC-Antwort', () {
      final sitzung = RandomChatSession.fromJson({
        'sessionId': 'sitzung-1',
        'partnerId': 'partner-1',
        'status': 'active',
      });

      expect(sitzung.sessionId, 'sitzung-1');
      expect(sitzung.partnerId, 'partner-1');
      expect(sitzung.status, RandomChatStatus.active);
    });

    test('fehlende Felder ergeben eine wartende Sitzung ohne Partner', () {
      // DER GRUND: Der Server kann eine leere Antwort liefern (z. B. wenn
      // die RPC keine Zeile fand). Das darf keinen Absturz und vor allem
      // keine erfundene Paarung ergeben.
      final sitzung = RandomChatSession.fromJson(const {});

      expect(sitzung.sessionId, isNull);
      expect(sitzung.partnerId, isNull);
      expect(sitzung.status, RandomChatStatus.waiting);
      expect(sitzung.isMatched, isFalse);
    });

    test('ein beendeter Chat bleibt beendet, auch mit Partner', () {
      final sitzung = RandomChatSession.fromJson({
        'sessionId': 'sitzung-2',
        'partnerId': 'partner-2',
        'status': 'ended',
      });

      expect(sitzung.status, RandomChatStatus.ended);
      expect(
        sitzung.isMatched,
        isFalse,
        reason:
            'Ein beendeter Chat ist keine aktive Paarung - die App darf '
            'ihn nicht als "du chattest gerade" behandeln.',
      );
    });
  });

  group('RandomChatSession.isMatched', () {
    test('aktiv MIT Partner: gepaart', () {
      const sitzung = RandomChatSession(
        sessionId: 'sitzung-3',
        partnerId: 'partner-3',
        status: RandomChatStatus.active,
      );

      expect(sitzung.isMatched, isTrue);
    });

    test('aktiv OHNE Partner: noch nicht gepaart', () {
      // DER GRUND: Der Server kann "active" melden, bevor die
      // Partner-ID feststeht. Ohne Partner gibt es niemanden, mit dem man
      // sprechen koennte.
      const sitzung = RandomChatSession(
        sessionId: 'sitzung-4',
        status: RandomChatStatus.active,
      );

      expect(sitzung.isMatched, isFalse);
    });

    test('wartend: nicht gepaart', () {
      const sitzung = RandomChatSession(
        sessionId: 'sitzung-5',
        partnerId: 'partner-5',
      );

      expect(sitzung.status, RandomChatStatus.waiting);
      expect(
        sitzung.isMatched,
        isFalse,
        reason: 'Warten heisst: die Paarung steht noch aus.',
      );
    });
  });
}
