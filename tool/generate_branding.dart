import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Erzeugt die Android-Branding-Assets aus dem Thestia-Basis-Icon
/// (`assets/images/thestia_icon_base.png`, EINZIGE Logo-Quelle):
///
///  1. `thestia_icon_foreground.png` – Adaptive-Icon-Foreground (Safe-Zone).
///  2. `drawable/notification_icon.png` – 96 px, weiß + Alpha (Android-
///     Statusleiste): helle Elemente des Logos werden weiß, der Rest
///     transparent. Fällt auf eine volle Kreissilhouette zurück, wenn zu
///     wenige helle Pixel gefunden werden.
///
/// (Der native Splash wird separat von `tool/generate_splash_images.dart`
/// + `flutter_native_splash:create` erzeugt - ebenfalls aus dem Basis-Icon.)
///
/// Aufruf: dart run tool/generate_branding.dart
void main() {
  const roundPath = 'assets/images/thestia_icon_base.png';
  final src = img.decodePng(File(roundPath).readAsBytesSync());
  if (src == null) throw Exception('$roundPath konnte nicht gelesen werden');

  // ---- 1) Adaptive-Icon-Foreground (Safe-Zone ~66 %) --------------------
  const fgSize = 1024;
  final fgContent = (fgSize * 0.66).round();
  final fgScaled = img.copyResize(
    src,
    width: fgContent,
    height: fgContent,
    interpolation: img.Interpolation.cubic,
  );
  final fg = img.Image(width: fgSize, height: fgSize, numChannels: 4);
  final fgOff = (fgSize - fgContent) ~/ 2;
  for (final p in fgScaled) {
    fg.setPixel(p.x + fgOff, p.y + fgOff, p);
  }
  File('assets/images/thestia_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(fg));

  // ---- 2) Notification-Icon (weiß + Alpha, 96 px, HERZ) ------------------
  // Android zeigt das Small Icon als weiße Silhouette in der Statusleiste.
  // Die frühere Luminanz-Extraktion aus dem Logo lieferte nur ~308 weiße
  // Pixel (praktisch LEER / wirkte als weißes Viereck). Jetzt: eine klare,
  // sofort erkennbare HERZ-Silhouette (Dating!) - zusätzlich kreisförmig
  // auf die Sichtrunde begrenzt.
  const nSize = 96;
  // WICHTIG: numChannels: 4 (RGBA)! Der Default (3 = RGB) verwirft Alpha
  // STILL - das Icon war dann ein volles 96x96 weisses Quadrat und
  // erschien in der Statusleiste als weisses VIERECK (User-Bericht).
  final n = img.Image(width: nSize, height: nSize, numChannels: 4);

  // Parametrische Herz-Kurve als Kontur-Punkte (ray-casting Füllung).
  final heart = <List<double>>[];
  for (var i = 0; i <= 120; i++) {
    final t = 2 * math.pi * i / 120;
    final x = 16 * math.pow(math.sin(t), 3).toDouble();
    final y = 13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    heart.add([nSize / 2 + x * 2.4, nSize / 2 - y * 2.4 + 4]);
  }

  bool insideHeart(double px, double py) {
    var inside = false;
    for (var i = 0, j = heart.length - 1; i < heart.length; j = i++) {
      final xi = heart[i][0], yi = heart[i][1];
      final xj = heart[j][0], yj = heart[j][1];
      if (((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  var whitePixels = 0;
  for (final p in n) {
    final inHeart = insideHeart(p.x + 0.5, p.y + 0.5);
    if (!inHeart) continue;
    // Leichte Kanten-Aufhellung: volle Deckkraft im Kern.
    p.setRgba(255, 255, 255, 255);
    whitePixels++;
  }

  // Kreismaske: Alles außerhalb der Sichtrunde transparent (weiche Kante).
  for (final p in n) {
    final dx = p.x + 0.5 - nSize / 2;
    final dy = p.y + 0.5 - nSize / 2;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > nSize / 2 - 1) {
      p.a = 0;
    } else if (dist > nSize / 2 - 3) {
      final fade = ((nSize / 2 - 1 - dist) / 2).clamp(0.0, 1.0);
      p.a = (p.a * fade).round().clamp(0, 255);
    }
  }
  File('android/app/src/main/res/drawable/notification_icon.png')
      .writeAsBytesSync(img.encodePng(n));

  stdout.writeln('Branding erzeugt (Quelle: thestia_icon_base.png): '
      'Adaptive-Foreground, Notification-Icon (weiss=$whitePixels px)');
}
