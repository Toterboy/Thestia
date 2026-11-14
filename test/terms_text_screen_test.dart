// Die Nutzungsbedingungen IN der App (BEFUND 14.11.2026, Betreiber:
// "Die Nutzungsbedingungen funktionieren in der App nicht").
//
// Vorher waren sie nur ein Link auf die Webseite: das brauchte einen
// installierten Browser und eine erreichbare Seite. Jetzt steht der
// Text im Binary und wird in der App angezeigt - wie die
// Datenschutzerklaerung, die Play ohnehin als Text in der App
// verlangt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/generated/terms_de.dart';
import 'package:thestia/generated/terms_en.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';
import 'package:thestia/screens/privacy/terms_text_screen.dart';

void main() {
  testWidgets('der Bildschirm zeigt den Volltext der Bedingungen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TermsTextScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    // Die Ueberschrift steht da (im Balken und als erste Zeile des
    // Textes - beides ist gewollt).
    expect(find.text('Nutzungsbedingungen'), findsWidgets);
    // Und der Text ist mehr als eine Ueberschrift: die Abschnitte
    // stehen drin (Mindestalter und Meldeweg sind die wichtigen).
    expect(
      find.textContaining('Mindestalter'),
      findsOneWidget,
      reason: 'Der Abschnitt zum Mindestalter muss in der App stehen.',
    );
    expect(
      find.textContaining('moderation@thestia.de'),
      findsNothing,
      reason:
          'Der Abschnitt 5 ist weiter unten - er wird beim Scrollen '
          'sichtbar, nicht sofort. Das prueft der zweite Test.',
    );
  });

  testWidgets('der ganze Text steht drin (nicht nur die ersten Zeilen)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TermsTextScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Der Widerspruchsweg (Abschnitt 5) steht weit unten - er wird
    // sichtbar, wenn man scrollt.
    final meldeweg = find.textContaining('moderation@thestia.de');
    for (var i = 0; i < 12 && meldeweg.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      meldeweg,
      findsOneWidget,
      reason:
          'Alle Abschnitte muessen in der App stehen - auch die am Ende. '
          'Sonst ist die Fassung in der App unvollstaendig.',
    );
  });

  testWidgets('die Kachel in den Datenschutz-Einstellungen oeffnet den Text', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.privacy,
      routes: [
        GoRoute(
          path: AppRoutes.privacy,
          builder: (context, state) => const PrivacyScreen(),
        ),
        GoRoute(
          path: AppRoutes.privacyTerms,
          builder: (context, state) => const TermsTextScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Die Kachel steht nicht ganz oben - der Test muss scrollen.
    final kachel = find.text('Nutzungsbedingungen');
    for (var i = 0; i < 12 && kachel.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(kachel, findsOneWidget);

    await tester.tap(kachel);
    await tester.pumpAndSettle();

    // Der Bildschirm mit dem Text steht jetzt da (nicht der Browser).
    expect(find.byType(TermsTextScreen), findsOneWidget);
    expect(find.text('Nutzungsbedingungen'), findsWidgets);
  });

  test('beide Sprachfassungen sind vollstaendig', () {
    expect(kTermsDe, isNotEmpty);
    expect(kTermsEn, isNotEmpty);
    // Die Abschnitte muessen in beiden Fassungen gleich viele sein -
    // sonst fehlt in einer Sprache ein Abschnitt.
    expect(kTermsDe.length, kTermsEn.length);
    // Das Mindestalter steht in beiden.
    expect(kTermsDe.any((b) => b.text.contains('Mindestalter')), isTrue);
    expect(kTermsEn.any((b) => b.text.contains('Minimum age')), isTrue);
  });
}
