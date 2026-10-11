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
/// ## Ein Motiv pro Symbol
///
/// Die zweite Fassung zeichnete in dasselbe Feld mehrere Motive
/// nebeneinander - Transit Spark bekam Radar-Bögen UND Funke UND Zug,
/// Find your Spark zwei Funken plus Lupe. In der echten Liste wirkt das
/// nicht reichhaltig, sondern unruhig: neben `Icons.event` und
/// `Icons.qr_code_scanner`, die je EIN Motiv haben und deshalb sofort
/// lesbar sind, zerfielen die Eigenzeichen in Klecks. Zurück auf je ein
/// Motiv, das den Namen trägt.
///
/// ## Gleiche Größe wie die Material-Symbole
///
/// Material-Symbole sind in einem 24x24-Viewport gezeichnet, ihr Inhalt
/// liegt aber in einem 20x20-Feld in der Mitte - zwei Einheiten Luft auf
/// jeder Seite. Die erste Fassung dieser Symbole füllte das volle 24er-
/// Feld und wirkte dadurch rund 20 % größer als die Nachbarn.
///
/// Deshalb zeichnen alle drei in ein [inhalt]-Quadrat, das zentral im
/// 24er-Viewport liegt. [ModeSymbol] skaliert es entsprechend.
///
/// ## Strichstärke
///
/// Material nutzt 2 Einheiten auf 24, also gut ein Zehntel der Kanten-
/// länge. Auf das 20er-Feld übertragen sind das 1.67. Die Eigenzeichen
/// lagen mit 1.5-1.6 knapp darunter und wirkten dadurch optisch schwerer
/// als die Nachbarn - bei gleicher Farbe und Fläche liest sich das als
/// "dicker". Hier jetzt 1.45.

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
// Transit Spark: Bahn unter einem Funken
// ---------------------------------------------------------------------------

/// Transit Spark — eine Bahn, darüber ein Funke.
///
/// Aufbau im 20er-Feld:
///   * Bahn unten: Körper mit zwei Fenstern und zwei Rädern
///   * Funke oben, leicht rechts versetzt
///
/// Die frühere Fassung ergänzte zwei Radar-Bögen links oben. Sie fielen
/// gegen die kräftige Bahnfarbe nicht auf, machten aber aus einem Motiv
/// drei und füllten die obere Hälfte, in der vorher nur der Funke stand.
class TransitSparkPainter extends _ModeSymbolPainter {
  TransitSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    // --- Bahn (unten, dominiert) ------------------------------------------
    // Der Körper ist eine gefüllte Fläche; die Fenster sind echte Löcher
    // über evenOdd, damit der Container durchscheint.
    final koerper = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.8, 7.4, 14.4, 6.2),
        const Radius.circular(2.2),
      ));
    for (final x in [6.4, 13.6]) {
      koerper.addRect(
        Rect.fromCenter(center: Offset(x, 10.5), width: 4.4, height: 2.6),
      );
    }
    canvas.drawPath(
      Path.from(koerper)..fillType = PathFillType.evenOdd,
      flaeche(color),
    );

    // Räder: gefüllte Kreise, kein Ring. Bei dieser Größe verschwindet
    // der Ring, gefüllt liest er sich als Rad.
    for (final x in [6.4, 13.6]) {
      canvas.drawCircle(Offset(x, 15.3), 1.35, flaeche(color));
    }

    // --- Funke (oben) ------------------------------------------------------
    canvas.drawPath(
      stern(const Offset(15.6, 3.7), 3.1, 0.34),
      flaeche(color),
    );
  }
}

// ---------------------------------------------------------------------------
// Find your Spark: ein Funke sucht den anderen
// ---------------------------------------------------------------------------

/// Find your Spark — eine Lupe, in deren Linse ein Funke liegt.
///
/// Die Lupe ist das „suchen", der Funke darin das „gefundene". Die
/// frühere Fassung setzte zusätzlich einen zweiten, kleineren Funken
/// links außen - der war neben dem Funken in der Linse ein gleichwer-
/// tiger Klotz ohne eigene Bedeutung, und beide zusammen machten die
/// Linse voll. Jetzt ein Motiv: der Funke liegt exakt im Mittelpunkt der
/// Linse, das Auge findet ihn sofort.
class FindSparkPainter extends _ModeSymbolPainter {
  FindSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    const c = Offset(8.8, 8.8);

    // Funke im Zentrum der Linse.
    canvas.drawPath(stern(c, 2.7, 0.34), flaeche(color));

    // Lupenring um den Funken.
    canvas.drawCircle(c, 5.8, strich(color, 1.45));

    // Stiel: startet auf dem Ring (45°) und läuft nach rechts unten bis
    // in die Ecke des 20er-Felds.
    canvas.drawLine(
      const Offset(12.9, 12.9),
      const Offset(17.7, 17.7),
      strich(color, 1.6),
    );
  }
}

// ---------------------------------------------------------------------------
// Zufallschat: leere Sprechblase
// ---------------------------------------------------------------------------

/// Zufallschat — eine leere Sprechblase.
///
/// Die frühere Fassung trug zusätzlich ein gezeichnetes Fragezeichen und
/// einen Schwanz aus drei freistehenden Linien. Der Schwanz war das
/// eigentliche Problem: drei Linien neben einer Rounded-Box lesen sich als
/// Schrägstrich, nicht als Blase, und die Verbindungsstelle klaffte. Das
/// Fragezeichen füllte die Blase zusätzlich, ohne Information zu tragen —
/// die Kachel darunter heißt ohnehin „Zufallschat".
///
/// Jetzt nur noch die Blase. Der Schwanz entsteht über
/// [Path.combine]: Außenkontur (Rounded-Box ∪ Dreieck) minus
/// Innenkontur (um die halbe Strichstärke nach innen versetzte Box).
/// Dadurch ist der Schwanz Teil derselben Fläche und kann keine Naht
/// bekommen — genau das war vorher der Grund für das Krumme.
class QuestionChatPainter extends _ModeSymbolPainter {
  QuestionChatPainter(super.color);

  @override
  void draw(Canvas canvas) {
    const st = 1.45;
    final aussen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.2, 2.6, 15.6, 12.2),
        const Radius.circular(3.4),
      ));
    final schwanz = Path()
      ..moveTo(6.0, 13.4)
      ..lineTo(4.0, 18.4)
      ..lineTo(10.4, 15.0)
      ..close();
    final mitSchwanz = Path.combine(PathOperation.union, aussen, schwanz);

    final innen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.2 + st, 2.6 + st, 15.6 - 2 * st, 12.2 - 2 * st),
        const Radius.circular(3.4 - st / 2),
      ));
    final ring = Path.combine(PathOperation.difference, mitSchwanz, innen);
    canvas.drawPath(ring, flaeche(color));
  }
}
