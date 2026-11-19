// Das Sicherheitscenter - bisher ungetestet (2,8 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/safety/safety_center_screen.dart 140 offene Zeilen bei 144
// Zeilen gesamt - der Bildschirm, auf dem ein Nutzer Hilfe bei
// Belästigung findet, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Hilfetelefone und die Schutz-Kacheln stehen da,
//   * die eigenen Meldungen werden angezeigt (mit ihrem Status),
//   * blockierte Nutzer werden angezeigt und koennen entsperrt werden,
//   * ohne Meldungen/blockierte Nutzer steht das ehrlich da.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/safety/safety_center_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server (Meldungen und Sperrliste kommen von dort).
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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const SafetyCenterScreen(),
        ),
      ),
    );
    await tester.pump();
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

  /// Scrollt, bis [finder] sichtbar ist.
  Future<void> scrollZu(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Das Sicherheitscenter', () {
    testWidgets('die Hilfetelefone stehen da', (tester) async {
      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safety.hotline1')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safety.hotline2')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safety.sectionHelp')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safety.sectionProtect')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Meldungen steht das da', (tester) async {
      server.rpcAntworten['list_my_reports'] = <dynamic>[];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      await scrollZu(
        tester,
        find.text(L10n.tWithoutContext('safety.myReports')),
      );
      expect(
        find.text(L10n.tWithoutContext('safety.noReports')),
        findsOneWidget,
      );
    });

    testWidgets('die eigenen Meldungen werden gezeigt', (tester) async {
      server.rpcAntworten['list_my_reports'] = <dynamic>[
        <String, dynamic>{
          'id': 'r1',
          'reportType': 'Belästigung / Beleidigungen',
          'status': 'pending',
          'createdAt': '2026-11-01T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'r2',
          'reportType': 'Spam',
          'status': 'reviewed',
          'createdAt': '2026-11-02T10:00:00Z',
        },
      ];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      await scrollZu(
        tester,
        find.text(L10n.tWithoutContext('safety.myReports')),
      );
      expect(find.text('Belästigung / Beleidigungen'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      // Der Status steht dabei - der Nutzer muss wissen, was passiert ist.
      expect(find.text('Wird geprüft'), findsOneWidget);
      expect(find.text('Wurde geprüft'), findsOneWidget);
    });

    testWidgets('ohne blockierte Nutzer steht das da', (tester) async {
      server.rpcAntworten['list_blocked_users'] = <dynamic>[];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      await scrollZu(
        tester,
        find.text(L10n.tWithoutContext('safety.blockedUsers')),
      );
      expect(
        find.text(L10n.tWithoutContext('safety.noBlocked')),
        findsOneWidget,
      );
    });

    testWidgets('ein blockierter Nutzer laesst sich entsperren', (
      tester,
    ) async {
      server.rpcAntworten['list_blocked_users'] = <dynamic>[
        <String, dynamic>{
          'blockedUserId': 'partner-1',
          'name': 'Mira',
          'createdAt': '2026-11-01T10:00:00Z',
        },
      ];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      await scrollZu(tester, find.text('Mira'));
      expect(find.text('Mira'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('safety.unblock')),
      );
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'unblock_user'),
        isTrue,
        reason:
            'Das Entsperren muss beim Server ankommen - sonst bleibt der '
            'Nutzer gesperrt.',
      );
    });
  });
}
