// Regressionstest fuer die Zentrierung in AppearanceSelector.
//
// Nutzerbefund: "Bei Erscheinung ist der Text bei System und Dunkel nicht
// richtig mittig." Ursache war ein SizedBox(width: 16), der in ALLEN
// Segmenten als Platz fuer den Auswahl-Haken stand. Bei "Hell" faellt das
// nicht auf, weil der Haken den Platz fuellt - "System" und "Dunkel" hadten
// dadurch einen um 6 px nach links verschobenen Text.
//
// Der Test vergleicht die Textmitte mit der Iconmitte. Das Icon ist genau
// mittig in seinem Segment (Column mit crossAxisAlignment.center), taugt
// also als Bezugspunkt - anders als ein gemessener Abstand zum Nachbarn,
// der von der Segmentbreite abhaengt.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/widgets/appearance_selector.dart';

Widget _host(String value) {
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
          width: 400,
          child: AppearanceSelector(value: value, onChanged: (_) {}),
        ),
      ),
    ),
  );
}

double _center(WidgetTester tester, Finder f) =>
    tester.getRect(f).center.dx;

void main() {
  // Suche nach den drei Segment-Beschriftungen anhand ihrer Texte.
  Finder caption(String s) => find.text(s, skipOffstage: false);

  testWidgets('Beschriftung sitzt mittig ueber dem Symbol', (tester) async {
    await tester.pumpWidget(_host('light'));
    await tester.pumpAndSettle();

    // Die Symbole sind die drei Icons der Auswahl. Sie liegen im
    // selben Column wie die Beschriftung und sind zentriert.
    for (final entry in {
      'Hell': Icons.light_mode_outlined,
      'System': Icons.brightness_auto_outlined,
      'Dunkel': Icons.dark_mode_outlined,
    }.entries) {
      final icon = find.byIcon(entry.value);
      final text = caption(entry.key);
      expect(icon, findsOneWidget, reason: 'Symbol ${entry.key} fehlt');
      expect(text, findsOneWidget, reason: 'Text ${entry.key} fehlt');

      final iconCenter = _center(tester, icon);
      final textCenter = _center(tester, text);
      // 0,5 px Toleranz: getRect liefert halbe Pixel, und ein
      // gerundeter Rahmen kann die Box um einen halben Pixel verschieben.
      expect(
        (textCenter - iconCenter).abs(),
        lessThanOrEqualTo(0.5),
        reason: 'Text "${entry.key}" ist um '
            '${(textCenter - iconCenter).toStringAsFixed(1)} px aus der '
            'Mitte - er muesste mittig ueber dem Symbol stehen',
      );
    }
  });

  testWidgets('Segmentbreite springt beim Wechsel nicht', (tester) async {
    // Der alte Aufbau reservierte 16 px in allen Segmenten, damit die
    // Zeile nicht springt. Mit dem Overlay-Haken ist dieser Platz
    // ueberfluessig.
    //
    // Ganz genau 0 ist die Differenz trotzdem nicht: das aktive Segment
    // hat einen 2 px starken Rahmen, die anderen 1 px. Der Rahmen geht
    // in die Breite ein, das Segment wächst also um 2 px. Das ist der
    // Rest des Springens, das bleibt - sichtbar ist es nicht.
    //
    // Vorher waeren es 16 px plus diese 2 px gewesen.
    double widthOf(String text) => tester
        .getRect(find.ancestor(of: caption(text),
            matching: find.byType(AnimatedContainer)))
        .width;

    await tester.pumpWidget(_host('light'));
    await tester.pumpAndSettle();
    final hell = widthOf('Hell');
    final system = widthOf('System');
    final dunkel = widthOf('Dunkel');

    await tester.pumpWidget(_host('dark'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final hell2 = widthOf('Hell');
    final system2 = widthOf('System');
    final dunkel2 = widthOf('Dunkel');

    const borderStep = 3.0;
    for (final e in <String, (double, double)>{
      'Hell': (hell, hell2),
      'System': (system, system2),
      'Dunkel': (dunkel, dunkel2),
    }.entries) {
      expect(
        (e.value.$2 - e.value.$1).abs(),
        lessThanOrEqualTo(borderStep),
        reason: '${e.key} aendert seine Breite um '
            '${(e.value.$2 - e.value.$1).toStringAsFixed(1)} px beim Wechsel '
            '- erlaubt ist nur der Rahmenwechsel (2 px). Ein Sprung von 16 px '
            'wuerde bedeuten, dass der Haken wieder am Text klebt.',
      );
    }
  });

// ---------------------------------------------------------------------------
// Zweiter Befund, eigene Ursache.
// ---------------------------------------------------------------------------
// Der erste Test verglich Textmitte gegen ICONmitte. Beide lagen
// korrekt uebereinander - nur an der FALSCHEN Stelle: beide waren im
// Segment nach links verschoben.
//
// Ursache: ein Stack richtet sein nicht positioniertes Kind standard-
// maessig oben links aus. Die Column ist schmal, der Kasten ist durch
// die Mindestbreite (92 px) breiter. Bei "Hell" ist der Unterschied am
// groessten.
//
// Dieser Test misst deshalb gegen die Segmentkante, nicht gegen das
// Symbol: genau die Groesse, die ein Nutzer als "nicht mittig" sieht.
testWidgets('Symbol und Beschriftung sitzen mittig IM Segment',
    (tester) async {
  await tester.pumpWidget(_host('light'));
  await tester.pumpAndSettle();

  for (final entry in {
    'Hell': Icons.light_mode_outlined,
    'System': Icons.brightness_auto_outlined,
    'Dunkel': Icons.dark_mode_outlined,
  }.entries) {
    final icon = find.byIcon(entry.value);
    final text = caption(entry.key);

    // Das Segment ist der Vorfahr mit dem AnimatedContainer. Gesucht
    // wird der naechste Container, der breiter ist als der Inhalt -
    // das ist genau der, der den sichtbaren Rahmen zeichnet.
    final box = find.ancestor(
      of: icon,
      matching: find.byType(AnimatedContainer),
    );
    expect(box, findsWidgets, reason: 'Segment-Rahmen fuer ${entry.key} fehlt');

    final ink = tester.getRect(box.first);
    final iconRect = tester.getRect(icon);

    // 1 px Toleranz: halbe Pixel und Rundung im Text-Layout.
    expect(
      (iconRect.center.dx - ink.center.dx).abs(),
      lessThanOrEqualTo(1.0),
      reason: 'Symbol "${entry.key}" ist um '
          '${(iconRect.center.dx - ink.center.dx).toStringAsFixed(1)} px '
          'aus der Segmentmitte verschoben.',
    );
    expect(
      (_center(tester, text) - ink.center.dx).abs(),
      lessThanOrEqualTo(1.0),
      reason: 'Text "${entry.key}" ist nicht mittig im Segment.',
    );
  }
});
}
