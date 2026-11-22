// Der Hintergrund der Geburtstagsflaeche (NUTZERWUNSCH 22.11.2026:
// "Die Geburtstagsvorschau ist noch immer komplett falsch, da der
// Hintergrund nicht der des Geburtstagsthemes ist").
//
// DER BEFUND: Die Profilflaeche malte eine eigene, schwaeche Tönung
// (22 % Akzent auf der weissen Flaeche) - der Verlauf des Stils lag
// PRIVAT in der Vorschaukarte. Bei midnight und mono war die Flaeche
// damit praktisch weiss: der Hintergrund des Geburtstagsthemes war
// nirgends zu sehen.
//
// DER TEST: Die Flaeche muss DENSELBEN Verlauf malen, den der Nutzer
// in der Auswahl sieht - und auf den dunklen Stilen muss der Text
// hell sein.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/common/birthday_style.dart';

/// Der erste Farbwert des Theme-Hintergrunds je Stil.
const _ersteFarbe = <String, Color>{
  'midnight': Color(0xFF1A2340),
  'mono': Color(0xFF2B2B2B),
  'sage': Color(0xFF9CAF88),
  'rose': Color(0xFFE8B4B8),
};

void main() {
  /// Baut ein Widget mit Theme-Kontext.
  Widget mitTheme(Widget child) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: child),
  );

  group('Der Hintergrund des Geburtstagsthemas', () {
    testWidgets('die Flaeche malt den Theme-Verlauf (nicht die alte Toenung)', (
      tester,
    ) async {
      await tester.pumpWidget(
        mitTheme(
          const BirthdayStyleSurface(
            style: 'midnight',
            active: true,
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final deko = container.decoration as BoxDecoration;
      final verlauf = deko.gradient as LinearGradient;

      expect(
        verlauf.colors.first,
        _ersteFarbe['midnight'],
        reason:
            'Die Flaeche muss den Hintergrund des THEMAS malen - nicht '
            'eine blasse Toenung.',
      );
    });

    testWidgets('ohne Geburtstag bleibt die Flaeche unveraendert', (
      tester,
    ) async {
      await tester.pumpWidget(
        mitTheme(
          const BirthdayStyleSurface(
            style: 'midnight',
            active: false,
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('auf dunklen Stilen ist der Text hell', (tester) async {
      await tester.pumpWidget(
        mitTheme(
          const BirthdayStyleSurface(
            style: 'mono',
            active: true,
            child: Text('Hallo'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der Text erbt die Farbe der Flaeche (weiss auf dunkel).
      final erbung = DefaultTextStyle.of(
        tester.element(find.text('Hallo')),
      ).style.color;
      expect(erbung, Colors.white);
    });

    testWidgets('der Verlauf ist fuer jeden Stil der des Stils', (
      tester,
    ) async {
      await tester.pumpWidget(
        mitTheme(
          const BirthdayStyleSurface(
            style: 'sage',
            active: true,
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final deko = container.decoration as BoxDecoration;
      final verlauf = deko.gradient as LinearGradient;
      expect(verlauf.colors.first, _ersteFarbe['sage']);
    });
  });
}
