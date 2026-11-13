// Render-Tests fuer den Rechts-Screen "Community Regeln".
//
// ANLASS: Der Screen ist eine Pflicht-Seite fuer den Play-Store
// (Kinderschutz-Standards: oeffentlich erreichbare Regeln, benannte
// Kontaktperson, beschriebener Meldeweg). Er wird deshalb rarely
// geaendert - und genau deshalb ist er geraten: niemand rendert ihn.
//
// Geprueft wird: kein Absturz, kein Render-Overflow, alle sieben
// Regeln sind erreichbar, der Link zum Kinderschutz steht da, und der
// Zurueck-Knopf macht das Richtige (pop, wenn es etwas zu poppen gibt -
// sonst zur Einstellung).
//
// Der Link wird NICHT angeklickt: er ruft den url_launcher-Plugin auf,
// der auf dem Desktop einen echten Browser oeffnen wuerde. Geprueft
// wird deshalb die Adresse selbst, nicht der Plugin-Aufruf.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/legal/community_guidelines_screen.dart';

/// Die sieben Regeln in der Reihenfolge des Screens.
const List<String> _regeln = [
  '§0 Respektvoller Umgang',
  '§1 Keine Belästigung',
  '§2 Echte Profile',
  '§3 Kein Spam',
  '§4 Datenschutz',
  '§5 Melden & Konsequenzen',
  'Null-Toleranz bei Kindesmissbrauch',
];

/// Router mit den beiden Routen, die der Screen braucht.
///
/// Der Screen holt sich beim Zurueck-Knopf [AppRoutes.settings] - ohne
/// diese Route wuerde der Knopf ins Leere zeigen.
///
/// [scale] ist die Schriftgroesse. Die MediaQuery sitzt dabei UNTER
/// dem MaterialApp: das MaterialApp setzt seine eigene MediaQuery und
/// wuerde eine aeussere ignorieren.
GoRouter _router({
  String start = AppRoutes.communityGuidelines,
  double scale = 1.0,
}) {
  return GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: AppRoutes.communityGuidelines,
        builder: (context, state) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: const CommunityGuidelinesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Einstellungen'),
                TextButton(
                  onPressed: () => context.push(AppRoutes.communityGuidelines),
                  child: const Text('Regeln oeffnen'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// Scrollt, bis [ziel] sichtbar ist (oder das Ende erreicht ist).
Future<void> _scrolleZu(WidgetTester tester, Finder ziel) async {
  final liste = find.byType(Scrollable).first;
  for (var i = 0; i < 40 && ziel.evaluate().isEmpty; i++) {
    await tester.drag(liste, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('Community Regeln', () {
    testWidgets('zeigt den Titel und die erste Regel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community Regeln'), findsOneWidget);
      expect(find.text('§0 Respektvoller Umgang'), findsOneWidget);
    });

    testWidgets('alle sieben Regeln sind erreichbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      for (final regel in _regeln) {
        await _scrolleZu(tester, find.text(regel));
        expect(
          find.text(regel),
          findsOneWidget,
          reason: 'Die Regel "$regel" muss erreichbar sein.',
        );
      }
    });

    testWidgets('der Hinweis auf den Kinderschutz steht ganz unten', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await _scrolleZu(tester, find.text('Kinderschutz und Meldestelle'));

      expect(tester.takeException(), isNull);
      expect(find.text('Kinderschutz und Meldestelle'), findsOneWidget);
      expect(find.text('Kinderschutz-Seite öffnen'), findsOneWidget);
      // Die Meldestelle wird ausdruecklich beschrieben - der
      // Play-Store verlangt einen benannten Meldeweg.
      expect(find.textContaining('Meldeweg'), findsOneWidget);
    });

    testWidgets('die Adresse der Kinderschutz-Seite stimmt', (tester) async {
      // Der Plugin-Aufruf wird nicht ausgefuehrt (er wuerde einen
      // echten Browser oeffnen). Geprueft wird die Adresse selbst -
      // sie muss oeffentlich erreichbar sein.
      expect(kChildSafetyUrl, 'https://auth.thestia.de/kinderschutz');
      expect(Uri.parse(kChildSafetyUrl).host, 'auth.thestia.de');
    });

    testWidgets('die erste Regel ist als Einleitung hervorgehoben', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byType(CommunityGuidelinesScreen)),
      ).colorScheme;
      final einleitung = tester.widget<Card>(find.byType(Card).first);

      expect(
        einleitung.color,
        scheme.primaryContainer,
        reason: 'Die Einleitung soll als Einleitung erkennbar sein.',
      );
    });

    testWidgets('ohne Verlauf fuehrt der Zurueck-Knopf zur Einstellung', (
      tester,
    ) async {
      // Steht der Screen allein (z. B. als Start), gibt es nichts zu
      // poppen - dann muss der Knopf zur Einstellung springen, sonst
      // passiert gar nichts.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.byType(CommunityGuidelinesScreen), findsNothing);
    });

    testWidgets('mit Verlauf geht der Zurueck-Knopf zurueck', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router(start: AppRoutes.settings);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Einstellungen'), findsOneWidget);

      // Wie in der App: aus der Einstellung heraus oeffnen.
      await tester.tap(find.text('Regeln oeffnen'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityGuidelinesScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.byType(CommunityGuidelinesScreen), findsNothing);
    });

    testWidgets('rendert ohne Overflow bei grosser Schrift', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = _router(scale: 3.2);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Der ganze Screen durchscrollen.
      final liste = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(liste, const Offset(0, -600));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
