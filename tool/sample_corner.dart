// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

/// Findet die Bounding-Box der opaken Pixel und samplet deren Randfarbe.
void main() {
  final im = img.decodePng(
      File('assets/images/thestia_icon_base.png').readAsBytesSync())!;
  var minX = im.width, minY = im.height, maxX = 0, maxY = 0;
  for (final p in im) {
    if (p.a.toInt() > 20) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  print('BoundingBox: x=$minX..$maxX y=$minY..$maxY '
      '(${maxX - minX + 1}x${maxY - minY + 1}) von ${im.width}x${im.height}');

  final bw = maxX - minX + 1;
  final bh = maxY - minY + 1;
  const inset = 10;
  var r = 0, g = 0, b = 0, n = 0;
  void add(int x, int y) {
    final p = im.getPixel(minX + x, minY + y);
    if (p.a.toInt() < 200) return;
    r += p.r.toInt();
    g += p.g.toInt();
    b += p.b.toInt();
    n++;
  }

  for (var x = inset; x < bw - inset; x += 4) {
    add(x, inset);
    add(x, bh - inset);
  }
  for (var y = inset; y < bh - inset; y += 4) {
    add(inset, y);
    add(bw - inset, y);
  }
  if (n == 0) {
    print('Keine opaken Randpixel in der BoundingBox.');
    return;
  }
  final avg = ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  print('Randpixel: $n');
  print('adaptive_icon_background: #${avg.toRadixString(16).padLeft(6, '0').toUpperCase()}');
}
