// Die Optik der eigenen Tastatur (27.11.2026).
//
// ANLASS: Der Betreiber meldete: "Die eigene App Tastatur sieht auf dem
// Smartphone nicht ansatzweise so aus wie die normale von Android."
//
// WAS HIER GEPRÜFT WIRD:
//   * die Buchstaben sind groß und normal gewichtet (wie beim System),
//   * die Buchstabentasten und die Funktionstasten haben verschiedene
//     Farben (wie beim System),
//   * die Eingabetaste ist die Akzentfarbe der App (wie beim System),
//   * die Tasten stehen reliefartig (ein feiner Schatten),
//   * die eigene Farbe (die Wahl des Nutzers) bleibt erhalten - der
//     Kontrast wird daraus berechnet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/widgets/chat/secure_keyboard.dart';

void main() {
  /// Die Tastatur im Test.
  Widget hause({TastaturStil? stil, int? farbe}) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: SecureKeyboard(
        layout: TastaturBelegung.deutsch,
        stil: stil,
        farbe: farbe,
        onCharacter: (_) {},
        onBackspace: () {},
      ),
    ),
  );

  group('Die Optik wie beim System', () {
    testWidgets('die Buchstaben sind groß und normal gewichtet', (
      tester,
    ) async {
      await tester.pumpWidget(hause());
      await tester.pump();

      final text = tester.widget<Text>(find.text('q'));
      expect(
        text.style?.fontSize,
        22,
        reason:
            'Die Buchstaben der Systemtastatur sind groß - mit 18 Pixeln '
            'sah die Tastatur aus wie eine Tabelle.',
      );
      expect(
        text.style?.fontWeight,
        FontWeight.w400,
        reason: 'Die Buchstaben des Systems sind normal gewichtet.',
      );
    });

    testWidgets('die Funktionstasten haben eine eigene Farbe', (tester) async {
      await tester.pumpWidget(hause());
      await tester.pump();

      final scheme = Theme.of(tester.element(find.text('q'))).colorScheme;

      // Die Buchstabentaste ist weiß (die Fläche des Systems), die
      // Funktionstaste einen Tick dunkler.
      final taste = tester.widget<Material>(
        find.ancestor(of: find.text('q'), matching: find.byType(Material)).last,
      );
      final funktion = tester.widget<Material>(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_upward),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(taste.color, scheme.surface);
      expect(funktion.color, scheme.surfaceContainerHighest);
      expect(
        funktion.color,
        isNot(taste.color),
        reason:
            'Die Funktionstasten müssen sich von den Buchstabentasten '
            'unterscheiden - sonst sieht die Tastatur flach aus.',
      );
    });

    testWidgets('die Eingabetaste ist die Akzentfarbe', (tester) async {
      await tester.pumpWidget(hause());
      await tester.pump();

      final scheme = Theme.of(tester.element(find.text('q'))).colorScheme;

      final taste = tester.widget<Material>(
        find
            .ancestor(
              of: find.byIcon(Icons.keyboard_return),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        taste.color,
        scheme.primary,
        reason:
            'Die Eingabetaste ist beim System die Akzentfarbe - daran '
            'erkennt man sie auf einen Blick.',
      );

      // Und das Symbol darauf ist lesbar (hell auf der Akzentfarbe).
      final icon = tester.widget<Icon>(find.byIcon(Icons.keyboard_return));
      expect(icon.color, scheme.onPrimary);
    });

    testWidgets('die Tasten stehen reliefartig', (tester) async {
      await tester.pumpWidget(hause());
      await tester.pump();

      final taste = tester.widget<Material>(
        find
            .ancestor(of: find.text('q'), matching: find.byType(Material))
            .first,
      );
      expect(
        taste.elevation,
        greaterThan(0),
        reason:
            'Ohne Schatten kleben die Tasten aneinander - das ist der '
            'größte Unterschied zur Systemtastatur.',
      );
    });
  });

  group('Die eigene Farbe des Nutzers', () {
    testWidgets('bleibt erhalten und bleibt lesbar', (tester) async {
      await tester.pumpWidget(
        hause(stil: TastaturStil.eigeneFarbe, farbe: 0xFF1B5E20),
      );
      await tester.pump();

      final taste = tester.widget<Material>(
        find
            .ancestor(of: find.text('q'), matching: find.byType(Material))
            .first,
      );
      expect(taste.color, const Color(0xFF1B5E20));

      // Auf der dunklen Fläche muss der Text hell sein.
      final text = tester.widget<Text>(find.text('q'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('der Name der Taste bleibt vorlesbar', (tester) async {
      await tester.pumpWidget(hause());
      await tester.pump();

      // Der Screenreader muss die Taste benennen können.
      final name = L10n.tWithoutContext('keyboard.space');
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == name,
        ),
        findsOneWidget,
        reason: 'Die Leertaste braucht einen Namen für den Screenreader.',
      );
    });
  });
}
