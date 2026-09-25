// tool/generate_icons.dart
//
// Erzeugt die Icon-Quell-Assets aus dem Thestia-Basis-Logo
// (assets/images/thestia_icon_base.png, 941x941, Verlaufshintergrund
// mit weissem Artwork):
//
//  1) thestia_icon_foreground.png  (1024x1024, transparent)
//     - Weiss-Keying (min-Kanal >= 215): weisses Artwork (Figuren, Herz,
//       Sparkles, Schrift) wird Badge auf Transparenz.
//     - Badge auf 66 % der Safe-Zone skaliert (wie bisher: Kreis/Squircle).
//  2) thestia_icon_ios.png         (1024x1024, opak)
//     - Basisbild auf eigenem Kanten-Verlauf zentriert (96 %), Ecken damit
//       nahtlos; Apple maskt selbst.
//  3) build/icon_previews/preview_*.png - Masken-Simulation + PASS/FAIL.
//
// Ausfuehren: dart run tool/generate_icons.dart
// Danach:     dart run flutter_launcher_icons

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const String _sourcePath = 'assets/images/thestia_icon_base.png';
const String _foregroundPath = 'assets/images/thestia_icon_foreground.png';
const String _iosPath = 'assets/images/thestia_icon_ios.png';
// (Konstanten zu Keying-Verfahren stehen bei den jeweiligen Abschnitten.)

