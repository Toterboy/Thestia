import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';

/// Der Impressum-Einstieg in den Datenschutz-Einstellungen.
///
/// WARUM (Recherche 05.11.2026): Die App ist selbst ein digitaler
/// Dienst im Sinne des Par. 5 DDG. Die Informationspflichten gelten
/// also fuer sie, nicht nur fuer die Website. Bisher gab es in der App
/// nur die Datenschutzerklaerung (die verlangt Play ohnehin) - das
/// Impressum fehlte ganz.
///
/// HINWEIS: Die Kachel steht nicht ganz oben. Ein ListView baut nur
/// die sichtbaren Kinder - der Test muss also scrollen. Ohne das
/// wuerde der Test "gruen" sein, obwohl die Kachel fehlt.
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
    final kachel = find.text(L10n.tWithoutContext('privacy.imprintTitle'));
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

  testWidgets('die Datenschutz-Einstellungen zeigen einen Impressum-Eintrag',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    expect(
      find.text(L10n.tWithoutContext('privacy.imprintTitle')),
      findsOneWidget,
    );
  });

  testWidgets('der Impressum-Eintrag nennt die Rechtsgrundlage',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    expect(find.textContaining('5 DDG'), findsOneWidget);
  });

  testWidgets('der Impressum-Eintrag ist eine Kachel (kein blosser Text)',
      (tester) async {
    await zeigeScreen(tester);
    await scrolleZurKachel(tester);

    final eintrag = find.ancestor(
      of: find.text(L10n.tWithoutContext('privacy.imprintTitle')),
      matching: find.byType(ListTile),
    );
    expect(eintrag, findsOneWidget);
  });
}
