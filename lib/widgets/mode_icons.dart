library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Baut ein Symbol in der angegebenen Farbe.
typedef ModeSymbolBuilder = CustomPainter Function(Color color);

/// Eigene Symbole für die Entdeckungs-Modi (v0.10.0).
///
/// Alle drei sind [CustomPainter], kein Bild-Asset: sie skalieren scharf
/// auf jede Dichte und nehmen die Theme-Farbe des Containers an.
///
/// ## Gleiche Größe wie die Material-Symbole
///
/// Material-Symbole sind in einem 24x24-Viewport gezeichnet, ihr Inhalt
/// liegt aber in einem 20x20-Feld in der Mitte - zwei Einheiten Luft auf
/// jeder Seite. Die erste Fassung dieser Symbole füllte das volle 24er-
/// Feld und wirkte dadurch rund 20 % größer als `Icons.event` und
/// `Icons.qr_code_scanner` neben sich.
///
/// Deshalb zeichnen alle drei in ein [INHALT]-Quadrat, das zentral im
/// 24er-Viewport liegt. [ModeSymbol] skaliert es entsprechend.
///
/// Die Formen sind absichtlich auf wenige Striche reduziert: bei 28 dp
/// sieht man keine Feinheiten mehr, und überladene Pfade werden zu Grau.

/// Kantenlänge des 24x24-Viewports.
const double _viewport = 24.0;

/// Seitenlänge des Inhaltsfelds. 20 lässt wie bei Material-Symbolen zwei
/// Einheiten Luft auf jeder Seite.
const double inhalt = 20.0;

/// Versatz des Inhaltsfelds im Viewport.
const double _inset = (_viewport - inhalt) / 2.0;

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

/// Basis: 24x24-Viewport, Inhalt im [inhalt]-Feld.
abstract class _ModeSymbolPainter extends CustomPainter {
  _ModeSymbolPainter(this.color);

  Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Inhalt zentral ins Viewport legen: skaliert von 24 auf die echte
    // Größe und verschiebt um den Innenabstand.
    final f = size.width / _viewport;
    canvas.scale(f);
    canvas.translate(_inset, _inset);
    // Ab hier ist das Koordinatensystem [inhalt] x [inhalt].
    draw(canvas);
    canvas.restore();
  }

  void draw(Canvas canvas);

  @override
  bool shouldRepaint(_ModeSymbolPainter old) => old.color != color;
}

/// Vierstrahliger Stern („Funke").
///
/// [mager] bestimmt, wie spitz die Strahlen sind: kleiner = spitzer.
/// Gerade Strecken, keine Kurven — ein Stern ist nichts anderes als acht
/// Punkte abwechselnd weit und nah. Der erste Entwurf baute das mit
/// Quadratic-Beziern und bekam einen runden Klecks.
Path stern(Offset c, double r, double mager) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final radius = i.isEven ? r : r * mager;
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

/// Strich-Pinsel mit runden Enden — für alles, was Linie ist.
Paint strich(Color color, double breite) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = breite
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Flächiger Pinsel.
Paint flaeche(Color color) => Paint()..color = color;

// ---------------------------------------------------------------------------
// Transit Spark: Funke + Bahn + Radar
// ---------------------------------------------------------------------------

/// Transit Spark — ein Funke über einer Bahn, mit Radar-Bögen.
///
/// Aufbau im 20er-Feld:
///   * Bahn unten: Körper mit zwei Fenstern und Radsatz
///   * Funke oben rechts, als „Spark"
///   * zwei Radar-Bögen links, die vom Funken weg laufen
///
/// Die Bahn ist das dominierende Element — sie trägt die Bedeutung
/// „unterwegs". Der Funke sitzt darüber und zeigt den Treffer.
class TransitSparkPainter extends _ModeSymbolPainter {
  TransitSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final linie = strich(color, 1.5);

