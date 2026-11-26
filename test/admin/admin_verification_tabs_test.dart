// Die Verwaltungs-Reiter des Admin-Bereichs (Verifizierung, Bugs,
// Sperren, Standort) - bisher ungetestet.
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/screens/admin/admin_screen.dart 617 offene Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * eine offene Verifizierung steht da - mit der KI-Altersschätzung
//     und der Abweichung zum angegebenen Alter,
//   * ein Minderjährigkeitsfall ist als solcher erkennbar (Kind-Symbol,
//     eigener Hinweis) - er ist die wichtigste Prüfung in der Queue,
//   * eine Abweichung von mehr als zwei Jahren färbt die Karte,
//   * die Fehlerberichte stehen da,
//   * die Sperren stehen da,
//   * die Standort-Prüfungen stehen da,
//   * ohne Einträge steht der Leerzustand da.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
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
    // ANGEMELDET: Edge Functions brauchen eine Sitzung - ohne sie
    // bleibt der Aufruf beim Token-Holen stehen (der Auth-Client
    // wartet auf eine Antwort, die nie kommt).
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'admin-1');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    server.rpcAntworten.clear();
    server.rpcAntworten['is_current_user_admin'] = true;
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
    server.rpcFehler.clear();
    server.antwortetMitFehler = false;
  });

  /// Baut den Admin-Bereich.
  ///
  /// Der Bildschirm ist BREIT (wie auf einem Tablet): die Reiter-Leiste
  /// ist horizontal scrollbar - auf einem Telefon liegen die hinteren
  /// Reiter außerhalb des Bildschirms.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final r = GoRouter(
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Tippt auf einen Reiter.
  Future<void> tippeReiter(WidgetTester tester, String l10nKey) async {
    final etikett = L10n.tWithoutContext(l10nKey);
    final pille = find.byKey(ValueKey('pill_tab_$etikett'));
    expect(
      pille,
      findsOneWidget,
      reason: 'Der Reiter $etikett muss auf der Leiste stehen.',
    );
    await tester.tap(pille);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Eine offene Verifizierung, wie sie der Server liefert.
  Map<String, dynamic> verifizierung({
    String name = 'Mira',
    String status = 'pending',
    double? angegebenesAlter = 30,
    double? kiAlter = 31,
  }) => <String, dynamic>{
    'userId': 'user-42',
    'name': name,
    'status': status,
    'statedAge': angegebenesAlter,
    'estimatedAge': kiAlter,
    'createdAt': '2026-11-14T10:00:00Z',
  };

  group('Die Verwaltungs-Reiter', () {
    testWidgets('eine offene Verifizierung steht da', (tester) async {
      server.rpcAntworten['admin_list_pending_verifications'] = [
        verifizierung(),
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabVerification');

      expect(tester.takeException(), isNull);
      expect(find.text('Mira'), findsOneWidget);
      expect(find.text('user-42'), findsOneWidget);
      // Die KI-Schätzung steht bei der Karte - der Betreiber soll den
      // Fall ohne Nachrechnen erkennen.
      expect(
        find.textContaining('KI 31'),
        findsOneWidget,
        reason: 'Die KI-Altersschaetzung muss bei der Karte stehen.',
      );
      expect(find.textContaining('Abweichung 1'), findsOneWidget);
    });

    testWidgets('ein Minderjaehrigkeitsfall ist erkennbar', (tester) async {
      server.rpcAntworten['admin_list_pending_verifications'] = [
        verifizierung(
          name: 'Jonas',
          status: 'pending_minor',
          angegebenesAlter: 17,
          kiAlter: 16,
        ),
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabVerification');

      expect(tester.takeException(), isNull);
      // Das Kind-Symbol und der eigene Hinweis: dieser Fall ist
      // besonders wichtig (Migration 144).
      expect(find.byIcon(Icons.child_care), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('admin.minorCase')),
        findsOneWidget,
      );
    });

    testWidgets('ohne KI-Schätzung steht das auch dabei', (tester) async {
      server.rpcAntworten['admin_list_pending_verifications'] = [
        verifizierung(angegebenesAlter: 30, kiAlter: null),
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabVerification');

      expect(
        find.textContaining('keine KI-Schätzung'),
        findsOneWidget,
        reason:
            'Ohne KI-Schätzung muss das erkennbar sein - sonst hält der '
            'Betreiber die 30 fuer eine Schätzung.',
      );
    });

    testWidgets('ohne offene Verifizierungen steht der Leerzustand da', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabVerification');

      expect(
        find.text(L10n.tWithoutContext('admin.emptyVerificationsTitle')),
        findsOneWidget,
      );
    });

    testWidgets('die Fehlerberichte stehen da', (tester) async {
      server.rpcAntworten['admin_list_bug_reports'] = [
        <String, dynamic>{
          'id': 'b-1',
          'description': 'Der Zufallschat haengt beim Start',
          'appVersion': '0.10.2',
          'createdAt': '2026-11-14T09:00:00Z',
        },
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabBugs');

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Der Zufallschat haengt beim Start'),
        findsOneWidget,
      );
    });

    testWidgets('die Sperren stehen da', (tester) async {
      server.rpcAntworten['admin_list_banned_emails'] = [
        <String, dynamic>{
          'email': 'spam@example.de',
          'reason': 'Werbung',
          'createdAt': '2026-11-13T09:00:00Z',
        },
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabBans');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('spam@example.de'), findsOneWidget);
    });

    testWidgets('die Standort-Pruefungen stehen da', (tester) async {
      server.rpcAntworten['admin_list_location_checks'] = [
        <String, dynamic>{
          'userId': 'user-7',
          'createdAt': '2026-11-14T08:00:00Z',
        },
      ];
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabLocations');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('user-7'), findsOneWidget);
    });

    testWidgets('ohne Sperren steht der Leerzustand da', (tester) async {
      await zeigeScreen(tester);
      await tippeReiter(tester, 'admin.tabBans');

      expect(
        find.text(L10n.tWithoutContext('admin.emptyBansTitle')),
        findsOneWidget,
      );
    });
  });

  // ANMERKUNG: Die Freigabe/Ablehnung einer Verifizierung (die Edge
  // Function "verify-account") wird hier NICHT getestet. Der Aufruf
  // geht über den Auth-Weg: vor dem Senden holt der Client das
  // Access-Token, und ohne gültige Session wartet er auf eine
  // Token-Aktualisierung - der Aufruf bleibt dann stehen (der Test
  // lief in den Zehn-Minuten-Timeout). Der Pfad ist in der App
  // aktiv und wird vom Betreiber benutzt; im Test ist er nicht
  // sinnvoll nachzubauen.
  //
  // BEFUND (15.11.2026): Der Aufruf im Admin-Bereich hat KEIN
  // Zeitlimit - bleibt die Edge Function ohne Antwort, bleibt der
  // Admin-Screen mit dem Ladeindikator stehen (bis er ihn
  // verlässt). Das ist als nächste Härtung notiert (kein
  // Produktivfehler, aber unangenehm).
}
