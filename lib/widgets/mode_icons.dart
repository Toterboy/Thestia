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
/// ## Umriss statt Fläche
///
/// Die dritte Fassung füllte den Zugkörper als geschlossene Fläche. In
/// der Liste daneben stehen `Icons.event` und `Icons.qr_code_scanner` —
/// reine Umrisse mit viel Weiß darin. Eine gefüllte Masse wiegt bei
/// gleicher Ausdehnung deutlich schwerer und wirkt dadurch größer. Alle
/// drei sind jetzt Umrisse.
///
/// ## Größe
///
/// „Gleiche Größe wie Material" war zwei Fassungen lang geraten und
/// trotzdem daneben. Nachgemessen ist `Icons.event` bei 40 dp nur 30 dp
/// breit — die Konstruktionsangabe (20 Einheiten im 24er-Viewport)
/// beschreibt den Bau der Glyphe, nicht ihre Tinte. Deshalb das Feld
/// auf 17 verkleinert.
///
/// ## Schleier
///
/// Funke und Funke-mit-Schleier sind zwei verschiedene Dinge: ein
/// einzelner Stern steht still, ein Stern mit Schleier fliegt. Der
/// Schleier läuft als Kette kleinerer Sterne hinter dem Hauptstern her
/// und ist bei Find your Spark und Transit Spark dasselbe Motiv.
///
/// Die Formen sind absichtlich auf wenige Striche reduziert: bei 40 dp
/// sieht man keine Feinheiten mehr, und überladene Pfade werden zu Grau.

/// Kantenlänge des 24x24-Viewports.
const double _viewport = 24.0;

/// Seitenlänge des Inhaltsfelds.
///
/// NICHT 20, obwohl Material-Symbole im 24er-Viewport meist ein 20er-
/// Feld nutzen: der Wert beschreibt die Konstruktion der Glyphe, nicht
/// ihre Tinte. Nachgemessen ist `Icons.event` bei 40 dp nur 30 dp breit,
/// und die Nachbarn wirken in der Liste trotzdem kleiner als die eigenen
/// Symbole. Der Unterschied ist die **Fläche**: Kalender und QR-Code
/// sind Umrisse mit viel Weiss darin, ein gefuellter Zugkoerper ist eine
/// kompakte schwarze Masse und wiegt optisch schwerer als dieselbe
/// Ausdehnung in Strichzeichnung.
///
/// Darum zwei Eingriffe statt einer Zahl: das Feld auf 17 verkleinert
/// (Innenabstand von 3.3 auf jeder Seite) UND alle drei Symbole als
/// Umriss gezeichnet, nicht gefuellt.
const double inhalt = 17.0;

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

/// Funke **mit Schleier** — ein Stern und zwei kleinere, die ihm nachlaufen.
///
/// Der Schleier ist kein Beiwerk, sondern die Bewegung: ein einzelner
/// Stern steht still, ein Stern mit Schleier fliegt. Ohne ihn liest sich
/// „Spark" als statisches Sternsymbol, mit ihm als Funkenausbruch.
///
/// Gezeichnet wird der Schleier von hinten nach vorn: erst der
/// kleinste, dann der mittlere, zuletzt der Hauptstern. Wer die
/// Reihenfolge umkehrt, überlagert die grossen Flächen die kleinen und
/// die Spur zerfällt zu einem Klecks.
///
/// [richtung] ist die Flugrichtung; der Schleier liegt auf der
/// Gegenseite. [stufen] ist die Länge der Spur in Sternradien.
void funkeMitSchleier(
  Canvas canvas,
  Offset c,
  double r,
  Color color, {
  double richtung = -2.36, // nach links oben
  double stufen = 0.62,
  double mager = 0.34,
}) {
  final d = Offset(math.cos(richtung), math.sin(richtung));
  for (final anteil in [0.72, 1.42]) {
    final pos = c + d * (r * stufen * anteil);
    canvas.drawPath(
      stern(pos, r * (1.45 - anteil) * 0.42, mager),
      flaeche(color),
    );
  }
  canvas.drawPath(stern(c, r, mager), flaeche(color));
}

/// Ein Fragezeichen aus einem Strich und einem Punkt.
///
/// Gezeichnet, nicht per [TextPainter]: ein TextPainter braucht eine
/// [TextStyle] und damit eine Schriftart, deren Fragezeichen bei dieser
/// Größe auf anderen Dichten anders aussehen. Die Kurve ist bewusst
/// kantig - bei 3 Einheiten Höhe verschwindet jede Rundung als Wulst.
Path fragezeichenBogen(Offset c, double s) {
  return Path()
    ..moveTo(c.dx - s * 0.46, c.dy - s * 0.16)
    ..cubicTo(c.dx - s * 0.58, c.dy - s * 0.92,
        c.dx + s * 0.58, c.dy - s * 0.92,
        c.dx + s * 0.58, c.dy - s * 0.10)
    ..cubicTo(c.dx + s * 0.58, c.dy + s * 0.26,
        c.dx + s * 0.05, c.dy + s * 0.24,
        c.dx + s * 0.05, c.dy + s * 0.54);
}

