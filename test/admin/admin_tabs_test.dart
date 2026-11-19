// Die Reiter des Admin-Bereichs (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/admin/admin_screen.dart 714 offene Zeilen - der Bereich,
// in dem der Betreiber Meldungen bearbeitet, Verifizierungen prueft und
// Profile sperrt.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Meldungen stehen da (mit Typ, gemeldeter Person und Datum),
//   * "Erledigt" meldet es an den Server,
//   * ohne Meldungen steht der Leerzustand da,
//   * ein Serverfehler zeigt die Fehlermeldung MIT Wiederholen,
//   * die Kennzahlen oben zaehlen die offenen Meldungen.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart. Der Admin-Check wird von ihm
// beantwortet, die Listen kommen aus seinen RPC-Antworten.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/admin/admin_screen.dart';

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

    server = FakeSupabaseServer(userId: 'admin-1');
    server.rpcAntworten['is_current_user_admin'] = true;
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
    TestWidgetsFlutterBinding.ensureInitialized();
    // Alle Listen sind zuerst leer - jeder Test stellt seine own.
    server.rpcAntworten.clear();
    server.rpcAntworten['is_current_user_admin'] = true;
    // DIE LISTEN-RPCS: Der Ersatz-Server antwortet auf eine unbekannte
    // RPC mit null - und die Kennzahlen-Zeile waere dann weg (statt
    // "0" zu zeigen). Also beantwortet der Test jede Liste leer.
    for (final rpc in [
      'admin_list_user_reports',
      'admin_list_bug_reports',
      'admin_list_pending_verifications',
      'admin_list_auto_verifications',
      'admin_list_banned_emails',
      'admin_list_photo_appeals',
      'admin_list_location_checks',
      'admin_list_mail_messages',
    ]) {
      server.rpcAntworten[rpc] = <dynamic>[];
    }
    server.pfade.clear();
    // Der Server antwortet wieder - auch wenn der vorige Test ihn
    // stummgeschaltet hat (sonst wuerde der Fehler in den nächsten
    // Test durchschlagen).
    server.antwortetMitFehler = false;
    server.rpcFehler.clear();
  });

  /// Der Router: der Admin-Bereich wird per `go` erreicht.
  GoRouter router() {
    return GoRouter(
      initialLocation: AppRoutes.admin,
      routes: [
        GoRoute(
          path: AppRoutes.admin,
          builder: (context, state) => const AdminScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
  }

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Baut den Admin-Bereich.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final r = router();
    addTearDown(r.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminAccessProvider.overrideWithValue(true)],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: r,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// Eine Meldung, wie sie der Server liefert.
  Map<String, dynamic> meldung({String id = 'r-1'}) => <String, dynamic>{
    'id': id,
    'reportType': 'unangemessene Nachricht',
    'description': 'Bitte pruefen, das ist nicht in Ordnung.',
    'status': 'pending',
    'reportedUserId': 'user-42',
    'reporterId': 'user-7',
    'messages': <dynamic>[],
    'createdAt': '2026-11-14T10:00:00Z',
  };

  group('Der Admin-Bereich (die Reiter)', () {
    testWidgets('die Meldungen stehen da', (tester) async {
      server.rpcAntworten['admin_list_user_reports'] = [meldung()];
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Die Meldung steht da - mit Typ, gemeldeter Person und Datum.
      expect(find.text('unangemessene Nachricht'), findsOneWidget);
      expect(
        find.textContaining('user-42'),
        findsOneWidget,
        reason: 'Die gemeldete Person muss benannt sein.',
      );
      expect(find.textContaining('Bitte pruefen'), findsOneWidget);
      // Und sie ist als offen markiert.
      expect(
        find.text(L10n.tWithoutContext('admin.statusPending')),
        findsOneWidget,
      );
    });

    testWidgets('"Erledigt" meldet es an den Server', (tester) async {
      server.rpcAntworten['admin_list_user_reports'] = [meldung()];
      await zeigeScreen(tester);

      await tester.tap(find.text(L10n.tWithoutContext('admin.resolved')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(
        server.pfade.any((p) => p.contains('admin_resolve_user_report')),
        isTrue,
        reason: 'Das Abhaken muss dem Server gemeldet werden.',
      );
    });

    testWidgets('ohne Meldungen steht der Leerzustand da', (tester) async {
      server.rpcAntworten['admin_list_user_reports'] = <dynamic>[];
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Kein leeres Nichts, sondern der ausgeschriebene Zustand.
      expect(
        find.text(L10n.tWithoutContext('admin.emptyReportsTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('admin.noReports')),
        findsOneWidget,
      );
    });

    testWidgets('ein Serverfehler zeigt die Meldung mit Wiederholen', (
      tester,
    ) async {
      // NUR die Liste schweigt - der Admin-Check antwortet (sonst
      // wuerde der Bereich ganz schliessen, fail-closed).
      server.rpcFehler.add('admin_list_user_reports');
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Fehler darf NICHT wie "keine Meldungen" aussehen - der
      // Betreiber muss wissen, dass die Liste nicht geladen wurde.
      expect(
        find.textContaining(
          L10n.tWithoutContext('admin.error').replaceAll('{error}', ''),
        ),
        findsWidgets,
      );
      // Und es gibt einen Weg zurueck.
      expect(find.text(L10n.tWithoutContext('common.retry')), findsOneWidget);

      // Jetzt antwortet der Server wieder - und der Knopf holt die Liste.
      server.rpcFehler.clear();
      await tester.tap(find.text(L10n.tWithoutContext('common.retry')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('admin.noReports')),
        findsOneWidget,
        reason: 'Nach dem Wiederholen steht der Leerzustand da.',
      );
    });

    testWidgets('die Kennzahlen zaehlen die offenen Meldungen', (tester) async {
      server.rpcAntworten['admin_list_user_reports'] = [
        meldung(id: 'r-1'),
        meldung(id: 'r-2'),
        meldung(id: 'r-3'),
      ];
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Die Kennzahl "Offene Meldungen" steht oben und zaehlt die
      // wartenden Meldungen.
      expect(
        find.text(L10n.tWithoutContext('admin.metricOpenReports')),
        findsOneWidget,
      );
      // Der Reiter "Meldungen" traegt dieselbe Zahl.
      expect(find.text('3'), findsWidgets);
    });
  });
}