void main() {
  final srcBytes = File(_sourcePath).readAsBytesSync();
  final src = img.decodePng(srcBytes);
  if (src == null) {
    stderr.writeln('Basis-Logo konnte nicht dekodiert werden: $_sourcePath');
    exit(1);
  }
  final w = src.width;
  final h = src.height;
  stdout.writeln('Basis: ${w}x$h');

  // --- 1. Artwork-Bounding-Box (Saettigungs-Key) -----------------------------
  // Verlaufshintergrund ist stark gesaettigt, Artwork schwach. Die Box
  // begrenzt nur den Ausschnitt - der Hintergrund AUSSERHALB wird
  // verworfen, der Rest weich in den Adaptive-Hintergrund geblendet.
  bool artPixel(int x, int y) {
    final p = src.getPixel(x, y);
    if (p.a < 128) return false;
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final mx = math.max(r, math.max(g, b));
    if (mx <= 0) return false;
    final mn = math.min(r, math.min(g, b));
    return (mx - mn) / mx <= 0.55;
  }

  var minX = w, minY = h, maxX = -1, maxY = -1;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!artPixel(x, y)) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) {
    stderr.writeln('Kein Badge gefunden.');
    exit(1);
  }
  stdout.writeln('Badge-BBox: x=$minX..$maxX, y=$minY..$maxY');

  // --- 2. Crop mit weicher Kante in Adaptive-Hintergrund --------------------
  // Das Artwork (inkl. eigenem Verlauf + Herz-Body) wird VOLLSTAENDIG
  // uebernommen und an den Crop-Raendern ueber ~28 px in das
  // Adaptive-Hintergrund-Pink (#390D3C) geblendet - keine Loecher,
  // keine harten Rechteck-Kanten.
  const bgR = 0x39, bgG = 0x0D, bgB = 0x3C;
  const pad = 4;
  const feather = 28;
  final cx0 = math.max(0, minX - pad);
  final cy0 = math.max(0, minY - pad);
  final cx1 = math.min(w - 1, maxX + pad);
  final cy1 = math.min(h - 1, maxY + pad);
  final cw = cx1 - cx0 + 1;
  final ch = cy1 - cy0 + 1;
  final side = math.max(cw, ch);
  final crop = img.Image(width: side, height: side, numChannels: 4);
  final dx = (side - cw) ~/ 2;
  final dy = (side - ch) ~/ 2;
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final edgeDist = math.min(math.min(x, y), math.min(cw - 1 - x, ch - 1 - y));
      var a = edgeDist / feather;
      if (a > 1.0) a = 1.0;
      final sp = src.getPixel(x + cx0, y + cy0);
      final r = (sp.r * a + bgR * (1 - a)).round();
      final g = (sp.g * a + bgG * (1 - a)).round();
      final b = (sp.b * a + bgB * (1 - a)).round();
      crop.setPixelRgba(dx + x, dy + y, r, g, b, 255);
    }
  }
  // Padding-Bereich ausserhalb des Crops: reines Hintergrund-Pink.
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final inCrop = x >= dx &&
          x < dx + cw &&
          y >= dy &&
          y < dy + ch;
      if (!inCrop) crop.setPixelRgba(x, y, bgR, bgG, bgB, 255);
    }
  }

  // --- 3. Foreground 1024 (Badge 66 %) ------------------------------------
  img.Image scaledCanvas(img.Image source, int size, double scale) {
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    final target = (size * scale).round();
    final resized = img.copyResize(source,
        width: target, height: target, interpolation: img.Interpolation.cubic);
    final off = (size - target) ~/ 2;
    img.compositeImage(canvas, resized, dstX: off, dstY: off);
    return canvas;
  }

  final foreground = scaledCanvas(crop, 1024, 0.66);
  File(_foregroundPath).writeAsBytesSync(img.encodePng(foreground));
  stdout.writeln('OK: $_foregroundPath');

  // --- 4. iOS-Master: Kanten-Verlauf + Basis 96 % --------------------------
  img.Pixel edgeSample(int y) {
    for (var yy = y; yy >= 0 && yy < h; yy += (y < h ~/ 2 ? 1 : -1)) {
      final p = src.getPixel(w ~/ 2, yy);
      if (p.a >= 128) return p;
    }
    return src.getPixel(w ~/ 2, h ~/ 2);
  }

  final top = edgeSample(2);
  final bottom = edgeSample(h - 3);
  final ios = img.Image(width: 1024, height: 1024, numChannels: 4);
  for (var y = 0; y < 1024; y++) {
    final t = y / 1023.0;
    final r = (top.r + (bottom.r - top.r) * t).round();
    final g = (top.g + (bottom.g - top.g) * t).round();
    final b = (top.b + (bottom.b - top.b) * t).round();
    for (var x = 0; x < 1024; x++) {
      ios.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  final baseResized = img.copyResize(src,
      width: 983, height: 983, interpolation: img.Interpolation.cubic);
  img.compositeImage(ios, baseResized, dstX: (1024 - 983) ~/ 2, dstY: (1024 - 983) ~/ 2);
  File(_iosPath).writeAsBytesSync(img.encodePng(ios));
  stdout.writeln('OK: $_iosPath');

  // --- 5. Masken-Simulation (rund/squircle, 512) ---------------------------
  Directory('build/icon_previews').createSync(recursive: true);
  var failed = false;
  final masks = <String, int>{
    'preview_circle.png': 2,
    'preview_squircle.png': 4,
  };
  for (final name in masks.keys) {
    final power = masks[name]!;
    const size = 512;
    final preview = img.copyResize(foreground,
        width: size, height: size, interpolation: img.Interpolation.cubic);
    // Auf Weiss kompositen (Launcher-Hintergrund hell) zur Sichtpruefung.
    final flat = img.Image(width: size, height: size, numChannels: 4);
    img.fill(flat, color: img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(flat, preview);
    var outside = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final rx = (x + 0.5 - size / 2).abs() / (size / 2);
        final ry = (y + 0.5 - size / 2).abs() / (size / 2);
        final inside = math.pow(rx, power) + math.pow(ry, power) <= 1.0;
        if (!inside) {
          // Pruefung auf dem Foreground (mit Transparenz), Deko auf Weiss.
          final fp = preview.getPixel(x, y);
          final m = math.min(fp.r, math.min(fp.g, fp.b));
          if (fp.a >= 128 && m >= 235) outside++;
          flat.setPixelRgba(x, y, 200, 200, 200, 255);
        }
      }
    }
    File('build/icon_previews/$name').writeAsBytesSync(img.encodePng(flat));
    if (outside == 0) {
      stdout.writeln('PASS  $name');
    } else {
      stdout.writeln('FAIL  $name: $outside Badge-Pixel ausserhalb!');
      failed = true;
    }
  }
  if (failed) exit(1);
  stdout.writeln('Fertig. Danach: dart run flutter_launcher_icons');
}
