// Die beiden Listen des Safety Centers haben je einen eigenen Screen
// (NUTZERWUNSCH 22.11.2026): "Blockierte Nutzer und Meldungen sollen
// beide als einzelne Screens, damit der Safety Center Screen nicht
// ueberladen wird, wenn es viele blockierungen und oder Meldungen
// gibt."
//
// Vorher standen beide Listen direkt im Safety Center. Die Tests fuer
// die Listen stehen jetzt hier - der Safety Center selbst tested nur
// noch, dass die beiden Einstiege vorhanden sind (siehe
// safety_center_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/safety/blocked_users_screen.dart';
import 'package:thestia/screens/safety/my_reports_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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
    server.rpcAufrufe.clear();
  });

  /// Baut einen Bildschirm.
  Future<void> zeige(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: ThemeData(useMaterial3: true), home: screen),
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

  group('Die Meldungen', () {
    testWidgets('ohne Meldungen steht das da', (tester) async {
      server.rpcAntworten['list_my_reports'] = <dynamic>[];

      await zeige(tester, const MyReportsScreen());
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
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

      await zeige(tester, const MyReportsScreen());
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Belästigung / Beleidigungen'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      // Der Status steht dabei - der Nutzer muss wissen, was passiert ist.
      expect(find.text('Wird geprüft'), findsOneWidget);
      expect(find.text('Wurde geprüft'), findsOneWidget);
    });
  });

  group('Die blockierten Nutzer', () {
    testWidgets('ohne blockierte Nutzer steht das da', (tester) async {
      server.rpcAntworten['list_blocked_users'] = <dynamic>[];

      await zeige(tester, const BlockedUsersScreen());
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
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

      await zeige(tester, const BlockedUsersScreen());
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
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
