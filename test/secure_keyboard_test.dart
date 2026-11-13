// Test fuer die eigene Tastatur der App (v0.10.1).
//
// WUNSCH DES BETREIBERS (13.11.2026): "dass die Handytastatur nicht
// tracken kann was man schreibt".
//
// DER TEST HALT FEST, DASS DAS WIRKLICH SO IST:
//  1. Das Eingabefeld steht auf `readOnly` und nutzt `TextInputType.none`
//     - auf Android und iOS entsteht damit gar keine Eingabeverbindung,
//     die Systemtastatur sieht also keinen einzigen Buchstaben.
//  2. Die App hat ihre eigene Tastatur, und die schreibt direkt in den
//     Textcontroller.
//  3. Die Tastatur lernt nicht aus dem, was eingegeben wird
//     (`enableIMEPersonalizedLearning: false`).
//  4. Eine Hardwaretastatur funktioniert weiterhin.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/secure_composer.dart';
import 'package:thestia/widgets/secure_keyboard.dart';

void main() {
  group('Die eigene Tastatur', () {
    testWidgets('sie erscheint, wenn man das Eingabefeld antippt', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      expect(find.byType(SecureKeyboard), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.byType(SecureKeyboard), findsOneWidget);
      controller.dispose();
    });

    testWidgets('das Eingabefeld gibt der Systemtastatur nichts', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      final feld = tester.widget<TextField>(find.byType(TextField));
      // `readOnly` ist der entscheidende Punkt: bei einem readOnly-Feld
      // entsteht auf Android und iOS keine Eingabeverbindung.
      expect(feld.readOnly, isTrue);
      expect(feld.keyboardType, TextInputType.none);
      // Und die Tastatur lernt nicht aus dem, was eingegeben wird.
      expect(feld.enableIMEPersonalizedLearning, isFalse);
      controller.dispose();
    });

    testWidgets('getippte Zeichen landen im Text', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      for (final zeichen in <String>['h', 'a', 'l', 'l', 'o']) {
        await tester.tap(find.text(zeichen));
        await tester.pump();
      }

      expect(controller.text, 'hallo');
      controller.dispose();
    });

    testWidgets('die Umlaute sind eigene Tasten', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ä'));
      await tester.tap(find.text('ö'));
      await tester.tap(find.text('ü'));
      await tester.tap(find.text('ß'));
      await tester.pump();

      expect(controller.text, 'äöüß');
      controller.dispose();
    });

    testWidgets('die Umschaltung macht Grossbuchstaben', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();

      await tester.tap(find.text('H'));
      await tester.pump();

      expect(controller.text, 'H');
      controller.dispose();
    });

    testWidgets('Backspace loescht das letzte Zeichen', (tester) async {
      final controller = TextEditingController(text: 'Hallo');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(controller.text, 'Hall');
      controller.dispose();
    });

    testWidgets('Enter fuegt einen Umbruch ein', (tester) async {
      final controller = TextEditingController();
      var gesendet = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(
              controller: controller,
              onSend: () => gesendet++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_return));
      await tester.pump();

      expect(controller.text, '\n');
      expect(gesendet, 0);
      controller.dispose();
    });

    testWidgets('mit "Enter sendet" sendet Enter', (tester) async {
      final controller = TextEditingController();
      var gesendet = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(
              controller: controller,
              onSend: () => gesendet++,
              enterSends: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_return));
      await tester.pump();

      expect(gesendet, 1);
      controller.dispose();
    });

    testWidgets('die Hardwaretastatur funktioniert auch', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();

      expect(controller.text, 'hi');
      controller.dispose();
    });

    testWidgets('die Tastatur laesst sich wieder ausblenden', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(SecureKeyboard), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_hide_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(SecureKeyboard), findsNothing);
      controller.dispose();
    });

    testWidgets('die Emoji-Auswahl funktioniert', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecureComposer(controller: controller, onSend: () {}),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('😀'));
      await tester.pump();

      expect(controller.text, '😀');
      controller.dispose();
    });
  });

  group('Die Belegung folgt der Sprache', () {
    Widget host(TextEditingController controller, Locale locale) =>
        ProviderScope(
          overrides: [localeProvider.overrideWith((ref) => locale)],
          child: MaterialApp(
            home: Scaffold(
              body: L10nScope(
                child: SecureComposer(controller: controller, onSend: () {}),
              ),
            ),
          ),
        );

    testWidgets('Deutsch hat QWERTZ (y unten, z oben)', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(controller, const Locale('de')));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final y = tester.getTopLeft(find.text('y')).dy;
      final z = tester.getTopLeft(find.text('z')).dy;
      // Im deutschen QWERTZ steht das "z" in der ersten Reihe und das
      // "y" in der dritten - also ist "y" weiter unten.
      expect(y, greaterThan(z));

      // Und die Umlaute sind eigene Tasten.
      expect(find.text('ä'), findsOneWidget);
      expect(find.text('ß'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('Englisch hat QWERTY (y oben, z unten)', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(controller, const Locale('en')));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final y = tester.getTopLeft(find.text('y')).dy;
      final z = tester.getTopLeft(find.text('z')).dy;
      expect(y, lessThan(z));

      // Und keine Umlaute - dafuer die Satzzeichen.
      expect(find.text('ä'), findsNothing);
      expect(find.text('ß'), findsNothing);
      expect(find.text(','), findsOneWidget);
      controller.dispose();
    });

    testWidgets('auf der englischen Belegung wird richtig getippt', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(controller, const Locale('en')));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      for (final zeichen in <String>['z', 'y', 'x']) {
        await tester.tap(find.text(zeichen));
        await tester.pump();
      }

      expect(controller.text, 'zyx');
      controller.dispose();
    });

    testWidgets('die Belegung wechselt mit der Sprache', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(controller, const Locale('de')));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('ä'), findsOneWidget);

      // Die App-Sprache umstellen (das ist der Sprachumschalter).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SecureComposer)),
      );
      container.read(localeProvider.notifier).state = const Locale('en');
      await tester.pumpAndSettle();

      expect(find.text('ä'), findsNothing);
      expect(find.text('y'), findsOneWidget);
      controller.dispose();
    });
  });
}
