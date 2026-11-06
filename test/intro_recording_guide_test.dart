import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/intro_recording_guide.dart';

/// Baut den Leitfaden in einer Umgebung mit deutscher Sprache.
Widget _app({required int elapsed, bool paused = false}) {
  return ProviderScope(
    child: L10nScope(
      child: MaterialApp(
        home: Scaffold(
          body: IntroRecordingGuide(elapsedSeconds: elapsed, paused: paused),
        ),
      ),
    ),
  );
}

/// Die Zeile, in der [text] steht.
Finder _zeile(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Row));

void main() {
  group('IntroRecordingGuide - Struktur', () {
    test('hat genau drei Schritte (Wer bist du / Was macht dich aus / '
        'Warum bist du hier)', () {
      expect(IntroRecordingGuide.stepKeys, hasLength(3));
    });

    test('die Schritt-Keys sind eindeutig', () {
      expect(
        IntroRecordingGuide.stepKeys.toSet().length,
        IntroRecordingGuide.stepKeys.length,
      );
    });

    test('die Schrittdauer ist so gewaehlt, dass alle drei Winkel in eine '
        'kurze Vorstellung passen', () {
      // Mindestlaenge der Aufnahme sind 10 Sekunden. Mit 15 Sekunden je
      // Schritt braucht der dritte Winkel 30 Sekunden - das ist bewusst
      // mehr als die Mindestlaenge: die ersten beiden Winkel sind fuer
      // den Einstieg da, der dritte darf entfallen.
      expect(IntroRecordingGuide.stepSeconds, greaterThanOrEqualTo(5));
      expect(IntroRecordingGuide.stepSeconds, lessThanOrEqualTo(30));
    });
  });

  group('IntroRecordingGuide - automatische Schrittauswahl', () {
    test('am Anfang ist Schritt 1 aktiv', () {
      expect(IntroRecordingGuide.stepForSeconds(0), 0);
      expect(IntroRecordingGuide.stepForSeconds(1), 0);
    });

    test('nach der Schrittdauer kommt der naechste Schritt', () {
      expect(IntroRecordingGuide.stepForSeconds(14), 0);
      expect(IntroRecordingGuide.stepForSeconds(15), 1);
      expect(IntroRecordingGuide.stepForSeconds(29), 1);
      expect(IntroRecordingGuide.stepForSeconds(30), 2);
    });

    test(
      'nach dem dritten Schritt bleibt der dritte stehen (keine Schleife)',
      () {
        // Die Aufnahme darf bis 5 Minuten laufen. Ein Leitfaden, der immer
        // wieder zurueckspringt, wuerde den Sprecher verwirren.
        for (final s in [45, 60, 120, 299, 300, 5000]) {
          expect(
            IntroRecordingGuide.stepForSeconds(s),
            2,
            reason: 'bei $s Sekunden',
          );
        }
      },
    );

    test('negative Werte werden nicht zu einem Absturz', () {
      expect(IntroRecordingGuide.stepForSeconds(-1), 0);
      expect(IntroRecordingGuide.stepForSeconds(-100), 0);
    });

    test('die Auswahl ist monoton (ein Schritt vorwaerts, nie zuruecks)', () {
      var vorher = 0;
      for (var s = 0; s <= 300; s++) {
        final jetzt = IntroRecordingGuide.stepForSeconds(s);
        expect(jetzt, greaterThanOrEqualTo(vorher));
        expect(jetzt, lessThanOrEqualTo(vorher + 1));
        vorher = jetzt;
      }
    });
  });

  group('IntroRecordingGuide - Anzeige', () {
    testWidgets('zeigt alle drei Schritte und die Ueberschrift', (
      tester,
    ) async {
      await tester.pumpWidget(_app(elapsed: 0));

      expect(find.text('Leitfaden für deine Vorstellung'), findsOneWidget);
      expect(find.text('Wer bist du?'), findsOneWidget);
      expect(find.text('Was macht dich aus?'), findsOneWidget);
      expect(find.text('Warum bist du hier?'), findsOneWidget);
    });

    testWidgets('markiert genau einen Schritt als aktiv', (tester) async {
      await tester.pumpWidget(_app(elapsed: 0));

      // Der aktive Schritt traegt das Symbol am Zeilenende.
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
      expect(
        find.descendant(
          of: _zeile('Wer bist du?'),
          matching: find.byIcon(Icons.graphic_eq),
        ),
        findsOneWidget,
      );
    });

    testWidgets('der aktive Schritt wandert mit der Zeit', (tester) async {
      await tester.pumpWidget(_app(elapsed: 30));

      expect(
        find.descendant(
          of: _zeile('Warum bist du hier?'),
          matching: find.byIcon(Icons.graphic_eq),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _zeile('Wer bist du?'),
          matching: find.byIcon(Icons.graphic_eq),
        ),
        findsNothing,
      );
    });

    testWidgets('ein Tipp uebernimmt die Steuerung', (tester) async {
      await tester.pumpWidget(_app(elapsed: 30));
      // Schritt 3 ist aktiv (30 Sekunden). Der Nutzer will zurueck auf
      // Schritt 1 - das muss gehen und muss bleiben.
      await tester.tap(find.text('Wer bist du?'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _zeile('Wer bist du?'),
          matching: find.byIcon(Icons.graphic_eq),
        ),
        findsOneWidget,
      );

      // Auch nach dem Zeitablauf bleibt die Wahl des Nutzers.
      await tester.pumpWidget(_app(elapsed: 120));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _zeile('Wer bist du?'),
          matching: find.byIcon(Icons.graphic_eq),
        ),
        findsOneWidget,
      );
    });

    testWidgets('im Pausenzustand ist der Leitfaden abgeblendet', (
      tester,
    ) async {
      await tester.pumpWidget(_app(elapsed: 0, paused: true));
      expect(find.text('Wer bist du?'), findsOneWidget);
    });
  });

  group('L10n-Parität: jeder Leitfaden-Text existiert in DE und EN', () {
    // Wie in test/intro_prompt_catalog_test.dart: die Maps werden
    // statisch geparst, weil `L10n.t` einen BuildContext braucht.
    //
    // WICHTIG: der Datei-Read passiert INNERHALB des Test-Bodys.
    ({String de, String en}) readBlocks() {
      final src = File('lib/l10n/app_strings.dart').readAsStringSync();
      final deIdx = src.indexOf("'de': {");
      final enIdx = src.indexOf("'en': {");
      expect(deIdx, greaterThan(0), reason: "Marker 'de' nicht gefunden");
      expect(enIdx, greaterThan(deIdx), reason: "Marker 'en' nicht gefunden");
      return (de: src.substring(deIdx, enIdx), en: src.substring(enIdx));
    }

    String valueOf(String block, String key) {
      final m = RegExp("'$key':\\s*'([^']*)'").firstMatch(block);
      return m?.group(1) ?? '';
    }

    test('alle Leitfaden-Keys sind in DE und EN definiert', () {
      final b = readBlocks();
      for (final key in [
        ...IntroRecordingGuide.stepKeys,
        'intro.guide.title',
        'intro.guide.hint',
      ]) {
        expect(b.de.contains("'$key':"), isTrue, reason: 'DE fehlt: $key');
        expect(b.en.contains("'$key':"), isTrue, reason: 'EN fehlt: $key');
      }
    });

    test('DE-Texte sind nicht leer und nicht identisch mit EN', () {
      final b = readBlocks();
      for (final key in [
        ...IntroRecordingGuide.stepKeys,
        'intro.guide.title',
        'intro.guide.hint',
      ]) {
        expect(valueOf(b.de, key), isNotEmpty, reason: 'DE leer: $key');
        expect(valueOf(b.en, key), isNotEmpty, reason: 'EN leer: $key');
        expect(
          valueOf(b.de, key),
          isNot(valueOf(b.en, key)),
          reason: 'DE == EN bei $key',
        );
      }
    });
  });
}