    // --- Bahn (unten, dominiert) ------------------------------------------
    // Körper mit den Fenstern ALS Löcher im Pfad, nicht über
    // BlendMode.dstOut. Der erste Entwurf stanzte mit dstOut aus - das
    // arbeitet aber auf der Ebene des CustomPaint, und die ausgestanzten
    // Stellen wurden SCHWARZ statt durchsichtig. Über evenOdd sind es
    // echte Löcher: der Container zeigt durch.
    final koerper = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.6, 11.6, 14.8, 5.0),
        const Radius.circular(2.5),
      ));
    for (final x in [4.6, 8.4, 12.2, 16.0]) {
      koerper.addRect(
        Rect.fromCenter(center: Offset(x, 13.2), width: 1.9, height: 2.1),
      );
    }
    canvas.drawPath(
      Path.from(koerper)..fillType = PathFillType.evenOdd,
      flaeche(color),
    );

    // Radsatz: zwei Räder als Ringe. Ringe lesen bei dieser Größe besser
    // als Kreuze.
    for (final x in [5.4, 14.6]) {
      canvas.drawCircle(Offset(x, 17.8), 1.5, linie);
    }

    // --- Funke (oben rechts, größer) --------------------------------------
    canvas.drawPath(
      stern(const Offset(14.4, 4.2), 4.6, 0.34),
      flaeche(color),
    );

    // --- Radar-Bögen (links oben) -----------------------------------------
    // Vom Funken weg laufend. Halbkreise mit wachsendem Radius, gleicher
    // Winkel — die klassische Radar-Lesart.
    for (var i = 0; i < 2; i++) {
      final r = 2.6 + i * 2.0;
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(4.4, 7.4), radius: r),
        math.pi * 0.85,
        math.pi * 0.55,
        false,
        linie,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Find your Spark: ein Funke sucht den anderen
// ---------------------------------------------------------------------------

/// Find your Spark — ein Funke mit Lupe, in der ein zweiter liegt.
///
/// Die Lupe ist das „suchen", der Funke darin das „gefundene". Ein
/// dritter, kleiner Funke links außen zeigt die Menge, in der gesucht
/// wird. Alle drei sind Sterne mit demselben [stern]-Helfer, nur in
/// verschiedener Größe — dadurch liest es sich als Familie, nicht als
/// drei verschiedene Objekte.
class FindSparkPainter extends _ModeSymbolPainter {
  FindSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final lupe = strich(color, 1.6);

    // Kleiner Funke links — die Menge, in der gesucht wird.
    canvas.drawPath(
      stern(const Offset(3.6, 3.4), 3.4, 0.36),
      flaeche(color),
    );

    // Funke in der Lupe — deutlich kleiner als der andere, damit „groß
    // sucht klein" lesbar ist.
    canvas.drawPath(
      stern(const Offset(11.6, 11.4), 2.9, 0.34),
      flaeche(color),
    );

    // Lupe: Ring um den gefundenen Funken.
    canvas.drawCircle(const Offset(11.6, 11.4), 5.6, lupe);

    // Stiel nach rechts unten. Endet innerhalb des 20er-Felds.
    canvas.drawLine(
      const Offset(15.7, 15.5),
      const Offset(19.2, 19.0),
      lupe,
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
    final s = strich(color, 1.5);

    // Blase. Rundrechteck mit deutlichem Eckenradius — bei 20 Einheiten
    // wirkt ein zu kleiner Radius wie ein Button statt wie eine Blase.
    const blase = Rect.fromLTWH(2.2, 2.6, 15.6, 12.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(blase, const Radius.circular(3.6)),
      s,
    );

    // Schwanz nach links unten. Gerade, nicht gebogen — bei dieser Größe
    // verschwindet eine Kurve.
    final schwanz = Path()
      ..moveTo(6.4, 14.2)
      ..lineTo(4.6, 18.6)
      ..lineTo(10.2, 15.0);
    canvas.drawPath(schwanz, s);

    // Fragezeichen. Der Bogen oben, dann die Kurve nach unten; der Punkt
    // sitzt mittig darunter.
    final frage = Path()
      ..moveTo(7.6, 5.4)
      ..cubicTo(7.6, 3.6, 12.4, 3.4, 12.4, 7.0)
      ..cubicTo(12.4, 9.0, 10.0, 9.4, 10.0, 11.4);
    canvas.drawPath(frage, s);

    canvas.drawCircle(const Offset(10.0, 13.2), 1.1, flaeche(color));
  }
}
