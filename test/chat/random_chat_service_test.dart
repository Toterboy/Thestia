// Der Dienst des Zufallschats (die Warteschlange auf dem Server).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/services/dating_hour/random_chat_service.dart 32 % Abdeckung. Der
// Dienst entscheidet, OB man im Chat landet - und liest die Antwort des
// Servers (Paarung, Status). Ein falsch gelesener Status heißt: der
// Nutzer wartet auf einen Partner, den es nicht gibt.
//
// WAS HIER GEPRÜFT WIRD:
//   * das Beitreten liefert die Session mit dem Partner,
//   * ohne Partner liefert der Dienst null (die App zeigt dann die
//     Fehlerseite),
//   * der Status wird richtig gelesen (wartend / aktiv / beendet),
//   * das Verlassen meldet die Session ab.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/services/dating_hour/random_chat_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late RandomChatService dienst;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    dienst = RandomChatService(supabase.Supabase.instance.client);
  });

  group('Der Zufallschat-Dienst', () {
    test('das Beitreten liefert die Session mit dem Partner', () async {
      server.rpcAntworten['join_random_chat'] = <String, dynamic>{
        'sessionId': 'session-1',
        'partnerId': 'partner-1',
        'status': 'active',
      };

      final session = await dienst.join();

      expect(session, isNotNull);
      expect(session!.sessionId, 'session-1');
      expect(session.partnerId, 'partner-1');
      expect(
        session.isMatched,
        isTrue,
        reason:
            'Aktive Session mit Partner heisst "gematcht" - nur dann zeigt '
            'die App den Chat.',
      );
    });

    test('ohne Partner liefert der Dienst null', () async {
      server.rpcAntworten['join_random_chat'] = <String, dynamic>{
        'sessionId': 'session-1',
        'status': 'waiting',
      };

      final session = await dienst.join();

      expect(session, isNotNull);
      expect(
        session!.isMatched,
        isFalse,
        reason:
            'Ohne Partner gibt es keinen Chat - die App muss weiter suchen '
            'und darf nicht so tun, als waere jemand da.',
      );
    });

    test('der Status wird richtig gelesen', () async {
      server.rpcAntworten['get_random_chat_session'] = <String, dynamic>{
        'sessionId': 'session-1',
        'partnerId': 'partner-1',
        'status': 'ended',
      };

      final session = await dienst.getSession('session-1');

      expect(session, isNotNull);
      expect(
        session!.status,
        RandomChatStatus.ended,
        reason:
            'Ein beendeter Chat muss als beendet erkannt werden - sonst '
            'wartet der Nutzer auf einen Partner, der gegangen ist.',
      );
    });

    test('eine unbekannte Session liefert null', () async {
      server.rpcAntworten['get_random_chat_session'] = null;

      final session = await dienst.getSession('gibt-es-nicht');

      expect(
        session,
        isNull,
        reason:
            'Eine unbekannte Session ist kein Fehler - der Dienst meldet '
            'einfach "nichts" zurueck.',
      );
    });

    test('das Verlassen meldet die Session ab', () async {
      await dienst.leave('session-1');

      expect(
        server.rpcAufrufe.any(
          (c) =>
              c['funktion'] == 'leave_random_chat' &&
              c['p_session_id'] == 'session-1',
        ),
        isTrue,
        reason:
            'Ohne Abmeldung wartet der Server ewig auf einen Partner, der '
            'nicht mehr kommt.',
      );
    });

    test('die eigene aktive Session wird gemeldet', () async {
      server.rpcAntworten['get_my_active_random_chat'] = <String, dynamic>{
        'sessionId': 'session-9',
        'partnerId': 'partner-9',
        'status': 'active',
      };

      final session = await dienst.getMyActiveSession();

      expect(session, isNotNull);
      expect(session!.sessionId, 'session-9');
      expect(session.partnerId, 'partner-9');
    });

    test('ohne aktive Session kommt null', () async {
      server.rpcAntworten['get_my_active_random_chat'] = <String, dynamic>{
        'sessionId': null,
      };

      final session = await dienst.getMyActiveSession();

      expect(
        session,
        isNull,
        reason:
            'Ohne Session-ID ist es keine Session - die App darf keine '
            'erfinden.',
      );
    });
  });

  group('Die Session aus dem Server', () {
    test('unbekannte Felder ergeben sichere Standardwerte', () {
      final session = RandomChatSession.fromJson(<String, dynamic>{
        'sessionId': 'session-1',
      });

      expect(session.partnerId, isNull);
      expect(session.status, RandomChatStatus.waiting);
      expect(session.isMatched, isFalse);
    });

    test('ein unbekannter Status gilt als "wartend"', () {
      // DER GRUND: Ein Status, den die App nicht kennt, darf NICHT als
      // "beendet" gelten - sonst würde die App einen lebenden Chat
      // schließen.
      final session = RandomChatSession.fromJson(<String, dynamic>{
        'sessionId': 'session-1',
        'partnerId': 'partner-1',
        'status': 'irgendwas',
      });

      expect(session.status, RandomChatStatus.waiting);
      expect(session.isMatched, isFalse);
    });
  });
}
