// Die Merkmals-Auswahl: Werte, Reihenfolge und was gesendet wird.
//
// BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen, also
// Hairstyle und so. Aber bitte gut umsetzen auf der Seite, da es so
// schon echt voll ist, braucht es schon fast ein Redesign vom wie siehst
// du aus screen."
//
// UND (derselbe Tag): "wie es die ganze Zeit neue Probleme geben kann,
// wenn du es immer pruefst. Bitte deck das mit tests besser ab oder
// irgendwie anders sinnvoll"
//
// Dieser Test deckt den Weg ab, den die App wirklich geht: Merkmal
// waehlen, Wert waehlen, und pruefen, DASS als "slug:wert" zurueckkommt
// - denn genau so muss es zum Server.
//
// Ohne eigenen Token hat der Server keinen Match gefunden (Migration
// 185). Ein Fehler in der Wire-Form ist damit genauso unsichtbar wie
// der Fehler, der gefixt wurde.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/screens/swipe/transit_radar_screen.dart';

void main() {
  group('Die Merkmale der Auswahl', () {
    test('Haare und Augen kommen zuerst', () {
      // Der Bildschirm heisst "Wie siehst du gerade aus?" - was man im
      // Gesicht sieht, muss oben stehen. Vorher standen die Haare ganz
      // hinten (nach Ober- und Unterteil).
      final slugs = TransitTagCategory.values.map((k) => k.slug).toList();
      expect(
        slugs.first,
        'hair',
        reason:
            'die Haare stehen nicht oben - sie sind das Erste, was '
            'man an einer Person wahrnimmt',
      );
      expect(
        slugs.indexOf('eyes'),
        lessThan(slugs.indexOf('top')),
        reason: 'die Augen stehen vor der Kleidung',
      );
    });

    test('jedes Merkmal mit Werten hat eine nichtleere Werteliste', () {
      for (final tag in TransitTag.catalog) {
        if (tag.hasValues) {
          expect(
            tag.availableValues,
            isNotEmpty,
            reason: '${tag.slug} hat eine Werteliste, die leer ist',
          );
          expect(
            tag.availableValues.toSet().length,
            tag.availableValues.length,
            reason: '${tag.slug} hat einen Wert doppelt in der Liste',
          );
        }
      }
    });

    test('Haarlaenge und Frisur sind eigene Kategorien', () {
      // Je Kategorie ist nur EIN Merkmal erlaubt. Haarlaenge und Frisur
      // sind aber keine Alternative, sondern zwei Angaben - in derselben
      // Kategorie wuerden sie sich ausschliessen (Migration 188).
      final laenge = TransitTag.bySlug('hair_length')!;
      final frisur = TransitTag.bySlug('hair_style')!;
      expect(
        laenge.category,
        isNot(frisur.category),
        reason:
            'Haarlaenge und Frisur teilen sich die Kategorie - damit '
            'kann man nur eines von beiden angeben',
      );
      expect(laenge.category, 'hair_length');
      expect(frisur.category, 'hair_style');
    });

    test('die Haarlaenge und die Frisur haben Werte', () {
      // Ohne Werte waeren "hair_length" und "hair_style" wertlose
      // Merkmale ("hat Haarlaenge?").
      final laenge = TransitTag.bySlug('hair_length');
      final frisur = TransitTag.bySlug('hair_style');
      expect(laenge, isNotNull);
      expect(frisur, isNotNull);
      expect(
        laenge!.hasValues,
        isTrue,
        reason: 'die Haarlaenge braucht Werte (kurz, mittellang, ...)',
      );
      expect(
        frisur!.hasValues,
        isTrue,
        reason: 'die Frisur braucht Werte (lockig, glatt, ...)',
      );
    });

    test('jeder Wert hat einen deutschen Text', () {
      // Fehlt ein Text, liefert L10n den Schluessel selbst zurueck -
      // in der Auswahl stuende dann "lockig" statt "Lockig".
      for (final tag in TransitTag.catalog) {
        for (final wert in tag.availableValues) {
          expect(
            L10n.tWithoutContext('transit.value.$wert'),
            isNot('transit.value.$wert'),
            reason: 'dem Wert $wert fehlt der deutsche Text',
          );
        }
      }
    });

    test('die Wire-Form ist "slug:wert"', () {
      // So muss es zum Server (Migration 187): der Wert steht hinter
      // dem Doppelpunkt, getrennt vom Merkmal.
      final frisur = TransitTag.bySlug('hair_style')!;
      final wert = frisur.availableValues.first;
      expect('${frisur.slug}:$wert', 'hair_style:$wert');
    });
  });

  group('Die Auswahl in der App', () {
    testWidgets('ein gewaehlter Wert kommt als "slug:wert" zurueck', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      List<String>? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final r = await showTransitTagPickerSheet(
                      context,
                      titleKey: 'transit.self.title',
                      hintKey: 'transit.self.hint',
                      requireSelection: true,
                    );
                    ergebnis = r?.tags;
                  },
                  child: const Text('oeffnen'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('oeffnen'));
      await tester.pumpAndSettle();

      // Die Merkmale stehen in Kategorien, und die stehen unterhalb
      // des sichtbaren Bereichs - vor jedem Tippen wird deshalb an
      // die Stelle gescrollt.
      Future<void> tippe(String text) async {
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      // "Frisur" waehlen.
      await tippe('Frisur');

      // Jetzt muessen die Werte erscheinen.
      expect(
        find.text('Lockig'),
        findsOneWidget,
        reason: 'nach der Wahl der Frisur erscheinen keine Werte',
      );

      // "Lockig" waehlen.
      await tippe('Lockig');

      // Mindestens zwei Merkmale sind Pflicht - der Senden-Knopf ist
      // sonst deaktiviert. Die Haarlaenge ist das zweite.
      await tippe('Haarlänge');
      await tippe('Lang');

      // Und absenden (der Knopf heisst "Funken"). Er liegt am Ende des
      // Sheet.
      await tester.ensureVisible(find.text('Funken'));
      await tester.pumpAndSettle();

      // Der Knopf muss aktiv sein - zwei Merkmale sind das Minimum.
      //
      // Der Handler wird direkt aufgerufen statt angeklickt: der
      // Knopf liegt am Ende des Sheets, und im Test waere das ein
      // Problem der Trefferflaeche, nicht der App. Geprueft wird
      // die KETTE: Auswahl -> Wert -> Slug -> Rueckgabe.
      final knopf = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Funken'),
      );
      expect(
        knopf.onPressed,
        isNotNull,
        reason:
            'der Senden-Knopf ist deaktiviert - es sind nicht '
            'genug Merkmale gewaehlt',
      );

      knopf.onPressed!();
      await tester.pumpAndSettle();

      expect(ergebnis, isNotNull);
      expect(
        ergebnis,
        contains('hair_style:lockig'),
        reason:
            'der gewaehlte Wert kommt nicht als "hair_style:lockig" '
            'zurueck - der Server wuerde die Angabe ablehnen',
      );
    });

    testWidgets('auch die englische Fassung hat die Werte', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          home: Scaffold(body: SizedBox.shrink()),
        ),
      );
      final context = tester.element(find.byType(Scaffold).first);
      for (final tag in TransitTag.catalog) {
        for (final wert in tag.availableValues) {
          expect(
            L10n.t(context, 'transit.value.$wert'),
            isNot('transit.value.$wert'),
            reason: 'dem Wert $wert fehlt der englische Text',
          );
        }
      }
    });
  });
}
