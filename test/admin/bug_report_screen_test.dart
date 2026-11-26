// Der Bug-Report-Bildschirm - bisher ungetestet (0,6 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/screens/bug_report/bug_report_screen.dart 154 offene Zeilen bei
// 155 Zeilen gesamt - der Bildschirm, über den der Nutzer der App
// einen Fehler meldet, war komplett ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich und bietet alle Wege (GitHub oder privat),
//   * eine zu kurze Beschreibung wird abgewiesen (sonst kommen Reports
//     an, die niemand zuordnen kann),
//   * ein Report mit brauchbarer Beschreibung geht an den Server,
//   * der Nutzer bekommt danach die Bestätigung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/bug_report/bug_report_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server.
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
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
  });

  /// Öffnet den Bildschirm (über einen zweiten Bildschirm - damit das
  /// "Zurück" nach dem Senden funktioniert).
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BugReportScreen(),
                    ),
                  ),
                  child: const Text('oeffnen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('oeffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Der Bug-Report', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(BugReportScreen), findsOneWidget);
      // Beide Wege stehen da.
      expect(find.text(L10n.tWithoutContext('bug.github')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('bug.send')), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('eine zu kurze Beschreibung wird abgewiesen', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextFormField), 'hi');
      await tester.pump();

      final senden = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('bug.send'),
      );
      await tester.ensureVisible(senden);
      await tester.tap(senden);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Nutzer wird gewarnt...
      expect(
        find.text(L10n.tWithoutContext('bug.descShort')),
        findsOneWidget,
        reason:
            'Eine zu kurze Beschreibung hilft niemandem - der Nutzer muss '
            'erkennen, dass er mehr schreiben muss.',
      );
      // ...und es ist nichts rausgegangen.
      expect(
        server.funktionsAufrufe,
        isEmpty,
        reason: 'Ohne brauchbare Beschreibung geht kein Report raus.',
      );
    });

    testWidgets('eine leere Beschreibung wird abgewiesen', (tester) async {
      await zeigeScreen(tester);

      final senden = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('bug.send'),
      );
      await tester.ensureVisible(senden);
      await tester.tap(senden);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('bug.descMissing')),
        findsOneWidget,
      );
      expect(server.funktionsAufrufe, isEmpty);
    });

    testWidgets('der Report geht an den Server', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(
        find.byType(TextFormField),
        'Der Chat laedt beim Oeffnen nicht.',
      );
      await tester.pump();

      final senden = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('bug.send'),
      );
      await tester.ensureVisible(senden);
      await tester.tap(senden);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      // Der Report ist angekommen.
      expect(
        server.funktionsAufrufe,
        hasLength(1),
        reason: 'Der Report muss beim Server ankommen.',
      );
      expect(server.funktionsAufrufe.first['funktion'], 'send-bug-report');
      expect(
        server.funktionsAufrufe.first['description'],
        'Der Chat laedt beim Oeffnen nicht.',
      );
      // Und der Nutzer bekommt die Bestätigung.
      expect(find.text(L10n.tWithoutContext('bugreport.sent')), findsOneWidget);
    });

    testWidgets('der GitHub-Weg wird angeboten', (tester) async {
      await zeigeScreen(tester);

      expect(find.text(L10n.tWithoutContext('bug.github')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('bug.githubBody')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('bug.privateBody')),
        findsOneWidget,
      );
    });
  });
}
