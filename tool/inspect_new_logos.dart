// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

/// Inspeziert die neuen Logo-Dateien: Groesse, Transparenz, Form.
void main(List<String> args) {
  final dir = r'C:\Users\Thoralf\Downloads\Blind-Date-App Repository';
  final files = [
    'thestia_icon_base.png',
    'thestia_icon_base neu.png',
    'thestia_icon_base-small.png',
    'thestia_notification.png',
    'thestia_benachrichtigungsicon neu.png',
  ];
  for (final name in files) {
    final f = File('$dir\\$name');
    if (!f.existsSync()) {
      print('$name: FEHLT');
      continue;
    }
    final im = img.decodePng(f.readAsBytesSync());
    if (im == null) {
      print('$name: decode-Fehler');
      continue;
    }
    var transparent = 0, opaque = 0, white = 0, total = 0;
    var minX = im.width, minY = im.height, maxX = 0, maxY = 0;
    for (final p in im) {
      total++;
      if (p.a.toInt() < 10) {
        transparent++;
        continue;
      }
      opaque++;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.r > 230 && p.g > 230 && p.b > 230) white++;
    }
    final bboxW = maxX - minX + 1;
    final bboxH = maxY - minY + 1;
    final isCircleLike = opaque > 0 &&
        (bboxW / im.width) > 0.8 &&
        (bboxH / im.height) > 0.8 &&
        transparent > 0;
    print('$name: ${im.width}x${im.height} transparent='
        '${(transparent * 100 / total).toStringAsFixed(0)}% weiss='
        '${(white * 100 / total).toStringAsFixed(0)}% bbox=${bboxW}x$bboxH'
        '${isCircleLike ? " [rund]" : ""}');
  }
}
