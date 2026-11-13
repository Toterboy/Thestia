// Tests fuer die beiden App-Buttons.
//
// ANLASS: Die Buttons tragen die halbe App. Zwei Dinge sind leicht
// falsch und fallen nie auf, wenn niemand sie antippt:
//
//   1. Der Ladezustand: Der Knopf muss den Text AUSBLENDEN und
//      gesperrt sein. Sonst kann der Nutzer zweimal tippen und die
//      Aktion twice laufen lassen.
//   2. Ein langer Text: "Persoenlichkeitstest starten" muss den Knopf
//      nicht aus dem Bild schieben - er wird gekuerzt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/buttons.dart';

Widget _huelle(Widget kind, {double scale = 1.0}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: kind,
        ),
      ),
    ),
  );
}

void main() {
  group('PrimaryButton', () {
    testWidgets('zeigt das Label', (tester) async {
      await tester.pumpWidget(_huelle(const PrimaryButton(label: 'Weiter')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Weiter'), findsOneWidget);
    });

    testWidgets('der Tipp wird gemeldet', (tester) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(PrimaryButton(label: 'Weiter', onPressed: () => tipps++)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(tipps, 1);
    });

    testWidgets('im Ladezustand steht der Ring statt des Textes', (
      tester,
    ) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(
          PrimaryButton(
            label: 'Wird gesendet',
            loading: true,
            onPressed: () => tipps++,
          ),
        ),
      );
      // KEIN pumpAndSettle: der Ladering dreht sich endlos - er kommt
      // nie zur Ruhe. Ein Frame reicht, um den Zustand zu sehen.
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Der Text ist weg: sonst sieht der Knopf nach zwei Aktionen aus.
      expect(find.text('Wird gesendet'), findsNothing);
    });

    testWidgets('im Ladezustand ist der Knopf gesperrt', (tester) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(
          PrimaryButton(
            label: 'Wird gesendet',
            loading: true,
            onPressed: () => tipps++,
          ),
        ),
      );
      await tester.pump();

      final knopf = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(knopf.enabled, isFalse);

      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();

      expect(tipps, 0, reason: 'Ein laedender Knopf darf nicht ausloesen.');
    });

    testWidgets('ohne Handler ist der Knopf gesperrt', (tester) async {
      await tester.pumpWidget(_huelle(const PrimaryButton(label: 'Weiter')));
      await tester.pumpAndSettle();

      final knopf = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(knopf.enabled, isFalse);
    });

    testWidgets('ein mitgegebenes Icon steht vor dem Text', (tester) async {
      await tester.pumpWidget(
        _huelle(
          const PrimaryButton(
            label: 'Starten',
            icon: Icon(Icons.rocket_launch),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.rocket_launch), findsOneWidget);
      expect(find.text('Starten'), findsOneWidget);
    });

    testWidgets('ein langes Label laeuft nicht aus der Flaeche', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const PrimaryButton(label: 'Persönlichkeitstest starten'),
          scale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Der Text ist noch da - nur gekuerzt.
      expect(find.text('Persönlichkeitstest starten'), findsOneWidget);
    });
  });

  group('SecondaryButton', () {
    testWidgets('zeigt das Label und meldet den Tipp', (tester) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(SecondaryButton(label: 'Abbrechen', onPressed: () => tipps++)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Abbrechen'), findsOneWidget);

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(tipps, 1);
    });

    testWidgets('ohne Handler ist der Knopf gesperrt', (tester) async {
      await tester.pumpWidget(
        _huelle(const SecondaryButton(label: 'Abbrechen')),
      );
      await tester.pumpAndSettle();

      final knopf = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(knopf.enabled, isFalse);
    });

    testWidgets('ueberlebt grosse Schrift ohne Overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(const SecondaryButton(label: 'Erneut versuchen'), scale: 3.2),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
