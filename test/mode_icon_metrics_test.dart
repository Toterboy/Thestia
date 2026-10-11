import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/mode_icons.dart';

/// Misst die TINTE der Modesymbole.
///
/// ## Warum hier KEINE Material-Symbole stehen
///
/// Die erste Fassung verglich mit `Icons.event` und `Icons.qr_code_scanner`
/// und kam auf "30.0dp, 56 % Tinte" - fuer sechs voellig verschiedene
/// Glyphen exakt denselben Wert. Kontrollsymbole haben es verraten:
/// `Icons.add` (ein dünnes Plus) und `Icons.close` (ein Kreuz) kamen auf
/// dieselben 30.0dp / 56 %. Das ist nicht die Glyphe, das ist ein
/// Ersatzkästchen: in `flutter_test` steht die echte Material-Schrift
/// nicht zur Verfuegung, `Icon` rendert also nicht die Glyphe.
///
/// Ein Vergleich gegen Material ist hier also NICHT moeglich. Die
/// Eigenzeichen sind Vektoren und werden echt gezeichnet, ihre Zahlen
/// stimmen - der Anker fuer die Groesse ist deshalb die Augenmaessung
/// auf dem Geraet, nicht diese Datei.
///
/// Als Gitter hilft der Umriss-Vergleich: Material-Symbole sind Umrisse
/// mit viel Weiss darin. Ein gefuellter Block gleicher Ausdehnung wiegt
/// optisch schwerer und sieht groesser aus.
///
///   flutter test test/mode_icon_metrics_test.dart
void main() {
  const size = 40.0;
  const zeile = 60;
  const zeileDp = 60.0;

  testWidgets('Tintenausdehnung messen', (tester) async {
    final kandidaten = <String, Widget>{
      'EIGEN find': ModeSymbol((x) => FindSparkPainter(x),
          size: size, color: const Color(0xFF000000)),
      'EIGEN transit': ModeSymbol((x) => TransitSparkPainter(x),
          size: size, color: const Color(0xFF000000)),
      'EIGEN zufall': ModeSymbol((x) => QuestionChatPainter(x),
          size: size, color: const Color(0xFF000000)),
    };

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        // KEIN Hintergrund: gemessen wird der Alphakanal. Ein weisses
        // Rect haette dort ueber Alpha 255 und die Tinte wuerde die
        // ganze Flaeche fuellen.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in kandidaten.entries)
              SizedBox(
                height: zeileDp,
                child: Center(child: e.value),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final randung =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    expect(randung, isNotNull);

    late Uint8List px;
    late int w, h;
    await tester.runAsync(() async {
      final b = await randung!.toImage(pixelRatio: 1.0);
      final daten = await b.toByteData(format: ui.ImageByteFormat.rawRgba);
      px = daten!.buffer.asUint8List();
      w = b.width;
      h = b.height;
    });

    debugPrint('=== TINTE je Kandidat (Box ${w}x$h, Zeile $zeile dp) ===');
    for (var i = 0; i < kandidaten.length; i++) {
      final y0 = i * zeile, y1 = y0 + zeile;
      var minX = w, maxX = -1, tinte = 0;
      var minY = 1 << 30, maxY = -1;
      for (var y = y0; y < y1 && y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = (y * w + x) * 4;
          if (px[p + 3] < 8) continue;
          // Schwarz auf transparent: weiche Raender haben geringe
          // Deckkraft UND niedrige Farbkanaele - beides pruefen, sonst
          // zaehlt der Anti-Aliasing-Rand als volle Tinte.
          if (px[p] > 120 || px[p + 1] > 120 || px[p + 2] > 120) continue;
          tinte++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y - y0 < minY) minY = y - y0;
          if (y - y0 > maxY) maxY = y - y0;
        }
      }
      final name = kandidaten.keys.elementAt(i).padRight(24);
      if (maxX < 0) {
        debugPrint('$name KEINE TINTE');
        continue;
      }
      final bw = (maxX - minX + 1).toDouble();
      final bh = (maxY - minY + 1).toDouble();
      debugPrint('$name '
          'b ${bw.toStringAsFixed(1).padLeft(5)}dp  '
          'h ${bh.toStringAsFixed(1).padLeft(5)}dp  '
          'mitte ${((minX + maxX) / 2).toStringAsFixed(1).padLeft(5)}  '
          'tinte ${(tinte / (bw * bh) * 100).toStringAsFixed(0).padLeft(3)}%  '
          'diag ${math.sqrt(bw * bw + bh * bh).toStringAsFixed(1)}');
    }
  });
}