// ---------------------------------------------------------------------------
// Transit Spark: Bahn unter einem Funken
// ---------------------------------------------------------------------------

/// Transit Spark — eine Bahn, darüber ein Funke **mit Schleier**.
///
/// Aufbau im 17er-Feld:
///   * Bahn unten als UMRISS: Körper, zwei gefüllte Fenster, zwei Räder
///   * Funke oben mit Schleier, der nach links oben ausläuft
///
/// Die Bahn ist im Umriss gezeichnet, nicht gefüllt. Als gefüllter
/// Block war sie die Ursache für „wirkt grauenhalt": neben
/// `Icons.event`, einem reinen Umriss, hing eine geschlossene schwarze
/// Fläche in der Liste - gleiche Ausdehnung, doppelte optische Schwere.
class TransitSparkPainter extends _ModeSymbolPainter {
  TransitSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final linie = strich(color, 1.35);

    // --- Bahn ---------------------------------------------------------------
    // Körper als Umriss. Die Fenster sind gefüllt: als weitere Umrisse
    // wären sie bei dieser Größe nur noch vier Striche, die mit dem
    // Körper verschwimmen.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.8, 6.7, 11.4, 5.3),
        const Radius.circular(1.8),
      ),
      linie,
    );
    for (final x in [5.25, 11.75]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, 9.3), width: 3.5, height: 1.6),
        flaeche(color),
      );
    }
    for (final x in [5.25, 11.75]) {
      canvas.drawCircle(Offset(x, 13.5), 1.1, linie);
    }

    // --- Funke mit Schleier -------------------------------------------------
    funkeMitSchleier(canvas, const Offset(12.2, 3.0), 2.2, color);
  }
}

// ---------------------------------------------------------------------------
// Find your Spark: ein Funke sucht den anderen
// ---------------------------------------------------------------------------

/// Find your Spark — eine Lupe, in deren Linse ein Funke **mit Schleier**
/// liegt.
///
/// Die Lupe ist das „suchen", der Funke darin das „gefundene". Der
/// Schleier läuft nach links oben aus und zeigt die Flugrichtung — so
/// war der Hinweis auf Bewegung schon da, er war nur nicht als
/// Schleier erkennbar.
class FindSparkPainter extends _ModeSymbolPainter {
  FindSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    const c = Offset(7.1, 7.1);

    // Funke mit Schleier im Zentrum der Linse.
    funkeMitSchleier(canvas, c, 2.35, color);

    // Lupenring um den Funken.
    canvas.drawCircle(c, 5.1, strich(color, 1.35));

    // Stiel: startet auf dem Ring (45°) und läuft nach rechts unten bis
    // in die Ecke des 17er-Felds.
    canvas.drawLine(
      const Offset(10.7, 10.7),
      const Offset(15.0, 15.0),
      strich(color, 1.5),
    );
  }
}

// ---------------------------------------------------------------------------
// Zufallschat: leere Sprechblase
// ---------------------------------------------------------------------------

/// Zufallschat — Sprechblase mit Fragezeichen.
///
/// Das Fragezeichen ist die Information, die vorher fehlte: die Kachel
/// heißt „Zufallschat", eine leere Blase sagt davon nichts. Zwei Frage-
/// zeichen, weil der Zufall zielt, nicht eine offene Frage.
class QuestionChatPainter extends _ModeSymbolPainter {
  QuestionChatPainter(super.color);

  @override
  void draw(Canvas canvas) {
    const st = 1.35;
    final aussen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.9, 2.2, 13.2, 10.4),
        const Radius.circular(3.0),
      ));
    final schwanz = Path()
      ..moveTo(4.8, 11.4)
      ..lineTo(3.0, 15.6)
      ..lineTo(8.4, 12.4)
      ..close();
    final mitSchwanz = Path.combine(PathOperation.union, aussen, schwanz);

    final innen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.9 + st, 2.2 + st, 13.2 - 2 * st, 10.4 - 2 * st),
        const Radius.circular(3.0 - st / 2),
      ));
    canvas.drawPath(
      Path.combine(PathOperation.difference, mitSchwanz, innen),
      flaeche(color),
    );

    // Zwei Fragezeichen, das große links, das kleine rechts versetzt.
    // Versetzt, damit sie sich nicht zu einer Lesezeichenreihe
    // zusammenschließen - die Blase ist hochkant.
    const gross = Offset(5.9, 6.3);
    const klein = Offset(11.2, 8.4);
    final s = strich(color, 1.15);
    for (final frage in [
      (c: gross, h: 4.6),
      (c: klein, h: 3.2),
    ]) {
      final r = frage.h / 2.0;
      canvas.drawPath(fragezeichenBogen(frage.c, r), s);
      canvas.drawCircle(
        Offset(frage.c.dx, frage.c.dy + r * 0.86),
        r * 0.17,
        flaeche(color),
      );
    }
  }
}
