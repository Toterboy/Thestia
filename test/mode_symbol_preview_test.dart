import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/mode_icons.dart';

/// Vorab-Rendering der drei neuen Mode-Symbole, nur von Hand zu starten:
///   flutter test test/mode_symbol_preview_test.dart
///
/// ACHTUNG: Dieser Test ist ein WERKZEUG, kein Guard. Er schreibt PNGs
/// nach C:/Users/.../AppData/Local/Temp/opencode/m133/, damit die Symbole
/// angesehen werden koennen, ohne die App auf einem Geraet zu oeffnen.
/// Ohne diese Datei kann niemand die Symbole begutachten, und ein
/// CustomPainter, den niemand gesehen hat, ist geraten statt gezeichnet.
void main() {
  testWidgets('Symbol-Preview schreiben', (tester) async {
    // Nur wenn der Ablageort benutzbar ist. Ein fester Windows-Pfad wuerde
    // auf einer Linux-Pipeline (F-Droid-CI) das ganze Testlauf abbrechen -
    // und ein Preview istoptional, ein gruener Lauf ist es nicht.
    final out = Directory(r'C:\Users\Thoralf\AppData\Local\Temp\opencode'
        r'\m133\symbole');
    try {
      if (!out.existsSync()) out.createSync(recursive: true);
    } catch (_) {
      debugPrint('Preview-Ablageort nicht nutzbar - uebersprungen.');
      return;
    }
    if (!out.existsSync()) return;

    final faelle = <String, Widget Function(Color)>{
      'transit_spark': (c) => CustomPaint(
          painter: TransitSparkPainter(c), size: const Size(120, 120)),
      'find_spark': (c) => CustomPaint(
          painter: FindSparkPainter(c), size: const Size(120, 120)),
      'zufallschat': (c) => CustomPaint(
          painter: QuestionChatPainter(c), size: const Size(120, 120)),
    };

    // Farben wie in der Kachel: ausgewählt (auf Primärfläche) und nicht
    // ausgewählt (auf surfaceContainerHighest).
    for (final variant in ['gewaehlt', 'ruhig']) {
      final farbe = variant == 'gewaehlt'
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF49454F);
      final flaeche = variant == 'gewaehlt'
          ? const Color(0xFF6750A4)
          : const Color(0xFFE7E0EC);
      for (final eintrag in faelle.entries) {
        final datei = File('${out.path}/${eintrag.key}_$variant.png');
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Container(
              color: flaeche,
              padding: const EdgeInsets.all(40),
              child: eintrag.value(farbe),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final randung = key.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          if (randung == null) {
            debugPrint('KEINE RANDUNG fuer ${eintrag.key}');
            return;
          }
          final bild = await randung.toImage();
          final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
          if (daten == null) {
            debugPrint('KEINE DATEN fuer ${eintrag.key}');
            return;
          }
          await datei.writeAsBytes(daten.buffer.asUint8List());
          debugPrint('geschrieben: ${datei.path}');
        });
        await tester.pumpAndSettle();
      }
    }
  });
}
