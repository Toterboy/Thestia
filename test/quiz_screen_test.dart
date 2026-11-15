// Das Match-Quiz ("Wie gut kenn ich mein Match") - bisher ungetestet.
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/quiz/quiz_screen.dart 283 offene Zeilen - der Screen war
// gar nicht getestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Zustand kommt vom Server (RPC) - ohne Antwort gibt es eine
//     Fehlermeldung,
//   * das Foto ist vor dem ersten Versuch ganz verdeckt,
//   * ein Versuch stellt eine Frage (serverseitig), die Antwort wird
//     serverseitig geprueft,
//   * das Ergebnis kennt vier Faelle: falsch, wartet auf den Partner,
//     Runde geschlossen, bestanden,
//   * nach einem Fehlversuch laeuft der Cooldown.
//
// WIE DER SERVER ERSETZT WIRD: Der [FakeSupabaseServer] beantwortet die
// RPCs (get_match_quiz_state, start_quiz_attempt, submit_quiz_answer)
// aus dem RAM.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/quiz/quiz_screen.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Die Nummer des Test-Funkens.
const int _matchId = 7;

void main() {
  late FakeSupabaseServer server;

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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcFehler.clear();
  });

  /// Baut das Quiz mit dem angegebenen Serverzustand.
  ///
  /// [zustand] ist die Antwort von get_match_quiz_state. Ohne Zustand
  /// bleibt die RPC unbeantwortet (das Bild zeigt dann den Fehler).
  Future<void> zeigeQuiz(
    WidgetTester tester, {
    Map<String, dynamic>? zustand,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    if (zustand != null) {
      server.rpcAntworten['get_match_quiz_state'] = zustand;
    }

    final router = GoRouter(
      initialLocation: '/quiz',
      routes: [
        GoRoute(
          path: '/quiz',
          builder: (context, state) => const QuizScreen(matchId: _matchId),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Raeumt den Screen ab (die Timer des Quiz-Screens werden beendet).
  Future<void> raeumeAuf(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('Das Match-Quiz', () {
    testWidgets('ohne Serverantwort gibt es eine Fehlermeldung', (
      tester,
    ) async {
      await zeigeQuiz(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('quiz.loadError')), findsOneWidget);
      await raeumeAuf(tester);
    });

    testWidgets('vor dem ersten Versuch ist das Foto verdeckt', (tester) async {
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 0,
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('quiz.startTitle')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('quiz.photoHidden')),
        findsOneWidget,
      );
      await raeumeAuf(tester);
    });

    testWidgets('der Versuch stellt eine Frage vom Server', (tester) async {
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'questionId': 'frage-1',
        'prompt': 'Wie heisst dein Match?',
        'options': <String>['Mira', 'Jona'],
      };
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 0,
        },
      );

      await tester.tap(find.text(L10n.tWithoutContext('quiz.startAttempt')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('Wie heisst dein Match?'), findsOneWidget);
      expect(find.text('Mira'), findsOneWidget);
      expect(find.text('Jona'), findsOneWidget);
      await raeumeAuf(tester);
    });

    testWidgets('die falsche Antwort meldet den Fehlversuch', (tester) async {
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'questionId': 'frage-1',
        'prompt': 'Wie heisst dein Match?',
        'options': <String>['Mira', 'Jona'],
      };
      server.rpcAntworten['submit_quiz_answer'] = <String, dynamic>{
        'correct': false,
        'passed': false,
        'failedAttempts': 1,
        'unlockLevel': 0,
      };
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 0,
        },
      );

      await tester.tap(find.text(L10n.tWithoutContext('quiz.startAttempt')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Eine Antwort waehlen und absenden.
      await tester.tap(find.text('Mira'));
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('quiz.submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('quiz.wrongTitle')),
        findsOneWidget,
      );
      await raeumeAuf(tester);
    });

    testWidgets('die richtige Antwort wartet auf den Partner', (tester) async {
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'questionId': 'frage-1',
        'prompt': 'Wie heisst dein Match?',
        'options': <String>['Mira', 'Jona'],
      };
      server.rpcAntworten['submit_quiz_answer'] = <String, dynamic>{
        'correct': true,
        'passed': false,
        'waitingForPartner': true,
      };
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 0,
        },
      );

      await tester.tap(find.text(L10n.tWithoutContext('quiz.startAttempt')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Mira'));
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('quiz.submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('quiz.correctTitle')),
        findsOneWidget,
      );
      await raeumeAuf(tester);
    });

    testWidgets('eine geschlossene Runde wird erklaert', (tester) async {
      // Die Frage wird beim Laden der Runde geholt - die Antwort muss
      // also VOR dem Aufbau stehen.
      server.rpcAntworten['start_quiz_attempt'] = <String, dynamic>{
        'questionId': 'frage-1',
        'prompt': 'Wie heisst dein Match?',
        'options': <String>['Mira', 'Jona'],
      };
      server.rpcAntworten['submit_quiz_answer'] = <String, dynamic>{
        'error': 'round_closed',
      };
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 0,
          'currentQuestionId': 'frage-1',
        },
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Mira'));
      await tester.pump();
      // Der Server meldet: die Runde ist vorbei. Der Zustand danach
      // hat keine laufende Runde mehr - sonst laedt der Screen die
      // Frage neu und der Hinweis verschwindet wieder.
      server.rpcAntworten['get_match_quiz_state'] = <String, dynamic>{
        'matchId': _matchId,
        'partnerId': 'partner-1',
        'unlockLevel': 0,
        'failedAttempts': 0,
      };
      await tester.tap(find.text(L10n.tWithoutContext('quiz.submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('quiz.roundClosed')),
        findsOneWidget,
      );
      await raeumeAuf(tester);
    });

    testWidgets('der Cooldown laeuft nach einem Fehlversuch', (tester) async {
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 0,
          'failedAttempts': 1,
          'nextAttemptAt': DateTime.now()
              .add(const Duration(minutes: 2))
              .toIso8601String(),
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      // Der Cooldown zeigt die Restzeit.
      expect(
        find.textContaining('01:'),
        findsWidgets,
        reason: 'Der Cooldown zeigt die verbleibende Zeit.',
      );
      await raeumeAuf(tester);
    });

    testWidgets('das bestandene Quiz zeigt das Foto und den Hinweis', (
      tester,
    ) async {
      await zeigeQuiz(
        tester,
        zustand: <String, dynamic>{
          'matchId': _matchId,
          'partnerId': 'partner-1',
          'unlockLevel': 2,
          'failedAttempts': 0,
          'passedAt': DateTime.now().toIso8601String(),
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('quiz.passedBadge')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await raeumeAuf(tester);
    });
  });
}
