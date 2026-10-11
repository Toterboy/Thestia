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
    // --- Zug ----------------------------------------------------------------
    // `Icons.train` ist die Frontansicht eines Zuges. Sie ist schmal,
    // fuellt die Breite des Feldes also nicht - aber genau DARIN liegt
    // das Argument fuer die Frontansicht: ein schmales Zeichen mittig
    // unter einem Funken ist ruhiger als ein breiter Wagen, der mit dem
    // Funken um die Breite kaempft.
    final zug = Icons.train.fontFamily;
    // Links der Mitte und leicht ueber der Feldmitte: der Funke sitzt
    // rechts oben, und ein Zug genau in der Mitte laege unter ihm wie
    // schief. Die Diagonale Zug-unten-links nach Funke-oben-rechts
    // traegt die Kachel, ohne dass eines der beiden Elemente untergeht.
    _glyphe(canvas, Icons.train.codePoint, zug!, const Offset(7.6, 9.9), 10.0);

    // --- Funke mit Schleier -------------------------------------------------
    funkeMitSchleier(canvas, const Offset(12.9, 4.0), 2.4, color);
  }

  /// Zeichnet eine Material-Glyphe in das 17er-Feld.
  ///
  /// Ueber [TextPainter] gesetzt, weil ein `Icon`-Widget innerhalb eines
  /// [CustomPainter] nicht zur Verfuegung steht - der Zeichner hat nur
  /// eine [Canvas]. Die Groesse ist bewusst ueber [skalierung] gesetzt:
  /// Material-Glyphen tragen ihre Strichstaerke nicht mit, wenn man sie
  /// skaliert, sie werden einfach dicker oder duenner. Darum wird fuer
  /// die gewuenschte Sichtgroesse ueberhaupt erst der Maler gebaut und
  /// das Ergebnis auf die Zielflaeche skaliert.
  void _glyphe(
    Canvas canvas,
    int codePoint,
    String family,
    Offset mitte,
    double groesse,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(codePoint),
        style: TextStyle(fontFamily: family, fontSize: 100, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final sk = groesse / 100.0;
    canvas.save();
    canvas.translate(mitte.dx - (tp.width * sk) / 2,
        mitte.dy - (tp.height * sk) / 2);
    canvas.scale(sk);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
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

    // EIN Fragezeichen, gross und mittig. Die Vorgaengerversion hatte zwei
    // versetzte und kam als "unvollstaendig" und dann "zu dick"
    // zurueck: zwei Fragezeichen in einer hochkanten Blase lesen sich
    // als Reihenzeichen, nicht als Zufall. Ein einziges, gross
    // gesetztes Zeichen hat einen klaren Blickpunkt - das ist die
    // Empfehlung, die fuer eine Icon-Liste ohnehin gilt: EIN
    // Fokuspunkt, nicht mehrere.
    const frage = (c: Offset(8.5, 7.2), h: 7.4);
    final r = frage.h / 2.0;
    final s = strich(color, 1.05);
    canvas.drawPath(fragezeichenBogen(frage.c, r), s);
    // Punkt mit sichtbarem Abstand zum Bogen.
    canvas.drawCircle(
      Offset(frage.c.dx + r * 0.18, frage.c.dy + r * 0.82),
      r * 0.15,
      flaeche(color),
    );
  }
}
