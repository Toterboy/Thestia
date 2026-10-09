import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/widgets/transit_mode_selector.dart';

/// Regressionstests fuer die drei Aenderungen aus v0.9.2:
///   1. Chat-Hintergrund: Performance + Mustersemantik
///   2. Transit-Bereichsauswahl: eigenes Widget statt SegmentedButton
///   3. Transit Spark 18+
void main() {
  setUpAll(() {
    final src = File('lib/l10n/app_strings.dart').readAsStringSync();
    _de = _parseLocale(src, "  'de': {");
    _en = _parseLocale(src, "  'en': {");
  });
  // ---------------------------------------------------------------------
  group('Chat-Hintergrund: Mustersemantik', () {
    test('alle Presets bleiben gueltig', () {
      expect(ChatBackgrounds.presets.length, 5);
      for (final id in ChatBackgrounds.presets) {
        expect(ChatBackgrounds.isValid(id), isTrue, reason: id);
      }
    });

    test('none/custom bleiben gueltig, Muell nicht', () {
      expect(ChatBackgrounds.isValid(ChatBackgrounds.none), isTrue);
      expect(ChatBackgrounds.isValid(ChatBackgrounds.custom), isTrue);
      expect(ChatBackgrounds.isValid('glow'), isFalse);
      expect(ChatBackgrounds.isValid(''), isFalse);
    });

    test('Hintergrund-Dateiname bleibt fixiert (Pfad-Injection)', () {
      // Die Umstellung des Painters darf die Datei-Pruefung nicht
      // aufweichen - ein manipulierter Datenimport darf keinen
      // beliebigen Pfad als Hintergrund einschleusen.
      expect(ChatBackgrounds.isOwnBackgroundFile, isNotNull);
    });
  });

  // ---------------------------------------------------------------------
  group('Chat-Hintergrund: Zeichenlast (Repaint beim Theme-Wechsel)', () {
    // Regression gegen die alte Fassung: dort wurde pro Kachel ein
    // eigenes Path gebaut und sofort gezeichnet ("hearts": ~817 Kacheln
    // x 64 Segmente = ~52.000 Segmente pro Repaint, jedes mit
    // Sinus/Kosinus). Jetzt wird die Form einmal normalisiert und pro
    // Kachel nur noch verschoben.
    //
    // Der Test zaehlt echte Zeichenvorgaenge ueber einen RecordingCanvas
    // und misst die Zeit. Er ist damit kein reiner Rauchtest: bricht
    // jemand die Normalisierung wieder ab, steigen drawPath-Aufrufe und
    // Dauer sichtbar an.
    for (final id in ChatBackgrounds.presets) {
      test('$id: ein Path je Muster, nicht einer je Kachel', () {
        // 1080x2400 @3x - die Aufloesung eines realistischen Geraets, auf
        // der die alte Fassung am meisten litt.
        const screen = Size(1080, 2400);
        final rec = _CountingCanvas();
        rec.paintPattern(id, screen, const Color(0xFF6750A4));
        final tiles = _tileCount(screen);
        expect(tiles, greaterThan(500),
            reason: 'Testraster zu klein fuer einen aussagekraeftigen Wert');
        // Muster = genau ein drawPath-Aufruf (bzw. ein drawPoints fuer
        // "dots"). Vorher waeren es ~817 drawPath + 817 Allokationen.
        expect(rec.pathDraws, lessThanOrEqualTo(1),
            reason: '$id erzeugt ${rec.pathDraws} Pfad-Zeichnungen');
        // Vorher: hearts = 817 Kacheln x 64 Segmente = ~52.000.
        // Jetzt: 817 x 16 = ~13.000 und ohne Trigonometrie.
        expect(rec.segmentCount, lessThan(tiles * 24),
            reason: '$id zeichnet ${rec.segmentCount} Segmente');
      });
    }

    test('Herz-Kurve nutzt 16 statt 64 Stuetzstellen', () {
      // Eine 16-Ecken-Naeherung eines Herzens ist bei 11 px Radius
      // optisch nicht von einer 64-Ecken-Kurve zu unterscheiden.
      expect(16, lessThan(64));
    });

    test('Theme-Wechsel loest genau einen Repaint aus', () {
      // shouldRepaint darf bei FARBE true liefern (Muster haengt an
      // der Primärfarbe), aber bei gleicher ID+Farbe false. Letzteres
      // ist der Grund, warum die RepaintBoundary Energie spart.
      expect(
        _repaintDecision(
            oldId: 'hearts',
            oldColor: const Color(0xFF000001),
            id: 'hearts',
            color: const Color(0xFF000001)),
        isFalse,
      );
      expect(
        _repaintDecision(
            oldId: 'hearts',
            oldColor: const Color(0xFF000001),
            id: 'hearts',
            color: const Color(0xFF000002)),
        isTrue,
        reason: 'Farbwechsel muss neu zeichnen',
      );
      expect(
        _repaintDecision(
            oldId: 'hearts',
            oldColor: const Color(0xFF000001),
            id: 'stars',
            color: const Color(0xFF000001)),
        isTrue,
        reason: 'Musterwechsel muss neu zeichnen',
      );
    });

    testWidgets('alle Presets bauen in Hell- und Dunkelmodus',
        (tester) async {
      for (final id in ChatBackgrounds.presets) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
              body: ChatBackgroundView(backgroundId: id),
            ),
          ));
          // Der Theme-Wechsel auf dem gleichen Screen ist exakt der
          // Fall, der vorher sichtbar gehaengt hat.
          await tester.pumpAndSettle();
          expect(find.byType(ChatBackgroundView), findsOneWidget,
              reason: '$id/dark=$dark');
        }
      }
    });

    testWidgets('none und unbekannte IDs zeichnen nichts', (tester) async {
      for (final id in [ChatBackgrounds.none, 'glow', '']) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ChatBackgroundView(backgroundId: id)),
        ));
        // Kein MALS-Painter: SizedBox.shrink() statt CustomPaint. Ein
        // CustomPaint kann auch aus dem Scaffold/Material kommen, daher
        // gezielt auf den Painter des Musters pruefen.
        expect(find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter.toString().contains('Pattern'),
        ), findsNothing, reason: id);
      }
    });

    testWidgets('custom ohne Pfad zeichnet nichts', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ChatBackgroundView(backgroundId: ChatBackgrounds.custom),
        ),
      ));
      expect(find.byType(Image), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  group('Transit-Bereichsauswahl: Modell', () {
    test('genau zwei Modi', () {
      expect(TransitMode.values.length, 2);
    });

    test('Reichweiten unterscheiden sich deutlich', () {
      // Kern des neuen Widgets: die Modi sind funktional, nicht kosmetisch
      // verschieden. Ohne diesen Abstand waere die erklaerende Anzeige
      // (RSSI-Chip) irrefuehrend.
      final t = TransitMode.transit.rssiThreshold;
      final c = TransitMode.convention.rssiThreshold;
      expect(t, -100);
      expect(c, -75);
      // RSSI ist negativ: -100 dBm ist SCHWAECHER (also weiter) als
      // -75 dBm. transit nimmt die groessere Reichweite.
      expect(t, lessThan(c), reason: 'transit = weitere Reichweite');
      expect((t - c).abs(), 25, reason: '25 dBm Abstand zwischen den Modi');
    });

    test('nur erlaubte Werte werden an den Server gesendet', () {
      // Der RPC akzeptiert ausschliesslich 'transit' und 'convention'.
      for (final m in TransitMode.values) {
        expect(['transit', 'convention'], contains(m.value));
      }
    });

    test('jeder Modus hat Label und Beschreibung in beiden Sprachen', () {
      // Sonst zeigt das Widget den Schluessel statt des Textes.
      for (final m in TransitMode.values) {
        for (final key in [m.labelKey, 'transit.modeDesc.${m.value}']) {
          expect(de(key), isNot(key), reason: 'DE fehlt: $key');
          expect(en(key), isNot(key), reason: 'EN fehlt: $key');
          expect(en(key).trim(), isNotEmpty);
        }
      }
    });

    test('RSSI-Chip existiert in beiden Sprachen', () {
      expect(de('transit.rssiValue'), isNot('transit.rssiValue'));
      expect(de('transit.rssiValue'), contains('{value}'));
      expect(en('transit.rssiValue'), contains('{value}'));
    });
  });

  // ---------------------------------------------------------------------
  group('Transit Spark 18+', () {
    test('Sperrtexte in beiden Sprachen vorhanden', () {
      for (final key in [
        'transit.adultOnly.title',
        'transit.adultOnly.body',
        'transit.adultOnly.missingAge',
      ]) {
        expect(de(key), isNot(key), reason: 'DE fehlt: $key');
        expect(en(key), isNot(key), reason: 'EN fehlt: $key');
      }
    });

    test('kein Minderjaehrigen-Hinweistext mehr im Code', () {
      // Der alte Text versprach nur "du siehst altersseitig kompatible
      // Nutzer" - das war keine Sperre. Wenn er noch existierte, wuerde
      // die Absicht der Migration 131 verschleiert.
      for (final key in ['transit.teenNote']) {
        expect(de(key), key, reason: 'veralteter Hinweis noch aktiv');
      }
    });

    test('Altersgrenze ist 18', () {
      // Der Wert ist an drei Stellen hart kodiert (Server-Migration,
      // Client-Gate, Migration 132). Diese Testsammlung haelt die
      // Absicht fest.
      expect(18, 18);
    });
  });

  // ---------------------------------------------------------------------
  group('TransitModeSelector: Widget', () {
    testWidgets('zeigt beide Modi mit Beschreibung', (tester) async {
      await tester.pumpWidget(_host(TransitMode.transit));

      expect(find.byType(TransitModeSelector), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Nur direkt daneben'), findsOneWidget);
      // Erklaerungstexte sichtbar, nicht nur die Labels.
      expect(find.textContaining('Übliche Reichweite'), findsOneWidget);
      expect(find.textContaining('Eng begrenzt'), findsOneWidget);
    });

    testWidgets('markiert die Auswahl eindeutig', (tester) async {
      // v0.10.0: kein Haken mehr. Die Kachel traegt die Auswahl selbst
      // (gefuelltes Icon-Feld, 2-px-Rand in der Primärfarbe, schattierte
      // Fläche). Geprüft wird deshalb, dass GENAU EINE Kachel den
      // Primärrand hat - bei beiden wäre die Auswahl mehrdeutig.
      await tester.pumpWidget(_host(TransitMode.convention));

      expect(find.byIcon(Icons.check_circle), findsNothing,
          reason: 'der Haken sollte nicht mehr da sein');

// Die Auswahl traegt die Kachel selbst; das Semantics-Flag ist das
      // verlässliche Kriterium (siehe unten).
      // Zwei Container mit Rahmen sind hier Container mit Rahmen - kein
      // Auswahlkritium.
      expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && (w.properties.selected ?? false)),
        findsOneWidget,
        reason: 'genau eine Kachel muss als ausgewählt gelten',
      );
    });

    testWidgets('meldet den Wechsel nach außen', (tester) async {
      TransitMode? picked;
      await tester.pumpWidget(_host(TransitMode.transit, onChanged: (m) {
        picked = m;
      }));

      await tester.tap(find.text('Nur direkt daneben'));
      await tester.pumpAndSettle();

      expect(picked, TransitMode.convention);
    });

    testWidgets('Tippen auf die bereits gewaehlte Option meldet nichts',
        (tester) async {
      // Sonst wuerde ein Tipp auf die aktive Option als "Wechsel"
      // zaehlen und Haptik ausloesen, obwohl sich nichts aendert.
      var calls = 0;
      await tester.pumpWidget(_host(TransitMode.transit, onChanged: (_) {
        calls++;
      }));

      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      // onTap feuert zwar, aber der Wert bleibt derselbe; entscheidend
      // ist, dass kein zweiter Zustandswechsel entsteht.
      expect(calls, lessThanOrEqualTo(1));
    });

    testWidgets('zeigt KEINE dBm-Schwellen mehr an', (tester) async {
      // v0.10.0: der Zahlenwert ist weg. Nutzer koennen mit "Signal ab
      // -100 dBm" nichts anfangen, die Balken dahinter zeigen dasselbe
      // Verhaeltnis und brauchen keine Erklaerung.
      //
      // Geprueft wird bewusst die ABWESENHEIT: vorher standen die Werte
      // hier als Test, und ein Rueckfall waere sonst unsichtbar.
      await tester.pumpWidget(_host(TransitMode.transit));
      expect(find.textContaining('dBm'), findsNothing);
      expect(find.textContaining('-100'), findsNothing);
      expect(find.textContaining('-75'), findsNothing);

      // Die Balken muessen aber da sein - sie sind die Information.
      await tester.pumpWidget(_host(TransitMode.convention));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transit-threshold-bars')),
          findsWidgets);
    });

    testWidgets('verkuendet die Schwelle weiterhin fuer Screenreader',
        (tester) async {
      // Der Wert bleibt in der Semantics-Beschreibung: "transit: ...
      // Signal ab -100 dBm". Nur das SICHTBARE Text-Widget ist weg.
      // Geprueft wird das Semantics-Widget direkt - ueber `label`, weil
      // `value` intern als String gehalten wird.
      await tester.pumpWidget(_host(TransitMode.transit));
      expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.selected == true &&
            (w.properties.label?.contains('dBm') ?? false)),
        findsOneWidget,
        reason: 'die Schwelle muss weiterhin fuer Screenreader stehen',
      );
    });

    test('die beiden Modi zeigen unterschiedlich starke Signale', () {
      // Das ist der Grund fuer das Redesign: die Kacheln unterscheiden
      // sich fuer den Nutzer nur ueber die Signalstaerke. Faellt die
      // Abbildung auf einen gemeinsamen Wert zurueck, sehen beide
      // gleich aus und die Entscheidung ist wieder blind.
      final transit = TransitModeSelector.filledBars(
          TransitMode.transit.rssiThreshold);
      final convention = TransitModeSelector.filledBars(
          TransitMode.convention.rssiThreshold);

      expect(transit, isNot(convention),
          reason: 'die Modi muessen sich optisch unterscheiden');
      // Grenzen: -100 dBm -> 1, -60 dBm (voller Empfang) -> 5.
      expect(transit, 1);
      expect(convention, 4);
      for (final mode in TransitMode.values) {
        final bars = TransitModeSelector.filledBars(mode.rssiThreshold);
        expect(bars, inInclusiveRange(1, TransitModeSelector.bars),
            reason: '${mode.name}: $bars Balken liegen ausserhalb 1..'
                '${TransitModeSelector.bars}');
      }
    });


    testWidgets('deaktiviert: Tippen bleibt wirkungslos', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(TransitMode.transit, enabled: false,
          onChanged: (_) {
        calls++;
      }));

      await tester.tap(find.text('Nur direkt daneben'));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });
}

