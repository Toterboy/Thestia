import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Erzeugt das runde Thestia-Logo aus dem Basis-Icon
/// (`assets/images/thestia_icon_base.png`, EINZIGE Logo-Quelle):
///
///  1. `thestia_logo_round.png`      – rundes App-Logo (Launcher,
///     pubspec/flutter_launcher_icons). Zoom basiert auf dem größten
///     um den Mittelpunkt liegenden opaken Kreis des Artworks: keine
///     transparenten Ecken, aber minimal möglicher Zuschnitt, damit
///     der Schriftzug vollständig lesbar bleibt.
///  2. `thestia_logo_round_dark.png` – Hintergrund ~12 % abgedunkelt.
///
/// Splash-/Foreground-/Notification-Assets werden aus derselben Quelle
/// von `tool/generate_branding.dart` erzeugt.
///
/// Aufruf: dart run tool/generate_round_logo.dart
void main(List<String> args) {
  const sourcePath = 'assets/images/thestia_icon_base.png';
  final src = img.decodePng(File(sourcePath).readAsBytesSync());
  if (src == null) throw Exception('$sourcePath konnte nicht gelesen werden');

  // Bounding-Box der opaken Pixel (PNG hat einen transparenten Rand).
  var minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (final p in src) {
    if (p.a.toInt() > 20) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  final bw = maxX - minX + 1;
  final bh = maxY - minY + 1;
  final bboxSide = math.max(bw, bh);

  // Auf Quadrat bringen: transparente Ränder/Ecken werden mit den
  // NAECHSTEN opaken Randpixeln gefuellt (Kanten-Extension). Der Farb-
  // verlauf laeuft damit nahtlos weiter -> kein transparentes Eckblitzen,
  // und der Schriftzug bleibt vollstaendig im Kreis sichtbar (Zoom 1.0).
  final square = img.Image(width: bboxSide, height: bboxSide);
  final padX = (bboxSide - bw) ~/ 2;
  final padY = (bboxSide - bh) ~/ 2;
  for (final p in square) {
    final sx = (minX + (p.x - padX).clamp(0, bw - 1)).clamp(0, src.width - 1);
    final sy = (minY + (p.y - padY).clamp(0, bh - 1)).clamp(0, src.height - 1);
    final s = src.getPixel(sx, sy);
    p.setRgba(s.r, s.g, s.b, s.a);
  }

  // Zweiter Durchlauf: verbliebene transparente Pixel (die abgerundeten
  // Ecken) aus der naechsten opaken Pixel derselben Zeile fuellen. Der
  // horizontale Farbverlauf bleibt so erhalten und es gibt keine
  // transparenten Ecken mehr -> Zoom 1.0, Schriftzug vollstaendig.
  for (var y = 0; y < bboxSide; y++) {
    for (var x = 0; x < bboxSide; x++) {
      if (square.getPixel(x, y).a.toInt() >= 200) continue;
      img.Pixel? fill;
      for (var d = 1; d < bboxSide && fill == null; d++) {
        final xl = x - d;
        if (xl >= 0 && square.getPixel(xl, y).a.toInt() >= 200) {
          fill = square.getPixel(xl, y);
          break;
        }
        final xr = x + d;
        if (xr < bboxSide && square.getPixel(xr, y).a.toInt() >= 200) {
          fill = square.getPixel(xr, y);
        }
      }
      if (fill != null) {
        square.getPixel(x, y).setRgba(
              fill.r.toInt(),
              fill.g.toInt(),
              fill.b.toInt(),
              255,
            );
      }
    }
  }

  // ---- 1+2) Rundes Logo -------------------------------------------------
  const outSize = 1024;
  final outRadius = outSize / 2.0 - 0.5;

  // Größter zentrierter Kreis, der NUR opake Pixel enthält (respektiert
  // die abgerundeten Ecken). Daraus folgt der minimale Zoom: keine
  // transparenten Ecken, aber minimaler Zuschnitt -> Schriftzug bleibt
  // vollständig lesbar.
  // (Diagnose-Wert, falls doch Lücken blieben:)
  var minInscribed = bboxSide / 2.0;
  const steps = 1440;
  for (var a = 0; a < steps; a++) {
    final theta = 2 * math.pi * a / steps;
    final dx = math.cos(theta);
    final dy = math.sin(theta);
    var d = 0.0;
    while (d < bboxSide / 2.0) {
      final x = (bboxSide / 2.0 + dx * d).round();
      final y = (bboxSide / 2.0 + dy * d).round();
      if (x < 0 || y < 0 || x >= bboxSide || y >= bboxSide) break;
      if (square.getPixel(x, y).a.toInt() < 200) break;
      d++;
    }
    if (d < minInscribed) minInscribed = d;
  }
  // Zoom 1.0: Der quadratische Kachel ist kantenverlaengert (opak), der
  // Ausgabe-Kreis samplet am Rand einfach die fortgesetzten Kantenfarben.
  // Damit ist der Schriftzug vollstaendig sichtbar und es gibt keinerlei
  // transparente Ecken.
  const zoom = 1.0;

  final scaledSide = (outSize * zoom).round();
  final scaled = img.copyResize(
    square,
    width: scaledSide,
    height: scaledSide,
    interpolation: img.Interpolation.cubic,
  );
  final inset = (scaledSide - outSize) ~/ 2;
  final round = img.Image(width: outSize, height: outSize);

  for (final p in round) {
    final dx = p.x + 0.5 - outSize / 2;
    final dy = p.y + 0.5 - outSize / 2;
    if (dx * dx + dy * dy <= outRadius * outRadius) {
      final s = scaled.getPixel(
        (p.x + inset).clamp(0, scaledSide - 1),
        (p.y + inset).clamp(0, scaledSide - 1),
      );
      p.setRgba(s.r, s.g, s.b, s.a);
    }
  }

  // Weiche Kante (1.5 px Alpha-Falloff).
  for (final p in round) {
    if (p.a == 0) continue;
    final dx = p.x + 0.5 - outSize / 2;
    final dy = p.y + 0.5 - outSize / 2;
    final edge = outRadius - math.sqrt(dx * dx + dy * dy);
    if (edge < 1.5) {
      p.a = (p.a * (edge.clamp(0.0, 1.5) / 1.5)).round().clamp(0, 255);
    }
  }

  File('assets/images/thestia_logo_round.png')
      .writeAsBytesSync(img.encodePng(round));

  // Dark: Hintergrund-Motive ~12 % abgedunkelt; nahe-weiße Design-Elemente
  // (Schriftzug/Herz) bleiben weiß.
  final dark = img.Image.from(round);
  for (final p in dark) {
    if (p.a == 0) continue;
    final isNearWhite = p.r > 235 && p.g > 235 && p.b > 235;
    if (!isNearWhite) {
      p.setRgba(
        (p.r * 0.88).round(),
        (p.g * 0.88).round(),
        (p.b * 0.88).round(),
        p.a,
      );
    }
  }
  File('assets/images/thestia_logo_round_dark.png')
      .writeAsBytesSync(img.encodePng(dark));

  stdout.writeln('Rundes Logo erzeugt: ${round.width}px '
      '(Quelle: thestia_icon_base.png), zoom=${zoom.toStringAsFixed(3)}');
}
