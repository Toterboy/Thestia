// Tests fuer die Interview-Blase aus der Erst-Einrichtung.
//
// ANLASS: Die Blase ist das optische Kernstueck des Interviews - die
// Einrichtung soll sich wie ein Gespraech anfuehlen und nicht wie ein
// Formular. Genau daran haengt aber die ganze Wirkung: Wenn die Blase
// zu breit wird, laeuft der Text aus dem Rahmen; wenn die Schrift
// waechst, muss sie mitwaachsen.
//
// Geprueft wird deshalb: der Text steht da, das Avatar steht da, die
// Blase sitzt LINKS (die Frage kommt von Thestia, nicht vom Nutzer),
// und nichts laeuft bei grosser Schrift ueber den Rand.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/interview_bubble.dart';

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

/// Die Dekoration der Blase (der aeusserste Container im Widget -
/// der CircleAvatar bringt einen zweiten mit).
BoxDecoration _deko(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(InterviewBubble),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration as BoxDecoration;
}

void main() {
  group('InterviewBubble', () {
    testWidgets('zeigt den Fragetext', (tester) async {
      await tester.pumpWidget(
        _huelle(const InterviewBubble(text: 'Wie möchtest du bleiben?')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Wie möchtest du bleiben?'), findsOneWidget);
    });

    testWidgets('zeigt das Thestia-Avatar', (tester) async {
      await tester.pumpWidget(
        _huelle(const InterviewBubble(text: 'Wie möchtest du bleiben?')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
    });

    testWidgets('die Blase sitzt links - die Frage kommt von Thestia', (
      tester,
    ) async {
      await tester.pumpWidget(_huelle(const InterviewBubble(text: 'Frage')));
      await tester.pumpAndSettle();

      final align = tester.widget<Align>(
        find.descendant(
          of: find.byType(InterviewBubble),
          matching: find.byType(Align),
        ),
      );
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('die Blase hat die Sprechblasen-Ecken', (tester) async {
      // Oben links ist die Ecke spitz - das ist der "Schwanz" der
      // Sprechblase. Unten und rechts ist sie rund.
      await tester.pumpWidget(_huelle(const InterviewBubble(text: 'Frage')));
      await tester.pumpAndSettle();

      final radius = _deko(tester).borderRadius! as BorderRadius;
      expect(radius.topLeft.x, 4, reason: 'Der Schwanz der Blase ist spitz.');
      expect(radius.topRight.x, 20);
      expect(radius.bottomLeft.x, 20);
      expect(radius.bottomRight.x, 20);
    });

    testWidgets('die Blase nutzt die Akzentfarbe des Themas', (tester) async {
      await tester.pumpWidget(_huelle(const InterviewBubble(text: 'Frage')));
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byType(InterviewBubble)),
      ).colorScheme;
      expect(_deko(tester).color, scheme.primaryContainer);
    });

    testWidgets('ein langer Text bricht die Blase nicht', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const InterviewBubble(
            text:
                'Magst du dein Konto mit einem Passkey absichern? Das geht '
                'schnell und ist die sicherste Anmeldeart.',
          ),
          scale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
