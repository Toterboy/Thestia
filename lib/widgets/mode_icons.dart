import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Baut ein Symbol in der angegebenen Farbe.
typedef ModeSymbolBuilder = CustomPainter Function(Color color);

/// Eigene Symbole für die Entdeckungs-Modi.
///
/// Alle drei sind [CustomPainter], kein Bild-Asset. Gründe:
///   * Sie skalieren scharf auf jede Dichte, ohne 5 PNG-Größen zu pflegen.
///   * Sie nehmen die Theme-Farbe des Containers an (`onPrimary` bzw.
///     `onSurfaceVariant`) — die bisherigen Material-Symbole taten das
///     auch; über einen festen Farbverlauf wäre das nicht mehr konsistent.
///   * Ein Funke, eine Lupe und ein Fragezeichen lassen sich als Vektor
///     genau so positionieren, wie es die 56×56-dp-Kachel braucht.
///
/// Gezeichnet wird in einem 24×24-Raster, wie es Material-Symbole ebenfalls
/// tun. So passt das Gewicht zu den Symbolen, die neben ihnen stehen
/// (`Icons.event` bei Dating Hour, `Icons.qr_code_scanner` beim QR-Scan).
///
/// Die beiden unveränderten Modi bleiben bei Material-Symbolen — siehe
/// `DiscoveryModeSymbol` in `swipe_mode_selection_screen.dart'.

/// Zeichnet ein Symbol in der Größe [size] mit der Farbe [color].
class ModeSymbol extends StatelessWidget {
  const ModeSymbol(this.erstellen,
      {super.key, this.size = 28, required this.color});

  /// Erzeugt den Painter mit der Farbe. Als Funktion, weil [CustomPainter]
  /// keine Farbe im Konstruktor annimmt — ein nachträgliches Setzen wäre
  /// einfach zu vergessen.
  final ModeSymbolBuilder erstellen;

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: erstellen(color)),
      );
}

/// Basis: allen gemein ist das 24×24-Raster und die Farbe.
abstract class _ModeSymbolPainter extends CustomPainter {
  _ModeSymbolPainter(this.color);

  Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final f = size.width / 24.0;
    canvas.save();
    canvas.scale(f);
    draw(canvas);
    canvas.restore();
  }

  void draw(Canvas canvas);

  @override
  bool shouldRepaint(_ModeSymbolPainter old) => old.color != color;
}

/// Vierstrahliger Stern („Funke").
///
/// [duenn] bestimmt, wie spitz die Strahlen sind: kleiner = spitzer. Der
/// Wert 0.34 sieht in beiden Symbolen aus wie ein Stern und nicht wie ein
/// Zahnrad — darum steht er hier und nicht in jedem Painter.
///
/// Gerade Strecken statt Kurven: ein vierstrahliger Stern ist nichts
/// anderes als acht Punkte abwechselnd weit und nah. Der erste Entwurf
/// hatte das mit Quadratic-Beziern gebaut und bekam einen runden Klecks.
Path stern(Offset c, double r, double duenn) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final radius = i.isEven ? r : r * duenn;
    final winkel = -math.pi / 2 + i * math.pi / 4;
    final x = c.dx + radius * math.cos(winkel);
    final y = c.dy + radius * math.sin(winkel);
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  p.close();
  return p;
}

// ---------------------------------------------------------------------------
// Transit Spark: Funke + Bahn + Radar
// ---------------------------------------------------------------------------

/// Transit Spark — ein Funke über einer Bahn, mit Radar-Bögen.
///
/// Aufbau im 24×24-Raster:
///   * zwei konzentrische Bögen links oben (Radar)
///   * vierzackiger Funke rechts daneben
///   * Bahn unten: Körper mit zwei Fenstern, Radsatz-Striche
class TransitSparkPainter extends _ModeSymbolPainter {
  TransitSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // --- Radar-Bögen (links unten) ----------------------------------------
    // Vom Funken weg verlaufend, nach links unten. Halbkreise im
    // 90°-Fenster: lesbar als „sucht in die Ferne", ohne dass es wie ein
    // Lautsprecher wirkt.
    for (var i = 0; i < 2; i++) {
      final r = 3.2 + i * 2.4;
      final rect = Rect.fromCircle(center: const Offset(5.6, 8.2), radius: r);
      canvas.drawArc(rect, math.pi * 0.15, math.pi * 0.7, false, paint);
    }

