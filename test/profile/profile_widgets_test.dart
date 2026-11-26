// Die Profil-Bausteine (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/profile_widgets.dart 0 %.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Interessen stehen als Chips da,
//   * gemeinsame Interessen sind hervorgehoben (mit Herz) - daran sieht
//     der Nutzer, was beide mögen,
//   * der Blind-Mode-Platzhalter sagt, warum kein Foto zu sehen ist.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/profile/profile_widgets.dart';

void main() {
  group('Die Profil-Bausteine', () {
    testWidgets('die Interessen stehen als Chips da', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InterestChips(interests: ['Klettern', 'Kochen']),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Klettern'), findsOneWidget);
      expect(find.text('Kochen'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('gemeinsame Interessen sind hervorgehoben', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InterestChips(interests: ['Klettern'], highlighted: true),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Das Herz zeigt dem Nutzer, dass das eine gemeinsame Interesse ist.
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('ohne Hervorhebung gibt es kein Herz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InterestChips(interests: ['Klettern'])),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('der Blind-Mode-Platzhalter sagt, warum', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BlindPhotoPlaceholder())),
      );

      expect(tester.takeException(), isNull);
      // Das Auge mit dem Strich: kein Foto sichtbar.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      // Und der Grund steht dabei.
      expect(find.text('Foto nach Match sichtbar'), findsOneWidget);
    });

    testWidgets('der Blind-Mode-Platzhalter nimmt einen eigenen Text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlindPhotoPlaceholder(label: 'Nach dem Like sichtbar'),
          ),
        ),
      );

      expect(find.text('Nach dem Like sichtbar'), findsOneWidget);
      expect(find.text('Foto nach Match sichtbar'), findsNothing);
    });
  });
}
