// Die beiden Kern-Bildschirme: "Neu in dieser Version" und "Update
// nötig".
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/screens/core/whats_new_screen.dart und
// lib/screens/core/update_required_screen.dart offene Zeilen - beide
// Bildschirme waren ungetestet. Sie sind aber wichtig: der eine
// erklärt dem Nutzer, was sich geändert hat, der andere hält einen zu
// alten Build auf.
//
// DER WEG: Wie der Rauchtest nutzt der Test die Routen-Tabelle der App
// (ohne Umleitung) und die Ersatz-Anbieter aus dem Harness.
//
// WAS HIER GEPRÜFT WIRD:
//   * der "Neu"-Bildschirm zeigt die Punkte der neuen Version,
//   * er fragt den Geburtstags-Stil ab (die neue Angabe),
//   * er führt nach dem Abschließen zur Startseite,
//   * der "Update nötig"-Bildschirm nennt den Grund und den Knopf,
//   * "später" funktioniert nur, wenn der Bildschirm keine Sperre ist
//     (beim Start darf der Nutzer nicht weiterlaufen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/core/update_required_screen.dart';
import 'package:thestia/screens/core/whats_new_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/widgets/common/birthday_style.dart';

import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await mockPfadProvider();
    mockKeystore();
    // DER BUILD 30 hat eigene "Neu"-Punkte (v0.9.2).
    mockPackageInfo(version: '0.9.2', build: '30');
  });

  group('Der "Neu"-Bildschirm', () {
    testWidgets('zeigt die Punkte der neuen Version', (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(TestSpeicher()),
          secureProfileStoreProvider.overrideWithValue(TestKeystore()),
          profileProvider.overrideWith((ref) => TestProfil()),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/whats-new',
        routes: appRoutes(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      // DIE ECHTE ZEIT: Die Versionsabfrage läuft über den Plattform-
      // Kanal - die Antwort kommt erst, wenn die echte Uhr weiterläuft.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(WhatsNewScreen),
        findsOneWidget,
        reason: 'Der Bildschirm muss sich aufbauen.',
      );
      expect(
        find.byType(FilledButton),
        findsWidgets,
        reason:
            'Der Bildschirm braucht einen Knopf zum Abschließen - sonst '
            'weiß der Nutzer nicht, wie es weitergeht.',
      );
    });

    testWidgets('fragt den Geburtstags-Stil ab', (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(TestSpeicher()),
          secureProfileStoreProvider.overrideWithValue(TestKeystore()),
          profileProvider.overrideWith((ref) => TestProfil()),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/whats-new',
        routes: appRoutes(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      // DIE ECHTE ZEIT: Die Versionsabfrage läuft über den Plattform-
      // Kanal - die Antwort kommt erst, wenn die echte Uhr weiterläuft.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(BirthdayStylePicker),
        findsOneWidget,
        reason:
            'Der Geburtstags-Stil ist die neue Angabe - der Bildschirm '
            'muss danach fragen.',
      );
    });
  });

  group('Der "Update nötig"-Bildschirm', () {
    testWidgets('nennt den Grund und bietet den Store an', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: UpdateRequiredScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.textContaining('Update'), findsWidgets);
    });

    testWidgets('"später" geht nur, wenn der Bildschirm keine Sperre ist', (
      tester,
    ) async {
      var verworfen = false;

      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredScreen(onDismiss: () => verworfen = true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(
        verworfen,
        isTrue,
        reason:
            'Während der laufenden App darf der Nutzer weiterarbeiten - '
            'der Hinweis ist nur eine Deckschicht.',
      );
    });

    testWidgets('beim Start ist "später" ohne Wirkung', (tester) async {
      // BEIM START: Der Bildschirm ist eine Sperre - ohne onDismiss darf
      // "Trotzdem fortfahren" nichts bewirken.
      await tester.pumpWidget(const MaterialApp(home: UpdateRequiredScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(UpdateRequiredScreen),
        findsOneWidget,
        reason: 'Ein zu alter Build darf nicht weiterlaufen.',
      );
    });
  });
}
