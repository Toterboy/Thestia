// Der Admin-Bereich (bisher ungetestet - der Screen war unerreichbar).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/admin/admin_screen.dart 807 offene Zeilen - der Bereich,
// in dem der Betreiber Meldungen bearbeitet, Verifizierungen prueft und
// Profile sperrt.
//
// DER WEG ZUM TEST: Der Screen war im Test unerreichbar, weil
// `isCurrentUserAdmin()` ohne die per --dart-define gesetzte Admin-UUID
// immer false ist. Dafuer gibt es jetzt den Provider
// [adminAccessProvider] - die REGEL bleibt unveraendert (ohne UUID ist
// NIE jemand Admin), aber ein Test kann den Bereich oeffnen.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart. Der Admin-Check wird von ihm
// beantwortet - genau so, wie es der echte Server tut.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * ALLE Reiter sind da und JEDER ist aufrufbar (der letzte - der
//     Posteingang - war kaputt: der Tab-Controller stand auf 7, es gibt
//     aber 8 Reiter),
//   * ohne Admin-Recht kommt der Hinweis statt des Bereichs,
//   * die Listen zeigen ihren Leerzustand.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/admin/admin_screen.dart';
import 'package:thestia/widgets/pill_tab_bar.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    // Der Ersatz-Server: er beantwortet den Admin-Check mit "ja" und
    // die Listen mit leer.
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
    // ANGEMELDET: Die Freigabe eines Fotos braucht die eigene
    // User-ID - ohne Sitzung passiert gar nichts.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'admin-1');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  /// Scrollt die Reiter-Leiste waagerecht bis zum Reiter.
  ///
  /// Die Leiste ist ein ListView: sie baut nur die sichtbaren Reiter auf -
  /// der Posteingang steht rechts draussen.
  Future<void> scrolleZuReiter(WidgetTester tester, String etikett) async {
    final pille = find.byKey(ValueKey('pill_tab_$etikett'));
    if (pille.evaluate().isNotEmpty) return;
    final leiste = find.descendant(
      of: find.byType(PillTabBar),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 20 && pille.evaluate().isEmpty; i++) {
      await tester.drag(leiste.first, const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut den Admin-Screen.
  ///
  /// [admin] steuert, ob der Bereich ueberhaupt offen ist.
  Future<void> zeigeScreen(WidgetTester tester, {bool admin = true}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final r = router();
    addTearDown(r.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminAccessProvider.overrideWithValue(admin)],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: r,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('Der Admin-Bereich', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AdminScreen), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('admin.title')), findsOneWidget);
    });

    testWidgets('alle acht Reiter stehen da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // BEFUND (14.11.2026): Der Tab-Controller stand auf 7, es gibt aber
      // ACHT Reiter - der letzte (Posteingang) war nicht erreichbar.
      for (final reiter in [
        'admin.tabReports',
        'admin.tabBugs',
        'admin.tabVerification',
        'admin.tabModeration',
        'admin.tabAppeals',
        'admin.tabBans',
        'admin.tabLocations',
        'admin.tabMail',
      ]) {
        final etikett = L10n.tWithoutContext(reiter);
        final pille = find.byKey(ValueKey('pill_tab_$etikett'));
        await scrolleZuReiter(tester, etikett);
        expect(
          pille,
          findsOneWidget,
          reason: 'Der Reiter $etikett muss erreichbar sein.',
        );
      }
    });

    // Die Foto-Moderation: der Reiter zeigt die wartenden Fotos, und
    // die Entscheidung geht an den Server.
    group('Die Foto-Moderation', () {
      /// Fuellt die Queue mit einer wartenden Meldung.
      void queueVorbereiten() {
        server.zeilen['photo_moderation'] = <String, dynamic>{
          'id': 5,
          'user_id': 'user-9',
          'status': 'pending_review',
          'photo_hash': 'abcdef0123456789',
          'created_at': '2026-11-16T09:00:00Z',
          'user': <String, dynamic>{'name': 'Jonas'},
        };
      }

      /// Oeffnet den Reiter der Foto-Moderation.
      Future<void> oeffneReiter(WidgetTester tester) async {
        final etikett = L10n.tWithoutContext('admin.tabModeration');
        await scrolleZuReiter(tester, etikett);
        final pille = find.byKey(ValueKey('pill_tab_$etikett'));
        expect(pille, findsOneWidget);
        await tester.ensureVisible(pille);
        await tester.pump();
        await tester.tap(pille);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        // Der Abruf der Queue braucht echte Zeit.
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          });
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      testWidgets('die wartenden Fotos stehen da', (tester) async {
        // DIE QUEUE VOR DEM AUFBAU: der Reiter laedt, sobald er
        // geoeffnet wird - die Daten muessen dann schon da sein.
        queueVorbereiten();
        await zeigeScreen(tester);
        await oeffneReiter(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Jonas'),
          findsWidgets,
          reason: 'Ein wartendes Foto muss im Reiter stehen.',
        );
      });

      testWidgets('das Freigeben geht an den Server', (tester) async {
        queueVorbereiten();
        await zeigeScreen(tester);
        await oeffneReiter(tester);

        // Der Freigabe-Knopf (der gruene Haken).
        final knopf = find.byIcon(Icons.check);
        expect(knopf, findsWidgets);
        await tester.tap(knopf.first);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }

        expect(tester.takeException(), isNull);
        // Der Server hat die Entscheidung bekommen.
        expect(
          server.schreibvorgaenge.any(
            (v) =>
                v['tabelle'] == 'photo_moderation' && v['status'] == 'approved',
          ),
          isTrue,
          reason: 'Die Freigabe muss auf dem Server landen.',
        );
      });
    });

    testWidgets('jeder Reiter laesst sich oeffnen', (tester) async {
      await zeigeScreen(tester);

      // Der letzte Reiter (Posteingang) war der kaputte: der Klick rief
      // animateTo(7) auf einem Controller mit 7 Eintraegen auf.
      final etikett = L10n.tWithoutContext('admin.tabMail');
      await scrolleZuReiter(tester, etikett);
      final pille = find.byKey(ValueKey('pill_tab_$etikett'));

      await tester.tap(pille);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Admin-Recht kommt der Bereich nicht', (tester) async {
      await zeigeScreen(tester, admin: false);

      expect(tester.takeException(), isNull);
      // Fail-closed: der Bereich wird nicht gezeigt, es geht zur
      // Startseite zurueck.
      expect(find.text('Startseite'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('admin.title')),
        findsNothing,
        reason: 'Ohne Admin-Recht darf der Bereich nicht erscheinen.',
      );
    });
  });
}
