import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';

/// Die Nutzungsbedingungen in den Datenschutz-Einstellungen.
///
/// Die Seiten gibt es seit dem 05.11.2026 (passkey-assets/
/// nutzungsbedingungen.html). In der App fehlte der Link darauf - und
/// Google Play verlangt fuer jede App eine erreichbare Adresse der
/// Nutzungsbedingungen.
///
/// HINWEIS: Die Kachel steht nicht ganz oben. Ein ListView baut nur die
/// sichtbaren Kinder - der Test muss also scrollen. Ohne das wuerde der
/// Test "gruen" sein, obwohl die Kachel fehlt.
void main() {
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PrivacyScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> scrolleZurKachel(WidgetTester tester) async {
    final kachel = find.text(L10n.tWithoutContext('privacy.termsTitle'));
    if (kachel.evaluate().isNotEmpty) return;
    for (var i = 0; i < 12; i++) {
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -260),
      );
      await tester.pump(const Duration(milliseconds: 120));
      if (kachel.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('die Datenschutz-Einstellungen nennen die Nutzungsbedingungen',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    expect(
      find.text(L10n.tWithoutContext('privacy.termsTitle')),
      findsOneWidget,
    );
  });

  testWidgets('die Nutzungsbedingungen sind eine Kachel (kein blosser Text)',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    final eintrag = find.ancestor(
      of: find.text(L10n.tWithoutContext('privacy.termsTitle')),
      matching: find.byType(ListTile),
    );
    expect(eintrag, findsOneWidget);
  });

  testWidgets('das Impressum steht daneben (beides gehoert zusammen)',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    expect(
      find.text(L10n.tWithoutContext('privacy.imprintTitle')),
      findsOneWidget,
    );
  });
}
