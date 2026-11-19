// Der Mood-of-the-Day - bisher ungetestet (1,0 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/mood/mood_picker_screen.dart 103 offene Zeilen bei 104
// Zeilen gesamt - der Bildschirm, ueber den der Nutzer seinen Tages-Mood
// waehlt, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * alle Moods stehen zur Auswahl,
//   * ohne Auswahl kann nicht gespeichert werden,
//   * der gewaehlte Mood geht an den Server,
//   * der aktuelle Mood des Tages wird angezeigt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_mood.dart';
import 'package:thestia/screens/mood/mood_picker_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server (der Mood kommt von dort).
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
    server.rpcAufrufe.clear();
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/mood',
          builder: (context, state) => const MoodPickerScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    // DER BILDSCHIRM WIRD GEOEFFNET (nicht als Start-Route) - sonst kann
    // der "Zurueck"-Knopf nichts zurueckgeben.
    router.push('/mood');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Wartet, bis der Server geantwortet hat.
  Future<void> warteAufServer(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Der Mood des Tages', () {
    testWidgets('alle Moods stehen zur Auswahl', (tester) async {
      server.rpcAntworten['get_user_mood'] = null;

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('mood.question')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('mood.explainer')), findsOneWidget);
      for (final mood in Mood.values) {
        expect(
          find.text(L10n.tWithoutContext(mood.labelKey)),
          findsOneWidget,
          reason: 'Der Mood "${mood.value}" muss zur Auswahl stehen.',
        );
      }
    });

    testWidgets('der aktuelle Mood wird angezeigt', (tester) async {
      server.rpcAntworten['get_user_mood'] = 'happy';

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('mood.current')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, welchen Mood er heute hat.',
      );
    });

    testWidgets('ohne Auswahl kann nicht gespeichert werden', (tester) async {
      server.rpcAntworten['get_user_mood'] = null;

      await zeigeScreen(tester);
      await warteAufServer(tester);

      final knopf = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('mood.save'),
      );
      final widget = tester.widget<FilledButton>(knopf);
      expect(
        widget.onPressed,
        isNull,
        reason: 'Ohne Auswahl gibt es nichts zu speichern.',
      );
    });

    testWidgets('der gewaehlte Mood geht an den Server', (tester) async {
      server.rpcAntworten['get_user_mood'] = null;

      await zeigeScreen(tester);
      await warteAufServer(tester);

      // Den ersten Mood waehlen.
      final auswahl = find.text(
        L10n.tWithoutContext(Mood.values.first.labelKey),
      );
      await tester.tap(auswahl);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Und speichern.
      final knopf = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('mood.save'),
      );
      await tester.ensureVisible(knopf);
      await tester.tap(knopf);
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      final aufrufe = server.rpcAufrufe.where(
        (c) => c['funktion'] == 'set_user_mood',
      );
      expect(
        aufrufe,
        isNotEmpty,
        reason:
            'Der Mood muss beim Server ankommen - sonst sieht ihn '
            'niemand.',
      );
      expect(aufrufe.first['p_mood'], Mood.values.first.value);
      // Und der Bildschirm wird verlassen.
      expect(find.text('Startseite'), findsOneWidget);
    });
  });
}
