// tool/generate_notification_icon.dart
//
// Erzeugt das Android-Benachrichtigungs-Icon als sauber gezeichnete
// Herz-Silhouette (weiss auf transparent, 96x96).
//
// Android verlangt fuer Statusleisten-Icons eine alpha-maskierte,
// einfarbige Form - das alte Icon war eine automatisch abgeleitete
// Logo-Silhouette (inkl. Schriftzug-Resten). Das neue Herz ist eine
// parametrische Kurve (16*sin^3, 13*cos - 5*cos2 - 2*cos3 - cos4),
// symmetrisch, mit ruhigen Rundungen und gleichmaessigem Padding.
//
// Output: android/app/src/main/res/drawable/notification_icon.png
//
// Ausfuehren: dart run tool/generate_notification_icon.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  const size = 96;
  // Herz-Breite ~60 px, zentriert mit ~18 px Padding ringsum.
  const heartWidth = 60.0;
  const cx = size / 2.0;
  const cy = size / 2.0 + 2.0;
  // Klassische Herz-Kurve: x in [-16, 16], y in ca. [-17, 12].
  const scale = heartWidth / 32.0;

  final canvas = img.Image(width: size, height: size, numChannels: 4);

  // Polygon aus der Kurve abtasten (720 Punkte = glatte Raender).
  final points = <img.Point>[];
  for (var i = 0; i < 720; i++) {
    final t = i / 720 * 2 * math.pi;
    final x = 16 * math.pow(math.sin(t), 3);
    final y = 13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    points.add(img.Point(
      (cx + x * scale).round(),
      (cy - y * scale).round(),
    ));
  }
  img.fillPolygon(
    canvas,
    vertices: points,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  const outDir = 'android/app/src/main/res/drawable';
  Directory(outDir).createSync(recursive: true);
  final out = File('$outDir/notification_icon.png');
  out.writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Geschrieben: $out (${size}x$size)');
}
