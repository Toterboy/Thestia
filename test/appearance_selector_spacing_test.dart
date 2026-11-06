// Regressionstest fuer die GLEICHEN Abstaende in der
// Erscheinungs-Auswahl (NUTZERWUNSCH 31.10.2026).
//
// "Die Abstaende bei Einstellungen Erscheinung sollen gleich links und
// rechts sein."
//
// Vorher waren die drei Segmente unterschiedlich breit: "Hell" war
// schmaler als "System" und "Dunkel", weil der Kasten nur eine
// Mindestbreite hatte und der Text den Rest bestimmte. Die Folge:
// links war kein Abstand, rechts ein grosser.
//
// Der Test vergleicht die drei Segmentbreiten MITTEINANDER (nicht mit
// dem Rand) - so ist er unabhaengig von der Fensterbreite und vom
// Text. Zusaetzlich wird der Abstand zwischen den Segmenten geprueft:
// er muss ueberall derselbe sein.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/widgets/appearance_selector.dart';

Widget _host(String value, {double breite = 400}) {
  return MaterialApp(
    theme: AppTheme.light(theme: ThestiaTheme.classic),
    locale: const Locale('de'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: breite,
          child: AppearanceSelector(value: value, onChanged: (_) {}),
        ),
      ),
    ),
  );
}

/// Das Rechteck des Segments (der Kasten mit dem sichtbaren Rahmen).
Rect _segmentRect(WidgetTester tester, String text) {
  final box = find.ancestor(
    of: find.text(text),
    matching: find.byType(AnimatedContainer),
  );
  expect(box, findsWidgets, reason: 'Segment "$text" nicht gefunden.');
  return tester.getRect(box.first);
}

void main() {
  const namen = ['Hell', 'System', 'Dunkel'];

  testWidgets('Die drei Segmente sind gleich breit', (tester) async {
    await tester.pumpWidget(_host('light'));
    await tester.pumpAndSettle();

    final breiten = [for (final n in namen) _segmentRect(tester, n).width];

    for (var i = 0; i < namen.length; i++) {
      expect(
        (breiten[i] - breiten.first).abs(),
        lessThanOrEqualTo(0.5),
        reason:
            '"${namen[i]}" ist ${breiten[i].toStringAsFixed(1)} px breit, '
            '"${namen.first}" ist ${breiten.first.toStringAsFixed(1)} px. '
            'Die Segmente muessen gleich breit sein - sonst ist der '
            'Abstand links nicht derselbe wie rechts.',
      );
    }
  });

  testWidgets('Der Abstand zwischen den Segmenten ist ueberall gleich', (
    tester,
  ) async {
    await tester.pumpWidget(_host('light'));
    await tester.pumpAndSettle();

    final rects = [for (final n in namen) _segmentRect(tester, n)];
    // Zwei Abstaende: zwischen Segment 1 und 2, zwischen 2 und 3.
    final abstaende = [
      rects[1].left - rects[0].right,
      rects[2].left - rects[1].right,
    ];

    expect(
      (abstaende[1] - abstaende[0]).abs(),
      lessThanOrEqualTo(0.5),
      reason:
          'Die Abstaende unterscheiden sich um '
          '${(abstaende[1] - abstaende[0]).toStringAsFixed(1)} px '
          '(${abstaende.map((a) => a.toStringAsFixed(1)).join(" und ")}). '
          'Sie muessen gleich sein.',
    );
  });

  testWidgets('Die Zeile endet genauso weit rechts wie sie links beginnt', (
    tester,
  ) async {
    // Der Nutzerwunsch war "gleich links und rechts": der Abstand
    // zwischen dem Rand des Containers und dem ersten Segment muss
    // gleich sein wie der zwischen dem letzten Segment und dem Rand.
    //
    // Gemessen wird ueber die KANTEN der drei Kacheln: die erste
    // beginnt bei x1, die letzte endet bei x2. Der Container ist
    // 400 px breit (das SizedBox im Test) und liegt mittig im
    // Fenster - die Kacheln muessen ihn also genau ausfuellen.
    //
    // Der Weg ueber die Kachelkanten statt ueber den Container:
    // der Container ist ein Widget im Baum, die Kachelkanten sind
    // Pixel - und die sind das, was der Nutzer sieht.
    await tester.pumpWidget(_host('light'));
    await tester.pumpAndSettle();

    final rects = [for (final n in namen) _segmentRect(tester, n)]
      ..sort((a, b) => a.left.compareTo(b.left));

    // Der Selector liegt in einem SizedBox von 400 px, mittig im
    // Fenster (800 px im Test). Also beginnt er bei (800-400)/2.
    final containerLinks = (800 - 400) / 2;

    final links = rects.first.left - containerLinks;
    final rechts = (containerLinks + 400) - rects.last.right;

    expect(
      (links - rechts).abs(),
      lessThanOrEqualTo(0.5),
      reason:
          'Links sind es ${links.toStringAsFixed(1)} px, rechts '
          '${rechts.toStringAsFixed(1)} px. Beide muessen gleich sein.',
    );
  });

  testWidgets('Die Breite ist bei jedem Wert dieselbe', (tester) async {
    // Beim Wechsel des Modus darf sich die Zeile nicht verschieben -
    // sonst springt die Auswahl unter dem Finger weg.
    //
    // Der Wert haengt vom Text ab ("System" ist breiter als "Hell"),
    // der ist aber hier fuer alle drei dieselbe. Geprueft wird, dass
    // sich die Breite beim Wechsel NICHT aendert.
    final breiten = <double>[];
    for (final wert in ['light', 'system', 'dark']) {
      await tester.pumpWidget(_host(wert));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      breiten.add(_segmentRect(tester, 'Hell').width);
    }
    for (final b in breiten) {
      expect(
        (b - breiten.first).abs(),
        lessThanOrEqualTo(0.5),
        reason:
            'Die Segmentbreite springt beim Wechsel des Modus: '
            '${breiten.map((x) => x.toStringAsFixed(1)).join(", ")} px.',
      );
    }
  });
}
