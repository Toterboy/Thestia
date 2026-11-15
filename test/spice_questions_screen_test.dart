// Die Eisbrecher-Fragen (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/spice/spice_questions_screen.dart 0 % - der Screen, ueber
// den der Nutzer eine gute Frage in den Chat holt.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen zeigt die Kategorien aus dem Katalog,
//   * eine aufgeklappte Kategorie zeigt ihre Fragen,
//   * die Suche filtert - und sagt, wenn sie nichts findet,
//   * ein Tipp auf eine Frage fragt nach (kopieren oder senden),
//   * "Kopieren" legt die Frage in die Zwischenablage und sagt es.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/data/icebreaker_catalog.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/spice/spice_questions_screen.dart';

void main() {
  /// Der Text, der zuletzt in die Zwischenablage gelegt wurde.
  ///
  /// DER GRUND FUER DEN EIGENEN KANAL: Die Zwischenablage des Geraets
  /// gibt es im Test nicht - ohne Ersatz bleibt der Aufruf haengen
  /// (der Test wartet dann bis zum Zeitueberlauf).
  String? kopierterText;

  setUp(() {
    kopierterText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (anruf) async {
          if (anruf.method == 'Clipboard.setData') {
            final argumente = (anruf.arguments as Map?)
                ?.cast<String, dynamic>();
            kopierterText = argumente?['text'] as String?;
            return null;
          }
          if (anruf.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': kopierterText};
          }
          return null;
        });
  });

  /// Baut den Screen mit einem Router (er nutzt context.pop/go).
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/spice',
      routes: [
        GoRoute(
          path: '/spice',
          builder: (context, state) => const SpiceQuestionsScreen(matchId: 42),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Die erste Frage des Katalogs (sie ist garantiert vorhanden).
  IcebreakerQuestion ersteFrage() => icebreakerCatalog.first.questions.first;

  /// Klappt die erste Kategorie auf - die Fragen stecken dahinter.
  Future<void> klappeAuf(WidgetTester tester) async {
    await tester.tap(
      find.text(icebreakerCatalog.first.titleFor('de')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  group('Die Eisbrecher-Fragen', () {
    testWidgets('der Screen zeigt die Kategorien', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Die Kopfzeile steht da.
      expect(find.text(L10n.tWithoutContext('spice.title')), findsOneWidget);
      // Und das Suchfeld.
      expect(find.byType(TextField), findsOneWidget);
      // Die erste Kategorie steht da (mit der Frage-Anzahl).
      expect(
        find.text(icebreakerCatalog.first.titleFor('de')),
        findsOneWidget,
        reason: 'Die erste Kategorie muss stehen.',
      );
    });

    testWidgets('eine aufgeklappte Kategorie zeigt ihre Fragen', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await klappeAuf(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(ersteFrage().textFor('de')), findsOneWidget);
    });

    testWidgets('die Suche filtert', (tester) async {
      await zeigeScreen(tester);

      // Ein Wort, das in der ersten Frage steht.
      final wort = ersteFrage().de
          .split(' ')
          .first
          .replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß]'), '');
      await tester.enterText(find.byType(TextField), wort);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Die Treffer-Kategorie steht da (und nur die passenden).
      final treffer = icebreakerCatalog.where(
        (c) => c.questions.any(
          (f) => f.de.toLowerCase().contains(wort.toLowerCase()),
        ),
      );
      expect(treffer, isNotEmpty);
      expect(
        find.text(treffer.first.titleFor('de')),
        findsOneWidget,
        reason: 'Die gefundene Kategorie muss stehen.',
      );
    });

    testWidgets('eine Suche ohne Treffer sagt es', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextField), 'xyzqwxyznichtda');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('spice.emptySearch')),
        findsOneWidget,
        reason:
            'Eine Suche ohne Treffer muss es sagen - eine leere Seite sieht '
            'wie ein Fehler aus.',
      );
    });

    testWidgets('ein Tipp auf eine Frage fragt nach', (tester) async {
      await zeigeScreen(tester);
      await klappeAuf(tester);

      await tester.tap(find.text(ersteFrage().textFor('de')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('spice.sendTitle')),
        findsOneWidget,
      );
      // Beide Wege stehen da.
      expect(
        find.text(L10n.tWithoutContext('spice.copyTooltip')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('spice.sendBtn')), findsOneWidget);
    });

    testWidgets('"Kopieren" legt die Frage in die Zwischenablage', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await klappeAuf(tester);

      await tester.tap(find.text(ersteFrage().textFor('de')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.tWithoutContext('spice.copyTooltip')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Die Frage liegt in der Zwischenablage ...
      final kopie = await Clipboard.getData(Clipboard.kTextPlain);
      expect(kopie?.text, ersteFrage().textFor('de'));
      expect(kopierterText, ersteFrage().textFor('de'));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text(L10n.tWithoutContext('spice.copied')), findsOneWidget);
    });
  });
}
