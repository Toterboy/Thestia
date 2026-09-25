import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

Future<void> main() async {
  const sourcePath = 'assets/images/thestia_icon_base.png';
  const hexForegroundPath = 'assets/images/thestia_icon_hex_foreground.png';
  const hexBackgroundPath = 'assets/images/thestia_icon_hex_background.png';

  final sourceBytes = File(sourcePath).readAsBytesSync();
  final source = img.decodePng(sourceBytes);
  if (source == null) {
    throw Exception('Could not decode $sourcePath');
  }

  final size = source.width < source.height ? source.width : source.height;
  final hexRadius = size / 2;
  final hexCenter = Offset(size / 2, size / 2);

  final hexPoints = _hexagonPoints(hexCenter, hexRadius);

  final foreground = img.Image(width: size, height: size);
  final background = img.Image(width: size, height: size);

  for (final pixel in foreground) {
    final point = Offset(pixel.x.toDouble(), pixel.y.toDouble());
    final inside = _isInsidePolygon(point, hexPoints);
    if (inside && pixel.x < source.width && pixel.y < source.height) {
      final srcPixel = source.getPixel(pixel.x, pixel.y);
      pixel.r = srcPixel.r;
      pixel.g = srcPixel.g;
      pixel.b = srcPixel.b;
      pixel.a = srcPixel.a;
    } else {
      pixel.a = 0;
    }
  }

  for (final pixel in background) {
    final point = Offset(pixel.x.toDouble(), pixel.y.toDouble());
    final inside = _isInsidePolygon(point, hexPoints);
    if (inside) {
      pixel.r = 255;
      pixel.g = 255;
      pixel.b = 255;
      pixel.a = 255;
    } else {
      pixel.a = 0;
    }
  }

  final foregroundPng = img.encodePng(foreground);
  final backgroundPng = img.encodePng(background);

  File(hexForegroundPath).writeAsBytesSync(foregroundPng);
  File(hexBackgroundPath).writeAsBytesSync(backgroundPng);
}

List<Offset> _hexagonPoints(Offset center, double radius) {
  return List.generate(6, (index) {
    final angle = (index * 60 - 90) * pi / 180;
    return Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
  });
}

bool _isInsidePolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].dx, yi = polygon[i].dy;
    final xj = polygon[j].dx, yj = polygon[j].dy;

    final intersect = ((yi > point.dy) != (yj > point.dy)) &&
        (point.dx < (xj - xi) * (point.dy - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
}
