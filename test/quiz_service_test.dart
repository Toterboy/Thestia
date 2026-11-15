// Das Match-Quiz (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/quiz_service.dart 0 %.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Zustand wird vom Server gelesen,
//   * eine Frage wird geholt,
//   * im Cooldown kommt der Cooldown-Hinweis (nicht eine Frage),
//   * die Antwort wird abgegeben und ausgewertet,
//   * ein Fehler fuehrt zu null (kein Absturz, kein falsches Ergebnis).
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/quiz_service.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late QuizService service;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

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
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.pfade.clear();
    server.antwortetMitFehler = false;
    service = QuizService(supabase.Supabase.instance.client);
  });

  group('Das Match-Quiz', () {
    test('der Zustand wird gelesen', () async {
      server.rpcAntworten['get_match_quiz_state'] = <String, dynamic>{
        'matchId': 42,
        'partnerId': 'user-7',
        'createdVia': 'find_match',
        'unlockLevel': 1,
        'failedAttempts': 2,
        'cooldownRemainingSeconds': 0,
      };

      final zustand = await service.getState(42);

      expect(zustand, isNotNull);
      expect(zustand!.matchId, 42);
      expect(zustand.partnerId, 'user-7');
      expect(zustand.unlockLevel, 1);
      expect(zustand.failedAttempts, 2);
      // Der Zustand entscheidet, ob der Chat gesperrt ist.
      expect(zustand.quizGated, isTrue);
      expect(zustand.passed, isFalse);
    });

    test('eine Frage wird geholt', () async {
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'questionId': 'q-1',
        'prompt': 'Was macht uns happy?',
        'options': ['Reisen', 'Kochen'],
      };

      final frage = await service.startAttempt(42);

      expect(frage, isNotNull);
      expect(frage!.id, 'q-1');
      expect(frage.prompt, 'Was macht uns happy?');
      expect(frage.options, ['Reisen', 'Kochen']);
    });

    test('im Cooldown kommt der Cooldown-Hinweis', () async {
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'error': 'cooldown',
        'cooldownRemainingSeconds': 120,
        'nextAttemptAt': '2026-11-14T12:00:00Z',
      };

      final frage = await service.startAttempt(42);

      expect(frage, isNotNull);
      // Der Marker "__cooldown__" sagt der Oberflaeche: das ist keine
      // Frage, sondern eine Wartezeit.
      expect(frage!.prompt, '__cooldown__');
      expect(frage.options.first, '120');
    });

    test('die Antwort wird abgegeben', () async {
      server.rpcAntworten['submit_quiz_answer'] = <String, dynamic>{
        'correct': true,
        'passed': true,
        'unlockLevel': 2,
        'failedAttempts': 0,
      };

      final ergebnis = await service.submitAnswer(42, 'q-1', 0);

      expect(ergebnis, isNotNull);
      expect(ergebnis!.correct, isTrue);
      expect(ergebnis.passed, isTrue);
      expect(ergebnis.unlockLevel, 2);
    });

    test('eine bereits beantwortete Runde wartet auf den Partner', () async {
      server.rpcAntworten['submit_quiz_answer'] = <String, dynamic>{
        'error': 'already_answered',
      };

      final ergebnis = await service.submitAnswer(42, 'q-1', 0);

      expect(ergebnis, isNotNull);
      expect(ergebnis!.waitingForPartner, isTrue);
    });

    test('ein Fehler fuehrt zu null', () async {
      server.antwortetMitFehler = true;

      // Kein Absturz und KEIN erfundenes Ergebnis: die Oberflaeche
      // entscheidet selbst, was ein Ausfall bedeutet.
      expect(await service.getState(42), isNull);
      expect(await service.startAttempt(42), isNull);
      expect(await service.submitAnswer(42, 'q-1', 0), isNull);
    });
  });
}
