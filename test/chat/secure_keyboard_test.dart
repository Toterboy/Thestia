// Test für die eigene Tastatur der App (v0.10.1).
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
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import 'package:thestia/widgets/chat/secure_keyboard.dart';

/// Der Speicher im RAM (der Composer liest die Einstellungen daraus).
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Composer im Test.
///
/// DER GRUND (27.11.2026): Der Composer holt sich die Wahl der Belegung
/// und der Farben selbst aus den Einstellungen - damit keine Stelle sie
/// vergessen kann. Er braucht deshalb den Speicher der App.
Widget hause(
  TextEditingController controller, {
  VoidCallback? onSend,
  bool enterSends = false,
}) {
  return ProviderScope(
    overrides: <Override>[localStorageProvider.overrideWithValue(_Speicher())],
    child: MaterialApp(
      home: Scaffold(
        body: SecureComposer(
          controller: controller,
          onSend: onSend ?? () {},
          enterSends: enterSends,
        ),
      ),
    ),
  );
}

void main() {
  group('Die eigene Tastatur', () {
    testWidgets('sie erscheint, wenn man das Eingabefeld antippt', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller, onSend: () => gesendet++));

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
        hause(controller, onSend: () => gesendet++, enterSends: true),
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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
      await tester.pumpWidget(hause(controller));

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
          overrides: [
            localeProvider.overrideWith((ref) => locale),
            // DER SPEICHER: Der Composer holt sich die Wahl der Belegung
            // und der Farben selbst aus den Einstellungen.
            localStorageProvider.overrideWithValue(_Speicher()),
          ],
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

      // Und keine Umlaute - dafür die Satzzeichen.
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
