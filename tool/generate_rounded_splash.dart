import 'dart:io';

import 'package:image/image.dart' as img;

Future<void> main() async {
  const sourcePath = 'assets/images/thestia_icon_base.png';
  const roundedForegroundPath = 'assets/images/thestia_icon_rounded_foreground.png';
  const roundedBackgroundPath = 'assets/images/thestia_icon_rounded_background.png';

  final sourceBytes = File(sourcePath).readAsBytesSync();
  final source = img.decodePng(sourceBytes);
  if (source == null) {
    throw Exception('Could not decode $sourcePath');
  }

  final size = source.width < source.height ? source.width : source.height;
  final sizeD = size.toDouble();
  final radiusD = sizeD / 6; // soft rounding

  final foreground = img.Image(width: size, height: size);
  final background = img.Image(width: size, height: size);

  for (final pixel in foreground) {
    final x = pixel.x.toDouble();
    final y = pixel.y.toDouble();
    final inside = _isInsideRoundedRect(x, y, sizeD, radiusD);
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
    final x = pixel.x.toDouble();
    final y = pixel.y.toDouble();
    final inside = _isInsideRoundedRect(x, y, sizeD, radiusD);
    if (inside) {
      pixel.r = 255;
      pixel.g = 255;
      pixel.b = 255;
      pixel.a = 255;
    } else {
      pixel.a = 0;
    }
  }

  File(roundedForegroundPath).writeAsBytesSync(img.encodePng(foreground));
  File(roundedBackgroundPath).writeAsBytesSync(img.encodePng(background));
}

bool _isInsideRoundedRect(double x, double y, double size, double radius) {
  // Check if point is in the main rectangular area (ignoring corners)
  final inMainRect = x >= radius &&
      x <= size - radius &&
      y >= radius &&
      y <= size - radius;

  if (inMainRect) return true;

  // Check if point is in any of the four edge strips (excluding corners)
  if (y >= radius && y <= size - radius) {
    if (x < radius || x > size - radius) return true;
  }
  if (x >= radius && x <= size - radius) {
    if (y < radius || y > size - radius) return true;
  }

  // Check corner quarter-circles
  final corners = [
    _CornerRegion(radius, radius, radius),
    _CornerRegion(size - radius, radius, radius),
    _CornerRegion(radius, size - radius, radius),
    _CornerRegion(size - radius, size - radius, radius),
  ];

  for (final corner in corners) {
    final dx = x - corner.cx;
    final dy = y - corner.cy;
    final distSquared = dx * dx + dy * dy;
    if (distSquared <= radius * radius) {
      return true;
    }
  }

  return false;
}

class _CornerRegion {
  final double cx;
  final double cy;
  final double radius;
  const _CornerRegion(this.cx, this.cy, this.radius);
}
