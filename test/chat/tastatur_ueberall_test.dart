// Die eigene Tastatur nimmt die Einstellungen überall an.
//
// ANLASS (27.11.2026): Der Betreiber meldete: "Die eigene Tastatur wird
// nicht überall angewendet."
//
// DIE URSACHE: Die drei Werte (Belegung, Stil, Farbe) mussten an jeder
// Stelle durchgereicht werden. Im Chat und im Zufallschat standen sie,
// im Dating-Hour-Chat fehlten sie - dort galt immer der Standard.
//
// DER WEG: Der Composer ([SecureComposer]) holt sich die Werte selbst
// aus den Einstellungen. Damit kann keine Stelle sie vergessen.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Belegung folgt der Einstellung - auch wenn die App-Sprache
//     etwas anderes sagt (deutsch in einer englischen App),
//   * die eigene Farbe wird übernommen,
//   * der Composer nimmt den Wert ausdrücklich gesetzter Parameter,
//     wenn einer kommt (der Vorrang für Sonderfälle).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import 'package:thestia/widgets/chat/secure_keyboard.dart';

/// Der Speicher im RAM - die Einstellungen kommen daraus.
class _Speicher implements LocalStorage {
  _Speicher([Map<String, dynamic> einstellungen = const {}]) {
    if (einstellungen.isNotEmpty) {
      _daten[AppConstants.prefsSettingsKey] = jsonEncode(einstellungen);
    }
  }

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

/// Der Composer mit den vorgegebenen Einstellungen.
Widget hause(
  TextEditingController controller, {
  Map<String, dynamic> einstellungen = const {},
  Locale? sprache,
  TastaturBelegung? layout,
  TastaturStil? stil,
  int? farbe,
}) {
  return ProviderScope(
    overrides: <Override>[
      localStorageProvider.overrideWithValue(_Speicher(einstellungen)),
      if (sprache != null) localeProvider.overrideWith((ref) => sprache),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: L10nScope(
          child: SecureComposer(
            controller: controller,
            onSend: () {},
            layout: layout,
            stil: stil,
            farbe: farbe,
          ),
        ),
      ),
    ),
  );
}

/// Öffnet die Tastatur (ein Tap auf das Eingabefeld).
Future<void> tastaturOeffnen(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pumpAndSettle();
}