    // --- Funke (vierzackiger Stern, oben rechts) ---------------------------
    // Derselbe Stern-Pfad wie in [FindSparkPainter] - der erste Entwurf
    // hatte hier eine eigene Bezier-Kette, die als runder Klecks
    // herauskam statt als Stern.
    canvas.drawPath(
      stern(const Offset(16.4, 4.6), 4.4, 0.34),
      Paint()..color = color,
    );

    // --- Bahn (unten) ------------------------------------------------------
    final bahn = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2.4, 15.6, 19.2, 4.8),
      const Radius.circular(2.4),
    );
    canvas.drawRRect(bahn, Paint()..color = color);

    // Fenster aussparen. `BlendMode.dstOut` entfernt alles unter dem
    // Pinsel — hier ist das gewollt, denn die Fläche darunter hat die
    // Farbe des Containers, nicht des Symbols.
    final fenster = Paint()..blendMode = BlendMode.dstOut;
    for (final x in [5.2, 12.0, 18.8]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 18.0), width: 2.8, height: 2.8),
        fenster,
      );
    }

    // Radsatz: zwei kurze Striche unter dem Körper.
    canvas.drawLine(const Offset(6.2, 21.2), const Offset(6.2, 22.2), paint);
    canvas.drawLine(const Offset(17.8, 21.2), const Offset(17.8, 22.2), paint);
  }
}

// ---------------------------------------------------------------------------
// Find your Spark: ein Funke sucht den anderen
// ---------------------------------------------------------------------------

/// Find your Spark — ein Funke mit Lupe, in der ein zweiter liegt.
///
/// Die beiden Funken sind verschieden groß, damit „sucht" und „gesucht"
/// auseinandergehen — gleich groß sähen sie aus wie ein Paar.
class FindSparkPainter extends _ModeSymbolPainter {
  FindSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final strich = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // kleiner Funke (links, der gesuchte)
    canvas.drawPath(
      stern(const Offset(5.2, 5.0), 4.6, 0.35),
      Paint()..color = color,
    );

    // großer Funke (in der Lupe)
    canvas.drawPath(
      stern(const Offset(13.4, 13.2), 3.1, 0.34),
      Paint()..color = color,
    );

    // Lupe: Ring um den großen Funken, Stiel nach rechts unten
    canvas.drawCircle(const Offset(13.4, 13.2), 6.4, strich);
    canvas.drawLine(
      const Offset(18.0, 17.8),
      const Offset(22.2, 22.0),
      strich,
    );
  }

}

// ---------------------------------------------------------------------------
// Zufallschat: Sprechblase mit Fragezeichen
// ---------------------------------------------------------------------------

/// Zufallschat — Sprechblase mit Fragezeichen.
///
/// Das Fragezeichen ist gezeichnet, nicht per TextPainter gesetzt: ein
/// TextPainter braucht eine TextStyle und damit eine Schriftart, die bei
/// 28 dp auf anderen Dichten anders aussieht.
class QuestionChatPainter extends _ModeSymbolPainter {
  QuestionChatPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final strich = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    // Blase
    final blase = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2.6, 3.4, 18.8, 13.6),
      const Radius.circular(4.4),
    );
    canvas.drawRRect(blase, strich);

    // Schwanz nach links unten
    final schwanz = Path()
      ..moveTo(7.4, 16.6)
      ..lineTo(5.6, 21.0)
      ..lineTo(11.2, 17.4);
    canvas.drawPath(schwanz, strich);

    // Fragezeichen: Bogen, Kurve nach unten, Punkt
    final frage = Path()
      ..moveTo(9.0, 7.2)
      ..cubicTo(9.0, 5.6, 15.0, 5.4, 15.0, 8.6)
      ..cubicTo(15.0, 11.0, 12.0, 11.2, 12.0, 13.4);
    canvas.drawPath(frage, strich);

    canvas.drawCircle(const Offset(12.0, 15.2), 0.95, Paint()..color = color);
  }
}
