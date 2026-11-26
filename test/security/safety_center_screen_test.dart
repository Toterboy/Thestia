// Das Sicherheitscenter - bisher ungetestet (2,8 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/screens/safety/safety_center_screen.dart 140 offene Zeilen bei 144
// Zeilen gesamt - der Bildschirm, auf dem ein Nutzer Hilfe bei
// Belästigung findet, war komplett ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Hilfetelefone und die Schutz-Kacheln stehen da,
//   * die beiden Listen (blockierte Nutzer, eigene Meldungen) haben je
//     einen EIGENEN Screen - hier steht nur der Einstieg.
//     Die Listen selbst werden in safety_lists_screens_test.dart
//     geprüft.
//
// NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen sollen
// beide als einzelne Screens, damit der Safety Center Screen nicht
// überladen wird, wenn es viele blockierungen und oder Meldungen
// gibt."
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

    testWidgets('die beiden Listen haben je einen eigenen Screen', (
      tester,
    ) async {
      // NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen
      // sollen beide als einzelne Screens, damit der Safety Center
      // Screen nicht überladen wird, wenn es viele blockierungen
      // und oder Meldungen gibt."
      //
      // Der Safety Center zeigt also nur die EINSTIEGE - die Listen
      // selbst stehen in eigenen Screens (test dafür:
      // safety_lists_screens_test.dart).
      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      await scrollZu(
        tester,
        find.text(L10n.tWithoutContext('safety.blockedUsers')),
      );
      expect(
        find.text(L10n.tWithoutContext('safety.blockedUsersSub')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safety.myReportsSub')),
        findsOneWidget,
      );
    });

    testWidgets('die Listen selbst stehen nicht mehr im Safety Center', (
      tester,
    ) async {
      server.rpcAntworten['list_my_reports'] = <dynamic>[
        <String, dynamic>{
          'id': 'r1',
          'reportType': 'Belästigung / Beleidigungen',
          'status': 'pending',
          'createdAt': '2026-11-01T10:00:00Z',
        },
      ];
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
      // Die Einträge selbst dürfen hier NICHT mehr stehen.
      expect(find.text('Belästigung / Beleidigungen'), findsNothing);
      expect(find.text('Mira'), findsNothing);
    });
  });
}
