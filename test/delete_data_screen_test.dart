// Die selektive Datenloeschung (DSGVO) - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/privacy/delete_data_screen.dart 131 offene Zeilen bei 132
// Zeilen gesamt - der Bildschirm, ueber den der Nutzer einzelne Daten
// loeschen kann, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * alle loeschbaren Kategorien stehen da,
//   * ohne Auswahl ist der Loesch-Knopf gesperrt,
//   * vor dem Loeschen kommt eine Rueckfrage (das ist endgueltig),
//   * nach dem Bestaetigen geht der Auftrag an den Server,
//   * beim Abbruch passiert nichts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/privacy/delete_data_screen.dart';
import 'package:thestia/widgets/buttons.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server (die Loeschung geht an die Edge Function).
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
    // DER SERVER: Die Loeschung war erfolgreich.
    server.funktionsAntworten['delete-user-data'] = <String, dynamic>{
      'ok': true,
      'geloescht': <String, dynamic>{},
      'warnungen': <dynamic>[],
    };
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/delete-data',
      routes: [
        GoRoute(
          path: '/delete-data',
          builder: (context, state) => const DeleteDataScreen(),
        ),
        GoRoute(
          path: AppRoutes.privacy,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Datenschutz'))),
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
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Scrollt, bis [finder] sichtbar ist.
  ///
  /// DER GRUND: Die Seite ist eine Liste - was weiter unten steht, wird
  /// erst gebaut, wenn man dorthin scrollt.
  Future<void> scrollZu(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Die selektive Datenloeschung', () {
    testWidgets('alle Kategorien stehen da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(CheckboxListTile), findsWidgets);
      expect(find.text(L10n.tWithoutContext('del.fotos')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('del.profil')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('del.standort')), findsOneWidget);
      await scrollZu(tester, find.text(L10n.tWithoutContext('del.allTitle')));
      expect(find.text(L10n.tWithoutContext('del.allTitle')), findsOneWidget);
    });

    testWidgets('ohne Auswahl ist der Knopf gesperrt', (tester) async {
      await zeigeScreen(tester);

      await scrollZu(tester, find.byType(PrimaryButton));
      final knopf = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        knopf.onPressed,
        isNull,
        reason:
            'Ohne Auswahl darf nichts geloescht werden - sonst waere der '
            'Knopf eine Falle.',
      );
    });

    testWidgets('vor dem Loeschen kommt die Rueckfrage', (tester) async {
      await zeigeScreen(tester);

      // Die erste Kategorie waehlen.
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Und den Loesch-Knopf druecken.
      final knopf = find.byType(PrimaryButton);
      await scrollZu(tester, knopf);
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('del.confirmTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('del.irreversible')),
        findsOneWidget,
      );
      // Und es ist noch nichts geloescht worden.
      expect(server.funktionsAufrufe, isEmpty);
    });

    testWidgets('nach dem Bestaetigen geht der Auftrag raus', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final knopf = find.byType(PrimaryButton);
      await scrollZu(tester, knopf);
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bestaetigen.
      final bestaetigen = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('del.deleteBtn'),
        ),
      );
      await tester.tap(bestaetigen);
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe,
        hasLength(1),
        reason: 'Die Loeschung muss beim Server ankommen.',
      );
      expect(server.funktionsAufrufe.first['funktion'], 'delete-user-data');
      expect(
        server.funktionsAufrufe.first['kategorien'],
        isNotNull,
        reason: 'Der Server muss wissen, WAS geloescht werden soll.',
      );
      // Und der Nutzer bekommt die Bestaetigung.
      expect(find.text(L10n.tWithoutContext('del.doneTitle')), findsOneWidget);
    });

    testWidgets('beim Abbruch passiert nichts', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final knopf = find.byType(PrimaryButton);
      await scrollZu(tester, knopf);
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Abbrechen.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe,
        isEmpty,
        reason: 'Nach dem Abbruch darf nichts geloescht werden.',
      );
    });

    testWidgets('alles loeschen geht auch', (tester) async {
      await zeigeScreen(tester);

      final alles = find.widgetWithText(
        OutlinedButton,
        L10n.tWithoutContext('del.allBtn'),
      );
      await scrollZu(tester, alles);
      await tester.tap(alles);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('del.deleteBtn'),
          ),
        ),
      );
      await tester.pump();
      await warteAufServer(tester);

      expect(server.funktionsAufrufe, hasLength(1));
      expect(server.funktionsAufrufe.first['kategorien'], contains('alles'));
    });
  });
}
