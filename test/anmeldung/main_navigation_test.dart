// Die Reiter-Leiste (MainNavigation) - die Schutzfragen waren ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/core/main_navigation.dart 111 offene Zeilen bei 198 Zeilen
// gesamt. Die Reiter-Leiste entscheidet, welcher Bereich der App
// gerade offen ist - und sie fragt nach, wenn der Nutzer ungespeicherte
// Aenderungen verliert (Nutzerwunsch vom 27.10.2026).
//
// WAS HIER GEPRUEFT WIRD:
//   * alle vier Reiter stehen da,
//   * mit ungespeicherten Aenderungen fragt die Leiste nach
//     (Speichern / Verwerfen / Abbrechen),
//   * "Abbrechen" laesst den Nutzer auf seinem Tab,
//   * "Verwerfen" verwirft die Aenderungen und wechselt,
//   * "Speichern" merkt sich die Ziel-Route (der Editor springt danach
//     selbst),
//   * im Chat wird die Leiste ausgeblendet (der Gespraech hat den
//     vollen Bildschirm).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/core/main_navigation.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart'
    show profileEditDirtyProvider, profileEditNavigateAfterSaveProvider;
import 'package:thestia/services/local_storage.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut die Leiste.
  ///
  /// [startRoute] ist die Seite, die beim Start offen ist.
  Future<ProviderContainer> zeigeNavigation(
    WidgetTester tester, {
    String startRoute = AppRoutes.home,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: startRoute,
      routes: [
        // DIE LEISTE: Sie umschliesst jede Seite (in der App macht das
        // die ShellRoute - im Test steht sie direkt in der Seite, sonst
        // baut go_router dieselbe Seite zweimal).
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('SEITE-HOME'))),
          ),
        ),
        GoRoute(
          path: AppRoutes.swipeModeSelection,
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('SEITE-ENTDECKEN'))),
          ),
        ),
        GoRoute(
          path: AppRoutes.interessen,
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('SEITE-INTERESSEN'))),
          ),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('SEITE-PROFIL'))),
          ),
        ),
        GoRoute(
          path: AppRoutes.profileEdit,
          builder: (context, state) => const MainNavigation(
            child: Scaffold(
              body: Center(child: Text('SEITE-PROFIL-BEARBEITEN')),
            ),
          ),
        ),
        GoRoute(
          path: '/chat/7',
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('SEITE-CHAT'))),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  group('Die Reiter-Leiste', () {
    testWidgets('alle vier Reiter stehen da', (tester) async {
      await zeigeNavigation(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('nav.home')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('nav.discover')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('nav.interests')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('nav.profile')), findsOneWidget);
    });

    testWidgets('ohne Aenderungen wechselt der Reiter sofort', (tester) async {
      await zeigeNavigation(tester);

      await tester.tap(find.text(L10n.tWithoutContext('nav.discover')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-ENTDECKEN'), findsOneWidget);
    });

    testWidgets('mit ungespeicherten Aenderungen wird nachgefragt', (
      tester,
    ) async {
      final container = await zeigeNavigation(tester);
      container.read(profileEditDirtyProvider.notifier).state = true;
      await tester.pump();

      // Den zweiten Reiter tippen.
      await tester.tap(find.text(L10n.tWithoutContext('nav.discover')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('nav.unsavedTitle')),
        findsOneWidget,
        reason:
            'Ohne Nachfrage wuerde der Nutzer ungespeicherte Aenderungen '
            'verlieren - das war der Wunsch des Betreibers.',
      );
      // Und es ist noch nicht gewechselt.
      expect(find.text('SEITE-HOME'), findsOneWidget);
    });

    testWidgets('"Abbrechen" laesst den Nutzer auf seinem Reiter', (
      tester,
    ) async {
      final container = await zeigeNavigation(tester);
      container.read(profileEditDirtyProvider.notifier).state = true;
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('nav.discover')));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-HOME'), findsOneWidget);
      expect(find.text('SEITE-ENTDECKEN'), findsNothing);
    });

    testWidgets('"Verwerfen" wechselt und loescht die Aenderungen', (
      tester,
    ) async {
      final container = await zeigeNavigation(tester);
      container.read(profileEditDirtyProvider.notifier).state = true;
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('nav.discover')));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.discard')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-ENTDECKEN'), findsOneWidget);
      expect(
        container.read(profileEditDirtyProvider),
        isFalse,
        reason:
            'Nach dem Verwerfen sind die Aenderungen weg - sonst fragt die '
            'Leiste noch einmal.',
      );
    });

    testWidgets('"Speichern" merkt sich die Ziel-Route', (tester) async {
      final container = await zeigeNavigation(tester);
      container.read(profileEditDirtyProvider.notifier).state = true;
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('nav.discover')));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, L10n.tWithoutContext('common.save')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Der Editor springt selbst - die Leiste merkt sich nur das Ziel.
      expect(
        container.read(profileEditNavigateAfterSaveProvider),
        AppRoutes.swipeModeSelection,
        reason:
            'Nach dem Speichern muss der Editor zur Ziel-Route springen - '
            'sonst bleibt der Nutzer im Formular haengen.',
      );
    });

    testWidgets('im Chat wird die Leiste ausgeblendet', (tester) async {
      await zeigeNavigation(tester, startRoute: '/chat/7');

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-CHAT'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('nav.home')),
        findsNothing,
        reason:
            'Im Chat sollen die Reiter unten nicht mehr sichtbar sein - '
            'das Gespraech hat den vollen Bildschirm.',
      );
    });
  });
}
