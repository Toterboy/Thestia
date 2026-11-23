// Die Reiter-Leiste: das Wischen, die Schiene (Desktop) und die
// gesicherte Route.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/core/main_navigation.dart 72 offene Zeilen. Der Test
// "main_navigation_test.dart" deckt die Nachfrage bei ungespeicherten
// Aenderungen ab - das Wischen zwischen den Reitern, die Schiene auf
// breiten Bildschirmen und die Sicherung der letzten Route waren
// ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein Wischen nach links kommt zum naechsten Reiter,
//   * am linken Rand geht es nicht zurueck (es gibt keinen Reiter da),
//   * ein zu kleiner Wischen federt zurueck (nichts passiert),
//   * in einem Unterscreen wischen nichts (der Reiter bleibt),
//   * auf breiten Bildschirmen gibt es die Schiene statt der Leiste,
//   * die Schiene schaltet genauso um wie die Leiste,
//   * die zuletzt gezeigte Seite wird gesichert (Wiederherstellung nach
//     einem Prozesstod).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/routing/route_restore.dart';
import 'package:thestia/screens/core/main_navigation.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/chat/dock_tab_bar.dart';

import '../support/router_harness.dart';

void main() {
  /// Der Speicher, in dem die gesicherte Route landet.
  late TestSpeicher speicher;

  /// Baut die Reiter-Leiste mit einem Router.
  Future<void> zeigeNavigation(
    WidgetTester tester, {
    String startRoute = AppRoutes.home,
    Size size = const Size(390, 844),
  }) async {
    // DIE GROESSE: Der Test-Fenster hat sonst eine Pixelratio von 3 -
    // dann waere ein 1200-Pixel-Bildschirm nur 400 Pixel breit und die
    // Schiene wuerde gar nicht erscheinen. Mit der Ratio 1 ist die
    // angegebene Groesse die logische.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    speicher = TestSpeicher();
    final container = ProviderContainer(
      overrides: <Override>[localStorageProvider.overrideWithValue(speicher)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: startRoute,
      routes: [
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
  }

  group('Das Wischen', () {
    testWidgets('nach links wischen kommt zum naechsten Reiter', (
      tester,
    ) async {
      await zeigeNavigation(tester);

      await tester.drag(find.text('SEITE-HOME'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-ENTDECKEN'), findsOneWidget);
    });

    testWidgets('am linken Rand geht es nicht zurueck', (tester) async {
      await zeigeNavigation(tester);

      await tester.drag(find.text('SEITE-HOME'), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('SEITE-HOME'),
        findsOneWidget,
        reason:
            'Am ersten Reiter gibt es keinen vorherigen - die Seite darf '
            'nicht ins Leere springen.',
      );
    });

    testWidgets('ein zu kleiner Wischen wechselt nichts', (tester) async {
      await zeigeNavigation(tester);

      // NUR 30 PIXEL: Das ist unter der Schwelle (64 Pixel) - die Seite
      // federt zurueck.
      await tester.drag(find.text('SEITE-HOME'), const Offset(-30, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-HOME'), findsOneWidget);
      expect(find.text('SEITE-ENTDECKEN'), findsNothing);
    });

    testWidgets('in einem Unterscreen wischen nichts', (tester) async {
      await zeigeNavigation(tester, startRoute: AppRoutes.profileEdit);

      await tester.drag(
        find.text('SEITE-PROFIL-BEARBEITEN'),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('SEITE-PROFIL-BEARBEITEN'),
        findsOneWidget,
        reason:
            'In einem Unterscreen soll das Wischen nichts machen - sonst '
            'waere man im falschen Bereich, ohne es zu merken.',
      );
    });
  });

  group('Die Schiene (Desktop)', () {
    testWidgets('ab 1000 Pixel Breite gibt es die Schiene', (tester) async {
      await zeigeNavigation(tester, size: const Size(1200, 800));

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        find.byType(DockTabBar),
        findsNothing,
        reason:
            'Auf dem Desktop gibt es die Schiene statt der unteren Leiste - '
            'sonst waeren die Reiter unten nicht erreichbar.',
      );
    });

    testWidgets('die Schiene schaltet genauso um', (tester) async {
      await zeigeNavigation(tester, size: const Size(1200, 800));

      await tester.tap(find.text(L10n.tWithoutContext('nav.interests')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-INTERESSEN'), findsOneWidget);
    });
  });

  group('Die gesicherte Route', () {
    testWidgets('die zuletzt gezeigte Seite wird gesichert', (tester) async {
      await zeigeNavigation(tester);

      await tester.tap(find.text(L10n.tWithoutContext('nav.interests')));
      await tester.pumpAndSettle();

      expect(
        await speicher.getString(lastRoutePrefsKey),
        AppRoutes.interessen,
        reason:
            'Nach einem Prozesstod soll der Nutzer auf der Seite landen, '
            'auf der er war - nicht wieder auf der Startseite.',
      );
    });

    testWidgets('der passende Reiter ist hervorgehoben', (tester) async {
      await zeigeNavigation(tester, startRoute: AppRoutes.profileEdit);

      final dock = tester.widget<DockTabBar>(find.byType(DockTabBar));
      expect(
        dock.index,
        3,
        reason:
            'Im Profil-Editor ist der Profil-Reiter der passende - der '
            'Nutzer soll sehen, wo er ist.',
      );
    });
  });
}
