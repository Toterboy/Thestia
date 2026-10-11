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
  double mager = 0.34,
}) {
  final d = Offset(math.cos(richtung), math.sin(richtung));
  // Spur als feste Groessen, NICHT aus r abgeleitet.
  //
  // Die erste Fassung rechnete die Spurgroesse als r * (1.45 - anteil)
  // * 0.42 und lief dabei ueber zwei Stuetzstellen. Bei der zweiten
  // Stufe ergab das r * 0.03 * 0.42 - praktisch null. Ein Stern mit
  // Nichts am Schweif ist ein Stern, und genau so ist es angekommen:
  // "der Schleier hat nicht funktioniert".
  //
  // Abstand und Groesse stehen deshalb jetzt nebeneinander: der
  // hintere Stern muss sichtbar bleiben, sonst ist es wieder kein
  // Schleier, sondern ein Punkt.
  const spur = [
    (abstand: 1.50, groesse: 0.28),
    (abstand: 0.82, groesse: 0.46),
  ];
  for (final s in spur) {
    canvas.drawPath(
      stern(c + d * (r * s.abstand), r * s.groesse, mager),
      flaeche(color),
    );
  }
  canvas.drawPath(stern(c, r, mager), flaeche(color));
}

/// Ein Fragezeichen als Bogen — der Punkt kommt separat dazu.
///
/// Gezeichnet, nicht per [TextPainter]: ein TextPainter braucht eine
/// [TextStyle] und damit eine Schriftart, deren Fragezeichen bei dieser
/// Größe auf anderen Dichten anders aussehen.
///
/// [s] ist die halbe Höhe des Zeichens, der Bogen endet bei `cy + 0.44s`.
/// Der Punkt sitzt bei `cy + 0.82s` — die Lücke dazwischen ist
/// Pflicht: hängt der Punkt am Bogen, ist es kein Fragezeichen mehr,
/// sondern ein Haken mit Klecks. Genau daran ist die erste Fassung
/// gescheitert, der Bogen lief ohne sichtbare Lücke in den Punkt.
Path fragezeichenBogen(Offset c, double s) {
  return Path()
    ..moveTo(c.dx - s * 0.44, c.dy - s * 0.18)
    // Bogen nach oben und über die rechte Schulter.
    ..cubicTo(c.dx - s * 0.56, c.dy - s * 0.88,
        c.dx + s * 0.56, c.dy - s * 0.88,
        c.dx + s * 0.56, c.dy - s * 0.26)
    // Herunter und zur Mitte, dort endet der Bogen als kurzer Stamm.
    ..cubicTo(c.dx + s * 0.56, c.dy + s * 0.12,
        c.dx + s * 0.18, c.dy + s * 0.10,
        c.dx + s * 0.18, c.dy + s * 0.44);
}

/// Transit Spark — Bahn mit Funken-Schleier.
///
/// Die Geschichte dieses Zeichners, weil sie den Weg erklaert: der
/// Wagen ist fuenfmal ueberarbeitet worden — gefuellt, dann im
/// Umriss mit zwei Fenstern, dann mit drei und 3:1-Proportion, dann
/// mit Materials Frontansicht statt der gezeichneten, dann mit Dach
/// und Fahrwerk. Jedes Mal lautete das Urteil "sieht komisch aus"
/// bzw. "keine wirkliche Bahn".
///
/// Zwei Versuche mit Material waren ebenfalls falsch und stehen
/// hier festgehalten, damit sie nicht wiederholt werden:
/// `Icons.train` und `Icons.directions_bus` zeigen BEIDE eine
/// Frontansicht. Beide sind damit schmal und fuellen ein
/// quadratisches Feld zur Haelfte der Breite, wirken klein und
/// wirken nicht wie "unterwegs".
///
/// Was am Ende den Unterschied macht, sind drei Kleinigkeiten und
/// nicht die Proportion: ein Strich ueber dem Kasten (Dach), Raeder,
/// die am Kasten ANSTOSSEN, und eine Deichsel zwischen ihnen. Ohne
/// die beiden letzteren liest sich das als Spielzeug.
class TransitSparkPainter extends _ModeSymbolPainter {
  TransitSparkPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final linie = strich(color, 1.3);
    final dick = strich(color, 1.5);

    // --- Dach ---------------------------------------------------------------
    // Ein Strich ueber dem Kasten. Ohne ihn ist der Wagen ein
    // Rechteck mit Fenstern; mit ihm ist es ein Fahrzeug mit Dach. Das
    // ist der Unterschied, an dem "keine wirkliche Bahn" haengt.
    canvas.drawLine(
      const Offset(3.6, 6.0),
      const Offset(13.4, 6.0),
      linie,
    );

    // --- Kasten -------------------------------------------------------------
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.2, 6.4, 12.6, 5.0),
        const Radius.circular(1.5),
      ),
      dick,
    );

    // Drei Fenster, gleichmaessig verteilt, mittig im Kasten.
    for (final x in [4.6, 8.5, 12.4]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, 8.9), width: 3.1, height: 1.8),
        flaeche(color),
      );
    }

    // --- Fahrwerk -----------------------------------------------------------
    // Die Raeder muessen am Kasten ANSTOSSEN und untereinander durch
    // eine Deichsel verbunden sein. Zwei lose Kreise unter einem
    // Rechteck lesen sich als Spielzeug, nicht als Bahn.
    canvas.drawLine(
      const Offset(5.6, 12.7),
      const Offset(11.4, 12.7),
      linie,
    );
    for (final x in [5.6, 11.4]) {
      canvas.drawCircle(Offset(x, 12.7), 1.4, linie);
    }

    // --- Funke mit Schleier -------------------------------------------------
    // Im selben Painter, nicht als Stapel ueber dem Kasten: als
    // eigener Stapel hing der Funk in der Ecke und der Wagen stand
    // unten links, die Kachel war also unten lastig und oben leer.
    funkeMitSchleier(canvas, const Offset(12.3, 2.6), 2.0, color);
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

    // Zwei Fragezeichen, das grosse links oben, das kleine rechts
    // unten. Versetzt, weil sie sich sonst zu einer Lesezeichenreihe
    // zusammenschliessen - die Blase ist hochkant.
    //
    // Stroeke 0.95 statt 1.15 und etwas kleiner gesetzt: bei 1.15
    // liefen die Fragezeichen bei 40dp in einen Block, und das kleine
    // stiess mit Bogen UND Punkt ueber den Innenrand der Blase, also
    // sichtbar abgeschnitten. Beides kam als "zu dick und abgeschnitten"
    // zurueck.
    const gross = (c: Offset(5.6, 5.8), h: 4.4);
    const klein = (c: Offset(10.9, 8.3), h: 3.0);
    final s = strich(color, 0.95);
    for (final frage in [gross, klein]) {
      final r = frage.h / 2.0;
      canvas.drawPath(fragezeichenBogen(frage.c, r), s);
      // Punkt mit sichtbarem Abstand zum Bogen.
      canvas.drawCircle(
        Offset(frage.c.dx + r * 0.18, frage.c.dy + r * 0.82),
        r * 0.16,
        flaeche(color),
      );
    }
  }
}
