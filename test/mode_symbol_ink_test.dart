import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/mode_icons.dart';

/// Misst die TINTE der Mode-Symbole im 24er-Viewport.
///
/// Warum es das gibt: der Transit-Spark-Icon besteht aus einer
/// Material-Glyphe (Zug) und selbst gezeichneten Elementen (Funke). Die
/// Glyphe hat Seitenzungen, ihre Tinte liegt NICHT mittig auf dem
/// uebergebenen Mittelpunkt. Raten fuehrt zu Ueberlagerungen - genau
/// daran ist der urspruengliche Entwurf gescheitert (der Funke zog
/// durch den Zug).
///
/// Deshalb wird hier gemessen statt gerechnet: gerendert wird in
/// bekannter Groesse, dann wird die Tinte gescannt und in
/// Viewport-Einheiten (24 = ganze Breite) zurueckgerechnet.
///
/// Nur von Hand zu starten:
///   flutter test test/mode_symbol_ink_test.dart
void main() {
  testWidgets('Tinten-Boxen messen', (tester) async {
    final out = Directory(r'C:\Users\Thoralf\AppData\Local\Temp\opencode'
        r'\m133\symbole');
    try {
      if (!out.existsSync()) out.createSync(recursive: true);
    } catch (_) {
      return;
    }

    const k = 400.0; // Renderkante in Pixeln
    final faelle = <String, CustomPainter Function(Color)>{
      'transit_spark': (c) => TransitSparkPainter(c),
      'find_spark': (c) => FindSparkPainter(c),
      'zufallschat': (c) => QuestionChatPainter(c),
    };

    for (final eintrag in faelle.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          // RepaintBoundary INNERHALB des Center: der Center gibt dem
          // Kind lockere Constraints, das SizedBox bleibt also exakt
          // 400x400 und die Randung erfasst genau den Icon-Bereich.
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFF000000),
              width: k,
              height: k,
              child: CustomPaint(painter: eintrag.value(const Color(0xFFFFFFFF))),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final randung = key.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (randung == null) return;
        final bild = await randung.toImage();
        final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
        if (daten == null) return;

        // PNG-Rohdaten lesen ist unpraktisch - deshalb als Bild
        // dekodieren und die Pixel scannen.
        final dec = await ui.instantiateImageCodec(daten.buffer.asUint8List());
        final frame = await dec.getNextFrame();
        final bild2 = frame.image;
        final byteData = await bild2.toByteData();
        if (byteData == null) return;

        int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
        for (int y = 0; y < bild2.height; y++) {
          for (int x = 0; x < bild2.width; x++) {
            final o = (y * bild2.width + x) * 4;
            final r = byteData.getUint8(o);
            final g = byteData.getUint8(o + 1);
            final b = byteData.getUint8(o + 2);
            // Weisse Tinte auf schwarzem Grund
            if (r > 140 && g > 140 && b > 140) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
        if (maxX < 0) return;

        // In Viewport-Einheiten: das Bild ist genau der Icon-Bereich
        // (400x400 = 24 Einheiten), also gilt px / 400 * 24.
        double u(double px) => px / k * 24.0;

        // Spaltenprofil: verraet, wo ein breiter Block (der Zug) beginnt
        // und wo ein schmaler Streifen (der Funke) laeuft. Aus dem
        // Profil laesst sich der Abstand zwischen beiden exakt ablesen.
        final profil = <String>[];
        for (int x = 0; x < bild2.width; x += 4) {
          int treffer = 0;
          for (int y = 0; y < bild2.height; y++) {
            final o = (y * bild2.width + x) * 4;
            if (byteData.getUint8(o) > 140 &&
                byteData.getUint8(o + 1) > 140 &&
                byteData.getUint8(o + 2) > 140) {
              treffer++;
            }
          }
          profil.add('${u(x.toDouble()).toStringAsFixed(1)}:'
              '${'#' * (treffer ~/ 4)}');
        }
        debugPrint('PROFIL ${eintrag.key}\n  ${profil.join(" ")}');

        debugPrint('${eintrag.key}: Tinte x=${u(minX.toDouble()).toStringAsFixed(2)}..'
            '${u(maxX.toDouble()).toStringAsFixed(2)}  '
            'y=${u(minY.toDouble()).toStringAsFixed(2)}..'
            '${u(maxY.toDouble()).toStringAsFixed(2)}');
      });
      await tester.pumpAndSettle();
    }
  });
}
