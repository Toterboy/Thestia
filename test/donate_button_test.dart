// Tests fuer den Spenden-Button.
//
// ANLASS: Der Button existierte bis v0.4.0 nicht mehr - zu Recht, weil
// die Zahlung damals eine Attrappe war. Jetzt ist er wieder da, aber
// ohne Attrappe: keine erfundene Buchung, keine "Danke"-Bestaetigung
// ohne Zahlung, kein Spender-Badge. Der Button oeffnet genau einen
// Link - oder erklaert ehrlich, dass gar keine Adresse hinterlegt ist.
//
// GENAU DIESER letzte Fall wird hier geprueft: Solange keine Adresse
// eingetragen ist, darf der Button KEINEN Zahlungsfluss vortaeuschen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/donate_button.dart';

Widget _huelle(Widget kind) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: Center(child: kind)),
  );
}

/// Die gezeichneten Vektoren im Button.
///
/// ACHTUNG: Das Material des Buttons bringt selbst ein CustomPaint
/// mit (fuer die Tinte des Tap-Feedbacks) - deshalb wird nur nach
/// einem CustomPaint MIT Painter gesucht. Das ist die Schenk-Glyphe.
Finder _gezeichneteVektoren() {
  return find.descendant(
    of: find.byType(DonateButton),
    matching: find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter != null,
    ),
  );
}

void main() {
  setUp(() {
    // Der Plattform-Kanal wird in Widget-Tests nicht beantwortet - ein
    // Haptik-Rückimpuls (HapticFeedback) wuerde den Test sonst ewig
    // warten lassen. Der Mock beantwortet ihn sofort.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          return null;
        });
  });

  group('DonateButton', () {
    testWidgets('zeigt den Text "Unterstuetzen"', (tester) async {
      await tester.pumpWidget(_huelle(const DonateButton()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unterstützen'), findsOneWidget);
    });

    testWidgets('zeichnet die eigene Schenk-Glyphe', (tester) async {
      // Bewusst KEIN Icons.card_giftcard: das steht in der App bereits
      // fuer "Gefaellt mir". Die eigene Glyphe hebt sich davon ab.
      await tester.pumpWidget(_huelle(const DonateButton()));
      await tester.pumpAndSettle();

      expect(_gezeichneteVektoren(), findsOneWidget);
      expect(find.byIcon(Icons.card_giftcard), findsNothing);
      // Und es ist wirklich kein Standard-Icon: die App benutzt
      // "Gefaellt mir" bereits als Herz-Icon.
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('nutzt ein mitgegebenes Icon statt der Glyphe', (tester) async {
      await tester.pumpWidget(
        _huelle(const DonateButton(icon: Icons.volunteer_activism)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.volunteer_activism), findsOneWidget);
      expect(_gezeichneteVektoren(), findsNothing);
    });

    testWidgets('ohne hinterlegte Adresse erklaert ein Dialog das', (
      tester,
    ) async {
      // Der wichtigste Fall: Es darf NICHTS passieren, was wie eine
      // Zahlung aussieht. Der Dialog sagt klar, dass nichts abgebucht
      // wurde.
      expect(
        donateConfigured,
        isFalse,
        reason:
            'Dieser Test laeuft ohne --dart-define. Ist im Build eine '
            'Adresse hinterlegt, muss der Test angepasst werden.',
      );

      await tester.pumpWidget(_huelle(const DonateButton()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unterstützen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('App unterstützen'), findsOneWidget);
      expect(
        find.textContaining('noch keine Spendenadresse hinterlegt'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Es wurde nichts abgebucht'),
        findsOneWidget,
        reason:
            'Der Dialog muss ausdruecklich sagen, dass nichts abgebucht '
            'wurde - sonst sieht es wie eine Zahlung aus.',
      );
    });

    testWidgets('der Dialog laesst sich wieder schliessen', (tester) async {
      await tester.pumpWidget(_huelle(const DonateButton()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unterstützen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('openDonateLink', () {
    testWidgets('ohne Adresse passiert nichts weiter', (tester) async {
      // Der Helfer fuer Textzeilen: ohne Adresse gibt es nichts zu
      // oeffnen. Er darf keinen Absturz produzieren - und keinen Link.
      await tester.pumpWidget(_huelle(const DonateButton()));
      await tester.pumpAndSettle();

      Object? fehler;
      try {
        await openDonateLink(tester.element(find.byType(DonateButton)));
      } catch (e) {
        fehler = e;
      }

      expect(fehler, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
