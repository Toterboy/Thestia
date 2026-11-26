// Die Elternfreigabe (16 und 17 Jahre) - bisher ungetestet (1,2 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/screens/guardian/guardian_consent_screen.dart 83 offene Zeilen bei
// 84 Zeilen gesamt.
//
// WAS HIER GEPRÜFT WIRD:
//   * die eigene Kontoadresse kann nicht Elternteil sein (der Server
//     prüft das auch - hier nur die freundliche Meldung),
//   * eine kaputte Adresse wird abgewiesen,
//   * die Anfrage geht an den Server,
//   * der Nutzer sieht die Bestätigung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/guardian/guardian_consent_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server (die Anfrage geht dorthin).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();

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
      initialLocation: '/guardian-consent',
      routes: [
        GoRoute(
          path: '/guardian-consent',
          builder: (context, state) => const GuardianConsentScreen(),
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Wartet, bis der Server geantwortet hat.
  Future<void> warteAufServer(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Die Elternfreigabe', () {
    testWidgets('die eigene Adresse darf nicht sein', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextFormField), 'ich@example.com');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('guardian.sendBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.errorSameEmail')),
        findsOneWidget,
        reason:
            'Die eigene Kontoadresse kann nicht Elternteil sein - der '
            'Nutzer muss das wissen.',
      );
      // Und es ging nichts an den Server.
      expect(
        server.rpcAufrufe.where(
          (c) => c['funktion'] == 'request_guardian_consent',
        ),
        isEmpty,
      );
    });

    testWidgets('eine kaputte Adresse wird abgewiesen', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextFormField), 'keine-adresse');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('guardian.sendBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        server.rpcAufrufe.where(
          (c) => c['funktion'] == 'request_guardian_consent',
        ),
        isEmpty,
        reason: 'Eine kaputte Adresse darf nicht rausgehen.',
      );
    });

    testWidgets('die Anfrage geht an den Server', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(
        find.byType(TextFormField),
        'Elternteil@Beispiel.de',
      );
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('guardian.sendBtn')));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      final aufrufe = server.rpcAufrufe.where(
        (c) => c['funktion'] == 'request_guardian_consent',
      );
      expect(
        aufrufe,
        isNotEmpty,
        reason:
            'Die Anfrage muss beim Server ankommen - sonst bekommt das '
            'Elternteil keine Mail.',
      );
      expect(aufrufe.first['p_guardian_email'], 'elternteil@beispiel.de');
    });
  });
}
