// Die Musik-Geschmack-Auswahl (Gemagte Genres + "mag ich nicht").
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/music_taste_widgets.dart 74 offene Zeilen - der
// Katalog war getestet, die beiden Oberflächen aber gar nicht.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein Klick auf ein Genre mag es (und ein zweiter Klick macht es
//     wieder neutral),
//   * ein verneintes Genre wird neutral, wenn man es im oberen Feld
//     antippt (es darf nicht in beiden Listen stehen),
//   * das Ausschliessen-Sheet: es bietet nur freie Genres, die Suche
//     filtert, ohne Treffer wird das gesagt, und die Wahl landet in
//     der Liste der verneinten Genres,
//   * die Anzeige bei einem fremden Profil: leere Angabe, gemagte
//     Genres (gemeinsame hervorgehoben), verneinte Genres mit Kreuz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/profile/music_taste_widgets.dart';

void main() {
  /// Was der Editor zuletzt gemeldet hat.
  List<String>? letzteGemochte;
  List<String>? letzteVerneinte;

  setUp(() {
    letzteGemochte = null;
    letzteVerneinte = null;
  });

  /// Baut den Editor (die Listen kommen aus dem Callback zurück).
  Future<void> zeigeEditor(
    WidgetTester tester, {
    List<String> liked = const [],
    List<String> disliked = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MusicTasteEditor(
              liked: liked,
              disliked: disliked,
              onChanged: (l, d) {
                letzteGemochte = l;
                letzteVerneinte = d;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Tippt auf ein Genre-Chip.
  ///
  /// ACHTUNG: Ein Genre, das gemocht UND verneint ist, steht zweimal da
  /// (oben in der "mag ich"-Reihe, unten in der "mag ich nicht"-Reihe).
  /// [unten] wählt das untere Chip.
  Future<void> tippeChip(
    WidgetTester tester,
    String label, {
    bool unten = false,
  }) async {
    final alle = find.widgetWithText(FilterChip, label);
    final chip = unten ? alle.last : alle.first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
  }

  group('Die Auswahl', () {
    testWidgets('ein Klick auf ein Genre mag es', (tester) async {
      await zeigeEditor(tester);

      await tippeChip(tester, 'Pop');

      expect(letzteGemochte, ['pop']);
      expect(letzteVerneinte, isEmpty);
    });

    testWidgets('ein zweiter Klick macht das Genre wieder neutral', (
      tester,
    ) async {
      await zeigeEditor(tester, liked: <String>['pop']);

      await tippeChip(tester, 'Pop');

      expect(
        letzteGemochte,
        isEmpty,
        reason:
            'Ein Genre, das man mag und dann wieder wegklickt, ist neutral '
            '- es darf nicht in beiden Listen stehen.',
      );
    });

    testWidgets('ein verneintes Genre wird oben neutral', (tester) async {
      await zeigeEditor(tester, disliked: <String>['rock']);

      // DAS OBERE FELD: Jedes Genre hat oben einen Chip - auch das
      // verneinte. Der Klick zieht es dort zurück.
      await tippeChip(tester, 'Rock');

      expect(
        letzteVerneinte,
        isEmpty,
        reason:
            'Ein Genre darf nicht gleichzeitig gemocht UND verneint sein - '
            'der Klick im oberen Feld nimmt es aus der Verweiner-Liste.',
      );
      expect(letzteGemochte, isEmpty);
    });

    testWidgets('ein verneintes Genre wird unten neutral', (tester) async {
      await zeigeEditor(tester, disliked: <String>['rock']);

      // DAS UNTERE FELD: Hier stehen die verneinten Genres (mit dem
      // Fehler-Kreuz) - der Klick nimmt es aus dieser Liste.
      await tippeChip(tester, 'Rock', unten: true);

      expect(letzteVerneinte, isEmpty);
      expect(
        letzteGemochte,
        isEmpty,
        reason: 'Das Genre war nicht gemocht - es darf es nicht werden.',
      );
    });
  });

  group('Das Ausschliessen-Sheet', () {
    /// Öffnet das Sheet und wartet, bis es steht.
    Future<void> oeffneSheet(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(InputChip, 'Genre ausschließen…'));
      await tester.pumpAndSettle();
    }

    /// Alles, was IM Sheet steht (nicht die Seite dahinter).
    Finder imSheet(Finder finder) =>
        find.descendant(of: find.byType(BottomSheet), matching: finder);

    testWidgets('es bietet nur Genres an, die noch frei sind', (tester) async {
      await zeigeEditor(
        tester,
        liked: <String>['pop'],
        disliked: <String>['rock'],
      );

      await oeffneSheet(tester);

      expect(imSheet(find.text('Pop')), findsNothing);
      expect(imSheet(find.text('Rock')), findsNothing);
      expect(
        imSheet(find.text('Indie')),
        findsOneWidget,
        reason:
            'Die freien Genres stehen zur Wahl - "Indie" ist weder gemocht '
            'noch verneint.',
      );
    });

    testWidgets('die Suche filtert die Liste', (tester) async {
      await zeigeEditor(tester);

      await oeffneSheet(tester);

      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();

      expect(imSheet(find.text('Jazz')), findsOneWidget);
      expect(imSheet(find.text('Techno')), findsNothing);
    });

    testWidgets('ohne Treffer wird das gesagt', (tester) async {
      await zeigeEditor(tester);

      await oeffneSheet(tester);

      await tester.enterText(find.byType(TextField), 'gibtsnicht');
      await tester.pumpAndSettle();

      expect(imSheet(find.text('Kein Genre gefunden.')), findsOneWidget);
    });

    testWidgets('die Wahl landet in der Liste der verneinten Genres', (
      tester,
    ) async {
      await zeigeEditor(tester);

      await oeffneSheet(tester);
      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();
      await tester.tap(imSheet(find.text('Jazz')));
      await tester.pumpAndSettle();

      expect(letzteVerneinte, contains('jazz'));
      expect(
        letzteGemochte,
        isEmpty,
        reason:
            'Ein ausgeschlossenes Genre darf nicht auch gemocht sein - '
            'sonst weiss der Nutzer nicht, was der Server speichert.',
      );
    });

    testWidgets('das Sheet laesst sich schliessen ohne Auswahl', (
      tester,
    ) async {
      await zeigeEditor(tester);

      await oeffneSheet(tester);
      // DER AUSSERNE TAP: Der Weg zurück, ohne etwas zu wählen.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(letzteVerneinte, isNull);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('Die Anzeige bei einem fremden Profil', () {
    Future<void> zeigeAnsicht(
      WidgetTester tester, {
      List<String> liked = const [],
      List<String> disliked = const [],
      List<String> commonWith = const [],
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: MusicTasteView(
              liked: liked,
              disliked: disliked,
              commonWith: commonWith,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('ohne Angabe steht das dort', (tester) async {
      await zeigeAnsicht(tester);

      expect(find.text('Kein Musik-Geschmack angegeben.'), findsOneWidget);
    });

    testWidgets('die gemochten Genres stehen als Chips da', (tester) async {
      await zeigeAnsicht(tester, liked: <String>['pop', 'jazz']);

      expect(find.widgetWithText(Chip, 'Pop'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Jazz'), findsOneWidget);
    });

    testWidgets('ein gemeinsames Genre ist hervorgehoben', (tester) async {
      await zeigeAnsicht(
        tester,
        liked: <String>['pop', 'jazz'],
        commonWith: <String>['pop'],
      );

      final chip = tester.widget<Chip>(find.widgetWithText(Chip, 'Pop'));
      expect(chip.backgroundColor, isNotNull);
      final anders = tester.widget<Chip>(find.widgetWithText(Chip, 'Jazz'));
      expect(anders.backgroundColor, isNull);
    });

    testWidgets('die verneinten Genres tragen ein Kreuz', (tester) async {
      await zeigeAnsicht(tester, disliked: <String>['rock']);

      expect(find.widgetWithText(Chip, 'Rock ✕'), findsOneWidget);
    });
  });
}