void main() {
  group('Die Belegung folgt der Einstellung', () {
    testWidgets('deutsch gilt auch in einer englischen App', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        hause(
          controller,
          einstellungen: <String, dynamic>{
            'tastaturBelegung': TastaturBelegung.deutsch.wert,
          },
          sprache: const Locale('en'),
        ),
      );
      await tastaturOeffnen(tester);

      // QWERTZ: Das "z" steht in der ersten Reihe, das "y" in der dritten.
      final y = tester.getTopLeft(find.text('y')).dy;
      final z = tester.getTopLeft(find.text('z')).dy;
      expect(
        y,
        greaterThan(z),
        reason:
            'Die App ist englisch, aber die Einstellung sagt Deutsch - '
            'das "z" muss oben stehen.',
      );
      // Und die Umlaute sind eigene Tasten.
      expect(find.text('ä'), findsOneWidget);
    });

    testWidgets('englisch gilt auch in einer deutschen App', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        hause(
          controller,
          einstellungen: <String, dynamic>{
            'tastaturBelegung': TastaturBelegung.englisch.wert,
          },
          sprache: const Locale('de'),
        ),
      );
      await tastaturOeffnen(tester);

      // QWERTY: Das "y" steht oben, das "z" unten.
      final y = tester.getTopLeft(find.text('y')).dy;
      final z = tester.getTopLeft(find.text('z')).dy;
      expect(
        y,
        lessThan(z),
        reason:
            'Die App ist deutsch, aber die Einstellung sagt Englisch - '
            'das "y" muss oben stehen.',
      );
      // Und keine Umlaute, dafür die Satzzeichen.
      expect(find.text('ä'), findsNothing);
      expect(find.text(','), findsOneWidget);
    });

    testWidgets('ohne Einstellung folgt die Belegung der App', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(hause(controller, sprache: const Locale('de')));
      await tastaturOeffnen(tester);

      expect(find.text('ä'), findsOneWidget);
    });
  });

  group('Die Animation', () {
    testWidgets('die Tastatur fährt ein', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(hause(controller));
      await tester.tap(find.byType(TextField));
      // Ein Frame: die Animation läuft noch.
      await tester.pump();

      final waehrend = tester.getSize(find.byType(AnimatedSize)).height;

      await tester.pumpAndSettle();
      final ende = tester.getSize(find.byType(AnimatedSize)).height;

      expect(
        waehrend,
        lessThan(ende),
        reason:
            'Die Tastatur muss einfahren - wie die des Systems. Vorher '
            'war sie einfach da.',
      );
      expect(ende, greaterThan(0));
    });
  });

  group('Der Wechsel zwischen den Tastaturen', () {
    testWidgets('der Knopf schaltet auf die System-Tastatur', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(hause(controller));
      await tastaturOeffnen(tester);

      // Die eigene Tastatur ist da.
      expect(find.byType(SecureKeyboard), findsOneWidget);
      final feld = tester.widget<TextField>(find.byType(TextField));
      expect(
        feld.readOnly,
        isTrue,
        reason:
            'Die eigene Tastatur sieht keinen einzigen Buchstaben der '
            'Systemtastatur - das Feld bleibt gesperrt.',
      );

      // Der Knopf daneben schaltet um.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      expect(
        find.byType(SecureKeyboard),
        findsNothing,
        reason: 'Die eigene Tastatur muss verschwinden.',
      );
      final feld2 = tester.widget<TextField>(find.byType(TextField));
      expect(
        feld2.readOnly,
        isFalse,
        reason:
            'In der System-Tastatur muss man schreiben können - das Feld '
            'darf also nicht gesperrt sein.',
      );
    });

    testWidgets('in der System-Tastatur wird der Text geschrieben', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(hause(controller));
      await tastaturOeffnen(tester);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hallo');
      await tester.pump();

      expect(controller.text, 'Hallo');
    });

    testWidgets('der Knopf bringt wieder die eigene Tastatur', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(hause(controller));
      await tastaturOeffnen(tester);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      // Zurück zur eigenen Tastatur.
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();

      expect(find.byType(SecureKeyboard), findsOneWidget);
      final feld = tester.widget<TextField>(find.byType(TextField));
      expect(
        feld.readOnly,
        isTrue,
        reason:
            'Zurück in der eigenen Tastatur muss das Feld wieder gesperrt '
            'sein - sonst sieht die Systemtastatur mit.',
      );
    });
  });

  group('Die Farbe folgt der Einstellung', () {
    testWidgets('die eigene Farbe wird übernommen', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        hause(
          controller,
          einstellungen: <String, dynamic>{
            'tastaturStil': TastaturStil.eigeneFarbe.wert,
            'tastaturFarbe': 0xFF1B5E20,
          },
        ),
      );
      await tastaturOeffnen(tester);

      // Auf der dunklen Fläche muss der Text hell sein.
      final text = tester.widget<Text>(find.text('q'));
      expect(
        text.style?.color,
        Colors.white,
        reason:
            'Auf der eigenen dunklen Farbe muss der Text hell sein - '
            'sonst wäre die Tastatur unlesbar.',
      );
    });

    testWidgets('der Vorrang gilt für ausdrücklich gesetzte Werte', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      // Die Einstellung sagt Englisch, der Aufrufer will Deutsch.
      await tester.pumpWidget(
        hause(
          controller,
          einstellungen: <String, dynamic>{
            'tastaturBelegung': TastaturBelegung.englisch.wert,
          },
          sprache: const Locale('de'),
          layout: TastaturBelegung.deutsch,
        ),
      );
      await tastaturOeffnen(tester);

      expect(find.text('ä'), findsOneWidget);
    });
  });
}
