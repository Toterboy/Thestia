// Die Tests 'store_v091_shots' (Teil 1).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/store_v091_shots_hilfen.dart.

// Store-Screenshot-Generator fuer v0.9.1 (KEIN regulaerer Test).
//
// Rendert 5 ausgewahlte Screens in ZWEI Aufloesungen:
//   9:16  -> 1080x1920  (Play-Store-Standard fuer Handys)
//   WQHD  -> 2560x1440  (16:9, Tablet-/Landscape-Variante)
//
// Aufruf (schreibt/aktualisiert):
//   $env:STORE_SHOTS="1"; flutter test --update-goldens test/screenshots/store_v091_shots_test.dart
//
// Ausgabe: test/screenshots/store_v091/{9x16,wqhd}/*.png
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/screens/home/home_screen.dart';
import 'package:thestia/screens/spice/spice_questions_screen.dart';
import 'package:thestia/screens/swipe/swipe_mode_selection_screen.dart';
import 'package:thestia/screens/welcome/welcome_screen.dart';
import 'package:thestia/widgets/appearance_selector.dart';
import 'package:thestia/widgets/app_logo.dart';
import 'package:thestia/widgets/chat_background_picker.dart';
import 'package:thestia/widgets/privacy_section.dart';
import 'package:thestia/widgets/theme_picker.dart';

import 'hilfen.dart';

