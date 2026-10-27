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
// Optional:   dart run tool/generate_notification_icon.dart <zielBreitePx>
//             (nur zum Vergleich der Varianten, Standard ist 88)

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main(List<String> args) {
  const size = 96;

  // ZIEL-BREITE des Herzens in Pixeln (96x96-Leinwand).
  //
  // WARUM (NUTZERWUNSCH 24.10.2026): "Das Herz Icon, was in der
  // Statusleiste bei Benachrichtigungen aufploppt, ist etwas kleiner als
  // andere Symbole. Bitte gleiche es an."
  //
  // Die Ursache: Das Herz belegte nur 60 von 96 px, also 62 % der
  // Leinwand. Android skaliert das Drawable auf 24 dp und maskiert es
  // dann mit der Systemform. Ein Icon, das nur 62 % fuellt, erscheint
  // deshalb sichtbar kleiner als die System-Icone daneben (Batterie,
  // WLAN, Signal) - die sind fast randlos.
  //
  // Ein Material-Heart (Icons.favorite) fuellt 20 x 18 von 24 dp, also
  // 83 % x 75 %. Unser Ziel liegt bewusst etwas darueber, damit das
  // Herz in der Statusleiste nicht als "klein" auffaellt.
  //
  // Die Breite wird vorgegeben, die Hoehe folgt aus dem Seitenverhaelt-
  // nis der Kurve - das Herz bleibt dadurch unverzerrt. 84 px Breite
  // ergeben rund 76 px Hoehe (79 % der Leinwand).
  //
  // Warum 84 und nicht 96: Manche Geraete legen eine runde oder
  // abgerundete Systemmaske ueber das Statusleisten-Icon. Bei 96 px
  // Breite ragten die oberen Lappen aus der Kreisform heraus und
  // wuerden angeschnitten. 84 px lassen 6 px Rand - das Herz ist damit
  // immer noch 88 % so breit wie vorher (60 px) und deutlich groesser
  // als die System-Icone daneben.
  final zielBreite =
      args.isNotEmpty ? double.tryParse(args.first) ?? 84.0 : 84.0;

  // 4-fach ueberabtastet und danach heruntergerechnet: nur so bekommt
  // die Silhouette saubere, weiche Kanten. Ohne das hat das Icon
  // sichtbare Treppenstufen, wenn Android es auf 24 dp verkleinert.
  const ueberabtastung = 4;
  const leinwand = size * ueberabtastung;

  // --- Kurve abtasten -------------------------------------------------
  //
  // Die klassische Herz-Kurve:
  //   x(t) = 16 sin^3 t
  //   y(t) = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t
  //
  // In mathematischer Orientierung (y nach oben) liegt die Spitze des
  // Herzens UNTEN bei y = -17 (t = pi) und die beiden Lappen oben
  // (Scheitel bei y = +11,6). Die Kerbe zwischen den Lappen ist der
  // Punkt (0, 5) bei t = 0.
  //
  // Fuer den Bildschirm (y nach unten) wird deshalb umgekehrt.
  const punkteAnzahl = 1440;
  final kurve = <List<double>>[];
  var xMin = double.infinity, xMax = -double.infinity;
  var yMin = double.infinity, yMax = -double.infinity;
  for (var i = 0; i < punkteAnzahl; i++) {
    final t = i / punkteAnzahl * 2 * math.pi;
    final x = 16 * math.pow(math.sin(t), 3).toDouble();
    final y = 13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    kurve.add([x, y]);
    if (x < xMin) xMin = x;
    if (x > xMax) xMax = x;
    if (y < yMin) yMin = y;
    if (y > yMax) yMax = y;
  }

  final kurvenBreite = xMax - xMin;
  final kurvenHoehe = yMax - yMin;

  // Einheitlich skalieren (kein Verzerren) und zentrieren.
  final scale = (zielBreite * ueberabtastung) / kurvenBreite;
  final zielHoehePx = (kurvenHoehe * scale) / ueberabtastung;
  final versatzX = (leinwand - kurvenBreite * scale) / 2;
  final versatzY = (leinwand - kurvenHoehe * scale) / 2;

  // --- Polygon zeichnen -----------------------------------------------
  final gross = img.Image(width: leinwand, height: leinwand, numChannels: 4);
  final punkte = <img.Point>[];
  for (final p in kurve) {
    punkte.add(img.Point(
      (versatzX + (p[0] - xMin) * scale).round(),
      // y umkehren: mathematisch oben -> Bildschirm oben
      (versatzY + (yMax - p[1]) * scale).round(),
    ));
  }
  img.fillPolygon(
    gross,
    vertices: punkte,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  final canvas = img.copyResize(
    gross,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );

  // --- Ausgabe ---------------------------------------------------------
  const outDir = 'android/app/src/main/res/drawable';
  Directory(outDir).createSync(recursive: true);
  final out = File('$outDir/notification_icon.png');
  out.writeAsBytesSync(img.encodePng(canvas));

  // Kurzmeldung mit der tatsaechlichen Tinten-Box (Tinte = Pixel mit
  // Alpha > 8). Sie zeigt, wie viel der Leinwand das Herz wirklich
  // belegt - daran erkennt man, ob es neben den System-Iconen klein
  // wirkt.
  var minX = size, minY = size, maxX = -1, maxY = -1;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (canvas.getPixel(x, y).a.toInt() > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  final bW = maxX - minX + 1;
  final bH = maxY - minY + 1;
  stdout.writeln('Geschrieben: $out (${size}x$size)');
  stdout.writeln('  Kurve: ${kurvenBreite.toStringAsFixed(1)} x '
      '${kurvenHoehe.toStringAsFixed(1)}  '
      '(Seitenverhaeltnis ${(kurvenBreite / kurvenHoehe).toStringAsFixed(2)})');
  stdout.writeln('  Tinten-Box: ($minX, $minY) - ($maxX, $maxY) '
      '= $bW x $bH px '
      '(${(bW * 100 / size).round()} % x ${(bH * 100 / size).round()} %)');
  stdout.writeln('  Ziel-Hoehe (Rechnung): ${zielHoehePx.toStringAsFixed(1)} px');
}