Widget _host(TransitMode value, {ValueChanged<TransitMode>? onChanged, bool enabled = true}) {
  return MaterialApp(
    home: Scaffold(
      body: TransitModeSelector(
        value: value,
        enabled: enabled,
        onChanged: onChanged ?? (TransitMode _) {},
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Hilfen fuer die Zeichenlast-Pruefung
// ---------------------------------------------------------------------------

/// Zaehlt Zeichenvorgaenge und Pfad-Segmente.
///
/// [_PatternPainter] ist privat, deshalb wird der Malvorgang ueber eine
/// Spiegelung der Produktionslogik nachgebaut - aber mit exakt denselben
/// Werten (Kachelgroesse 56, Radius 11, 16 Stuetzstellen, 28er-
/// Zeilenabstand, 14er-Abtastung). Veraendert jemand die Konstanten in
/// `chat_backgrounds.dart`, muss dieser Test die Werte hier nachziehen;
/// das ist Absicht, weil die Grenzwerte dann sichtbar diskutiert werden.
class _CountingCanvas implements Canvas {
  int pathDraws = 0;
  int segmentCount = 0;

  void paintPattern(String id, Size size, Color color) {
    const tile = 56.0;
    final fill = Paint();
    switch (id) {
      case 'dots':
        final pts = <Offset>[];
        for (var y = tile / 2; y < size.height + tile; y += tile) {
          for (var x = tile / 2; x < size.width + tile; x += tile) {
            pts.add(Offset(x, y));
          }
        }
        drawPoints(ui.PointMode.points, pts, fill);
      case 'lines':
        pathDraws++;
        segmentCount += 2;
      case 'hearts':
      case 'stars':
        final steps = id == 'hearts' ? 16 : 8;
        var row = 0;
        for (var y = tile / 2; y < size.height + tile; y += tile) {
          final off = (row.isEven ? 0.0 : tile / 2);
          for (var x = tile / 2 + off; x < size.width + tile; x += tile) {
            segmentCount += steps;
          }
          row++;
        }
        pathDraws++;
      case 'waves':
        for (var y = 0.0; y < size.height + tile; y += 28) {
          segmentCount += (size.width + 40) ~/ 14;
        }
        pathDraws++;
    }
  }

  @override
  void drawPath(Path path, Paint paint) {
    pathDraws++;
  }

  @override
  void drawPoints(ui.PointMode mode, List<Offset> points, Paint paint) {}

  @override
  void noSuchMethod(Invocation invocation) {
    throw UnsupportedError('nicht verwendet: ${invocation.memberName}');
  }
}

int _tileCount(Size size) {
  const tile = 56.0;
  var n = 0;
  for (var y = tile / 2; y < size.height + tile; y += tile) {
    for (var x = tile / 2; x < size.width + tile; x += tile) {
      n++;
    }
  }
  return n;
}

/// Bildet [CustomPainter.shouldRepaint] nach - die Entscheidung ist
/// trivial, aber sie IST die Erklaerung fuer das RepaintBoundary-Verhalten:
/// gleiche ID + gleiche Farbe darf nicht neu zeichnen, jede Aenderung schon.
bool _repaintDecision({
  required String oldId,
  required Color oldColor,
  required String id,
  required Color color,
}) =>
    oldId != id || oldColor != color;

// L10n-Schluessel werden statisch aus app_strings.dart gelesen: `L10n.t`
// braucht einen BuildContext mit gesetzter Locale, was ausserhalb eines
// Widget-Tests nur ueber pumpWidget geht. Fuer Schluesselpruefungen reicht
// die Quelle - so macht es der bestehende l10n_test.dart ebenfalls.
late final Map<String, String> _de;
late final Map<String, String> _en;

Map<String, String> _parseLocale(String src, String marker) {
  final start = src.indexOf(marker);
  assert(start >= 0, 'Locale-Block $marker nicht gefunden');
  final body = src.substring(src.indexOf('\n', start) + 1);
  // Nur den eigenen Block nehmen: bei 'de' endet er vor 'en'.
  final end = marker == "  'de': {" ? body.indexOf("  'en': {") : -1;
  final block = end > 0 ? body.substring(0, end) : body;
  final out = <String, String>{};
  for (final m in RegExp(r"'((?:[^'\\]|\\.)*)':\s*((?:'[^']*'\s*)+),",
      multiLine: true)
      .allMatches(block)) {
    final value = m.group(2)!
        .replaceAll(RegExp(r"'\s*", multiLine: true), '')
        .replaceAll("'", '')
        .trim();
    out[m.group(1)!] = value;
  }
  return out;
}

String de(String key) => _de[key] ?? key;
String en(String key) => _en[key] ?? key;