void main() {
  if (enabled) {
    testWidgets('export Kacheln 01 (Logo und Text)', (tester) async {
      await pump(
        tester,
        const WelcomeScreen(),
        outDir: outCards,
        name: '01_willkommen',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
      );
      final content = find.byKey(const Key('welcome-page-content'));
      expect(
        content,
        findsOneWidget,
        reason: 'der Key welcome-page-content fehlt in WelcomeScreen',
      );
      // Das Rechteck ist die VEREINIGUNG von Logo, Titel und Text, nicht
      // die Column. Die Column fuellt den ganzen Seitenbereich
      // (mainAxisAlignment.center in einem Expanded), ihr Rechteck ist
      // deshalb 574 dp hoch und die Kachel wurde ein grosses weisses
      // Rechteck mit einem Fleck darin. Der weisse Rand kommt in
      // make_store_screenshots.py dazu (CARD_MARGIN_LOGICAL).
      final logo = find.descendant(of: content, matching: find.byType(AppLogo));
      expect(logo, findsOneWidget, reason: 'AppLogo nicht gefunden');
      final texts = find.descendant(of: content, matching: find.byType(Text));
      final boxes = <Rect>[
        tester.getRect(logo),
        for (final t in tester.widgetList(texts))
          tester.getRect(find.byWidget(t)),
      ];
      var box = boxes.first;
      for (final r in boxes.skip(1)) {
        box = box.expandToInclude(r);
      }
      await writeCardRects(tester, '01_willkommen', {'willkommen_logo': box});
      // Kein eigener Capture: pump() hat den Screenshot unter
      // $outCards/01_willkommen.png bereits geschrieben. Ein zweiter
      // Capture erzeugte nur eine doppelte PNG.
    });

    testWidgets('export Kacheln 04 (drei Auswahlkacheln)', (tester) async {
      // Die drei Widgets werden einzeln in einen Host gehaengt und
      // vermessen. Sie sind ausgelagerte Widgets und in der App noch
      // nicht in einen Screen eingebaut - siehe die Anmerkung in
      // compose_cards() dazu.
      //
      // Adressiert wird ueber den WIDGET-Typ, nicht ueber `Card`: keines
      // der drei baut eine Card. ThemePicker ist ein Wrap, die beiden
      // anderen Column bzw. GridView. Ein `find.byType(Card)` lieferte
      // "No element".
      final cards = <String, Map<String, Object>>{};
      for (final entry in <String, Widget>{
        'anpassen_farbschema': const ThemePicker(
          selectedName: 'classic',
          onChanged: noopTheme,
        ),
        'anpassen_erscheinung': const AppearanceSelector(
          value: 'light',
          onChanged: noop,
        ),
        'anpassen_chat': const ChatBackgroundPicker(),
      }.entries) {
        await pump(
          tester,
          cardHost(entry.value),
          outDir: outCards,
          name: entry.key,
          size: storeV091ShotsPhone,
          dpr: storeV091ShotsDpr,
        );
        final finder = find.byWidget(entry.value);
        expect(
          finder,
          findsOneWidget,
          reason: '${entry.key}: Widget nicht gefunden, Rect waere falsch',
        );
        final r = tester.getRect(finder);
        cards[entry.key] = {
          'file': '${entry.key}.png',
          'rect': [r.left, r.top, r.width, r.height],
        };
      }
      // Einmal am Ende: writeCardRects pro Durchlauf wuerde die Datei
      // bei jedem Widget ueberschreiben und am Ende nur noch das
      // Chat-Hintergrund-Rechteck enthalten.
      await writeCardList(tester, '04_anpassen', cards);
    });

    // 6) Datenschutz. Eigenes Bild statt vierte Kachel in 04: die
    //    Entfernungs-Anzeige ist die inhaltlich wichtigste Aenderung
    //    dieses Releases, und sie verschwindet in einer von vier
    //    gleichwertigen Kacheln neben Farbschema und Chat-Hintergrund.
    //
    //    Rendert `PrivacySection` - dasselbe Widget wie in der App, nicht
    //    ein nachgebautes Layout. Der Screenshot soll etwas zeigen, das
    //    es wirklich gibt.
    testWidgets('export 06_datenschutz Kachel', (tester) async {
      final cards = <String, Map<String, Object>>{};
      const section = PrivacySection(readOnly: true);
      await pump(
        tester,
        cardHost(section),
        outDir: outCards,
        name: '06_datenschutz',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
      );
      final finder = find.byWidget(section);
      expect(
        finder,
        findsOneWidget,
        reason: 'Datenschutz-Abschnitt nicht gefunden, Rect waere falsch',
      );
      final r = tester.getRect(finder);
      cards['datenschutz'] = {
        'file': 'datenschutz.png',
        'rect': [r.left, r.top, r.width, r.height],
      };
      await writeCardList(tester, '06_datenschutz', cards);
    });

    testWidgets('export Kacheln 05 (alle Kategorien)', (tester) async {
      await pump(
        tester,
        const SpiceQuestionsScreen(matchId: 1),
        outDir: outCards,
        name: '05_eisbrecher',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
      );
      // Die Kategorien stehen in einem ListView.builder: gerendert wird
      // nur, was im Viewport liegt. Also wird durch die Liste gelaufen
      // und jede Kachel dann aufgenommen, wenn sie vollstaendig sichtbar
      // ist.
      //
      // Der Name kommt aus dem KACHELTEXT, nicht aus ihrer Position. Mit
      // einem Index als Namen war jede Kategorie nach dem Scrollen eine
      // andere: Index 0 war die erste sichtbare, nicht die erste
      // Kategorie. Die Liste enthielt am Ende acht Kacheln mit den
      // Namen kat_0 bis kat_7 statt der elf Kategorien.
      final list = find.byType(Scrollable).last;
      final cards = <String, Map<String, Object>>{};
      await tester.dragUntilVisible(
        find.byType(ExpansionTile).first,
        list,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();

      for (var step = 0; step < 40; step++) {
        final tiles = find.byType(ExpansionTile);
        final found = tester.widgetList(tiles).length;
        var added = 0;
        for (var i = 0; i < found; i++) {
          final tile = tester.widget<ExpansionTile>(tiles.at(i));
          final name = tileName(tile.title);
          if (name == null || cards.containsKey(name)) continue;
          final r = tester.getRect(tiles.at(i));
          final view = tester.view.physicalSize / tester.view.devicePixelRatio;
          if (r.top < 1 || r.bottom > view.height - 1) continue;
          cards[name] = {
            'file': '05_$step.png',
            'rect': [r.left, r.top, r.width, r.height],
          };
          added++;
        }
        if (added == 0) break; // nichts Neues mehr im Viewport

        await expectLater(
          find.byType(MaterialApp).last,
          matchesGoldenFile('$outCards/05_$step.png'),
        );
        await writeCardList(tester, '05_eisbrecher', cards);

        await tester.drag(list, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
    });
  }

  // 0b) Chat: ersetzt das Anmelde-Bild. Der Chat traegt das staerkste
  //      Versprechen der App und zeigt den Alltag, den die uebrigen
  //      Bilder nicht zeigen - 01 Willkommen, 03 Modi, 04 Personalisierung,
  //      05 Eisbrecher.
  if (enabled) {
    testWidgets('export Kacheln 02 (Chat)', (tester) async {
      await vorbereiteChatSpeicher(tester);

      // Auch im Phone-Ordner: make_store_screenshots.py liest den
      // Store-Screen 02 von dort, nicht aus cards/. Beide Aufrufe
      // nutzen denselben Provider-Override - ohne ihn waere der Screen
      // in einem der beiden Ordner leer.
      await pump(
        tester,
        const ChatDetailScreen(matchId: 'store-shot-match'),
        outDir: '$root/phone',
        name: '02_chat',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
        after: wegtippeVerbindungshinweis,
        extra: [
          chatServiceProvider.overrideWithValue(
            FakeChatService(chatPartner(), chatHistory()),
          ),
        ],
      );
      await pump(
        tester,
        const ChatDetailScreen(matchId: 'store-shot-match'),
        outDir: outCards,
        name: '02_chat',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
        after: wegtippeVerbindungshinweis,
        extra: [
          chatServiceProvider.overrideWithValue(
            FakeChatService(chatPartner(), chatHistory()),
          ),
        ],
      );
      expect(find.byType(ChatDetailScreen), findsOneWidget);
      expect(
        find.text('Mara'),
        findsWidgets,
        reason: 'der Partner-Name fehlt - die Attrappe greift nicht',
      );
    });

    // 2) Aktuelles: die Startseite.
    //
    //    Der Wunsch: "einen neuen Screenshot, wo man die Aktuelles
    //    Seite sieht" - als ZWEITES Bild, direkt nach "Blind Date mit
    //    Substanz". Das Bild zeigt, was man beim Oeffnen der App
    //    wirklich sieht: neue Nachrichten, neue Likes, neue Funken und
    //    das Dock.
    testWidgets('export 02_aktuelles (Startseite)', (tester) async {
      await vorbereiteChatSpeicher(tester);

      await pump(
        tester,
        const HomeScreen(),
        outDir: '$root/phone',
        name: '02_aktuelles',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
        extra: [
          chatServiceProvider.overrideWithValue(
            FakeChatService(chatPartner(), chatHistory()),
          ),
        ],
      );
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  // 1) Willkommen: das Versprechen der App (Persönlichkeit vor Aussehen).
  storeV091ShotsShot('01_willkommen', () => const WelcomeScreen());
  if (enabled) {
    testWidgets('export 03_entdecken Kacheln', (tester) async {
      // Die View bleibt 1080x2400 bei dpr 3, also logisch 360x800 - die
      // Groesse, in der die App die Kachel auf einem Telefon zeigt.
      // Aufloesung kommt nicht ueber eine groessere logische View: dann
      // bricht der Text nicht mehr um, die Kachel wird flacher (88 statt
      // 92 px hoch) und zeigt etwas anderes als die App. Sie kommt
      // ueber den Capture-Finder, siehe unten.
      await pump(
        tester,
        const SwipeModeSelectionScreen(),
        outDir: outTiles,
        name: 'screen',
        size: storeV091ShotsPhone,
        dpr: storeV091ShotsDpr,
      );
      final cards = findModeCards(tester);
      expect(
        cards.length,
        modeOrder.length,
        reason: 'jeder Entdeckungs-Modus muss exportiert werden',
      );

      // WICHTIG: alle Kacheln VOR dem Umbau als Widgets materialisieren.
      // Sobald einmal ein neues Widget gerendert wird, ist der alte
      // Screen weg und die restlichen Finder liefern kein Element mehr
      // ("Bad state: No element").
      final widgets = <Card>[];
      for (final f in cards) {
        widgets.add(tester.element(f).widget as Card);
      }

      for (var i = 0; i < widgets.length; i++) {
        // Jede Kachel einzeln in ein eigenes Scaffold heben und dort als
        // einziges Widget rendern - nur so ist der Export wirklich EINE
        // Kachel. Ein Capture auf find.byKey(card.key!) erfasst auf dem
        // vollstaendigen Screen die ganze Gruppe mit Ueberschrift und
        // Nachbarkacheln.
        //
        // Der Capture laeuft bewusst ueber find.byType(MaterialApp).last und
        // NICHT ueber die Kachel selbst: ein Finder-Capture auf ein
        // einzelnes Widget schreibt LOGISCHE Pixel (312 px breite
        // Kachel in einer 360x800-PNG), der Capture der ganzen View
        // schreibt physische (1080x2400). Genau diese 312 px wurden
        // in compose_modes() auf 830 px hochskaliert - Faktor 2,66,
        // das war die Pixeligkeit in 03_entdecken.
        //
        // Die Datei enthaelt also die ganze View mit Scaffold-Rand um
        // die Kachel. make_store_screenshots.py schneidet sie ueber
        // exaktes Weiss heraus (_crop_tile) und ist damit
        // aufloesungsunabhaengig.
        final card = widgets[i];
        await tester.pumpWidget(soleTileHost(card));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp).last,
          matchesGoldenFile('$outTiles/tile_$i.png'),
        );
      }
    });
  }

  storeV091ShotsShot('03_entdecken', () => const Placeholder());
  storeV091ShotsShot('04_anpassen', () => anpassenScreen('light'));
  shotDark('04_anpassen_dunkel', () => anpassenScreen('dark'));
  storeV091ShotsShot(
    '06_datenschutz',
    () => Scaffold(
      appBar: AppBar(title: Text(storeV091ShotsT('Einstellungen', 'Settings'))),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: PrivacySection(readOnly: true),
      ),
    ),
  );
  storeV091ShotsShot(
    '05_eisbrecher',
    () => const SpiceQuestionsScreen(matchId: 1),
    after: (tester) async {
      final tiles = find.byType(ExpansionTile);
      if (tester.widgetList(tiles).isNotEmpty) {
        await tester.tap(tiles.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
      }
    },
  );
}
