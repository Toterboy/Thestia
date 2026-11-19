// Tests fuer den ruhigen Ladeindikator.
//
// ANLASS (NUTZERWUNSCH 31.10.2026): "der kurze Ladekreis ist stoerend
// fuer die Animation dort". Ein Ring, der nach 200 ms wieder verschwindet,
// ist ein Blitzer - er zieht den Blick auf sich und macht aus einem weichen
// Ueberblenden einen harten Schnitt. Der [CalmLoading] ist der Ersatz:
// drei Balken, die langsam ein- und ausblenden.
//
// Geprueft wird deshalb das WESENTLICHE des Widgets:
//   * Es ist KEIN Ladekreis (sonst waere der Blitzer wieder da),
//   * die Balken atmen wirklich (die Deckkraft aendert sich),
//   * sie atmen NACHECINANDER (versetzte Phasen), und
//   * sie werden nicht breiter als erlaubt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/calm_loading.dart';

Widget _huelle(Widget kind) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: Center(child: kind)),
  );
}

/// Die Deckkraft des n-ten Balkens.
///
/// WICHTIG: der Finder muss auf den [CalmLoading]-Teilbaum
/// eingeschraenkt werden - das MaterialApp benutzt fuer den
/// Seitenwechsel selbst eine FadeTransition, die sonst gefunden wird.
double _opazitaet(WidgetTester tester, int index) {
  final balken = tester.widget<FadeTransition>(
    find
        .descendant(
          of: find.byType(CalmLoading),
          matching: find.byType(FadeTransition),
        )
        .at(index),
  );
  return balken.opacity.value;
}

void main() {
  group('CalmLoading', () {
    testWidgets('zeichnet genau so viele Balken wie gewuenscht', (
      tester,
    ) async {
      await tester.pumpWidget(_huelle(const CalmLoading(lines: 3)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(CalmLoading),
          matching: find.byType(Container),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('die Anzahl der Balken ist frei waehlbar', (tester) async {
      await tester.pumpWidget(_huelle(const CalmLoading(lines: 5)));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CalmLoading),
          matching: find.byType(Container),
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('KEIN Ladekreis - genau das ist der Zweck', (tester) async {
      await tester.pumpWidget(_huelle(const CalmLoading()));
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'Der kreisende Ring ist genau das, was der Nutzer nicht mehr '
            'wollte. Er darf hier nicht auftauchen.',
      );
    });

    testWidgets('die Balken blenden ein und aus', (tester) async {
      await tester.pumpWidget(_huelle(const CalmLoading()));
      await tester.pump();

      final start = _opazitaet(tester, 0);
      await tester.pump(const Duration(milliseconds: 400));
      final spaeter = _opazitaet(tester, 0);

      expect(spaeter, isNot(start), reason: 'Der Balken muss atmen.');
      // Der Balken ist nie ganz weg und nie ueberstrahlt.
      expect(start, inInclusiveRange(0.3, 1.0));
      expect(spaeter, inInclusiveRange(0.3, 1.0));
    });

    testWidgets('die Balken atmen nacheinander, nicht im Gleichtakt', (
      tester,
    ) async {
      // Der Grund fuer die versetzten Phasen: gleich laufende Balken
      // lesen sich als Ladekreislauf. Versetzt lesen sie sich als
      // "hier passiert gerade etwas".
      await tester.pumpWidget(_huelle(const CalmLoading(lines: 3)));
      await tester.pump(const Duration(milliseconds: 400));

      final werte = [0, 1, 2].map((i) => _opazitaet(tester, i)).toList();

      expect(
        werte.toSet().length,
        greaterThan(1),
        reason:
            'Die Balken duerfen nicht alle gleichzeitig gleich hell sein - '
            'Deckkraftwerte: $werte',
      );
    });

    testWidgets('die Balken werden nicht breiter als maxWidth', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(const CalmLoading(maxWidth: 120)));
      await tester.pump();

      final balken = find
          .descendant(
            of: find.byType(CalmLoading),
            matching: find.byType(Container),
          )
          .first;
      expect(
        tester.getSize(balken).width,
        lessThanOrEqualTo(120),
        reason: 'Auf einem Tablet sollen die Balken nicht zur Page werden.',
      );
    });

    testWidgets('auf einem schmalen Bildschirm laeuft nichts ueber', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(const CalmLoading()));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
