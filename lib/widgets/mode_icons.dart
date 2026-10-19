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
    // Alle drei Symbole mit DIESER Strichstaerke. Das ist die einzige
    // Zahl, die die Liste zusammenhaelt - die Apple-HIG nennt genau das
    // (gleiche Strichstaerke, gleiche Detailtiefe, gleiche Perspektive).

    // --- Zug (Frontansicht) -------------------------------------------------
    // GEAENDERT: der Zug ist wieder die FRONTansicht - schmal, mit
    // Windschutzscheibe und zwei Scheinwerfern. Die Seitenansicht
    // (Kasten mit drei Fenstern) war handgezeichnet und wirkte wie
    // ein Spielzeug; die Frontansicht liest sich sofort als Zug.
    //
    // Die Frontansicht ist schmal, deshalb ist sie zentriert und
    // dominant: sie steht exakt auf der Feldmitte 8.5, der Funke
    // laeuft als Streifen DURCH sie hindurch statt daneben zu stehen.
    //
    // GLYPHE per TextPainter, weil in einem CustomPainter kein
    // Icon-Widget zur Verfuegung steht.
    //
    // Die Groesse ist so gewaehlt, dass die Strichstaerke der Glyphe
    // zur der der Nachbarn passt: Material zeichnet mit 2 Einheiten auf
    // 24. Fuer 1.35 im 17er-Feld braucht es 1.35/2*24 = 16.2
    // Einheiten. Genau so gross wird gezeichnet - und damit ist die
    // Strichstaerke deckungsgleich mit den anderen Symbolen, statt
    // 0.83 zu betragen.
    final zug = Icons.train;
    // Der Zug wird in eine Ebene gezeichnet, aus der der Streifen
    // wieder AUSSCHNITTE. Ein saveLayer ueber dem fertigen Bild
    // wuerde nichts loeschen - die neue Ebene enthaelt den Zug nicht.
    canvas.saveLayer(null, Paint());
    _glyphe(canvas, zug.codePoint, zug.fontFamily!, zug.fontPackage,
        const Offset(8.5, 8.5), 16.2);

    // --- Spark als Streifen durch den Zug ----------------------------------
    // Der Funke zieht als Diagonale durch das Feld und durch den Zug
    // hindurch. Das erzaehlt die Verbindung: der Funke BEWEGT sich, und
    // er zieht an dir vorbei, ohne dass du ihn greifen kannst.
    //
    // Der Streifen schneidet die Zugkontur aus, statt darueberzuliegen:
    // sonst verschmilzt er mit dem Zug zu einem undeutlichen Gebilde.
    // Der Ausschnitt ist transparent, es kommt also die Farbe des
    // Containers zum Vorschein - unabhaengig davon, welche das ist.
    final diagonale = Path()
      ..moveTo(3.0, 15.2)
      ..lineTo(13.6, 2.0);
    canvas.drawPath(
      diagonale,
      Paint()
        ..style = PaintingStyle.stroke
        // Duenner als der Zugstrich: bei 2.9 schnitt die Diagonale den
        // Wagen in zwei Haelften, das las sich als zerschnitten, nicht
        // als durchfahrender Funke. 1.9 laesst die Kontur erkennbar und
        // trennt sie zugleich vom Streifen.
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.clear
        ..color = const Color(0xFF000000),
    );
    canvas.restore();

    // Spark-Sterne auf der Diagonalen: der grosse mittig, der kleine
    // scherzt davor her. Sie liegen auf dem ausgeschnittenen Streifen
    // und fallen deshalb frei auf dem Hintergrund.
    canvas.drawPath(stern(const Offset(9.2, 7.8), 2.7, 0.34), flaeche(color));
    canvas.drawPath(stern(const Offset(6.3, 11.2), 1.3, 0.34), flaeche(color));
  }

  /// Zeichnet eine Material-Glyphe in das 17er-Feld, mittig auf [mitte].
  ///
  /// `fontPackage` ist nicht optional: die Material-Schrift liegt im
  /// Paket `flutter`, und ein [TextPainter] ohne dieses Paket findet
  /// sie nicht. Es wird dann kein Zug gezeichnet, sondern ein
  /// Ersatzkaestchen - im Test sichtbar, in der App genauso.
  void _glyphe(
    Canvas canvas,
    int codePoint,
    String family,
    String? paket,
    Offset mitte,
    double groesse,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(codePoint),
        style: TextStyle(
          fontFamily: family,
          // Der Parameter heisst hier `package`, nicht `fontPackage` -
          // den gibt es nur auf IconData. Die Material-Schrift liegt im
          // Paket `flutter`; ohne sie findet der TextPainter die
          // Glyphe nicht und malt ein Ersatzkaestchen.
          package: paket,
          fontSize: 100,
          color: color,
        ),
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
    // --- Blase -----------------------------------------------------------
    // MITTIG: vorher stand die Blase links unten, weil der Funke rechts
    // oben Platz brauchte. Der Funke gehoert jetzt IN die Blase, also
    // kann die Blase wieder mittig stehen - auf 8.5, wie die anderen
    // Motive.
    //
    // Die Kontur ist duenner als bei den anderen Symbolen (1.15 gegen
    // 1.35). Das ist keine Willkuer: eine geschlossene Kontur traegt
    // mehr Tinte pro Laenge als eine offene, und der Umriss einer
    // Sprechblase ist die laengste geschlossene Kontur in der Liste.
    // Bei gleicher Staerke wirkt sie deshalb breiter als der Zug.
    const st = 1.15;
    final aussen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.9, 1.9, 13.2, 12.4),
        const Radius.circular(3.4),
      ));
    final schwanz = Path()
      ..moveTo(4.6, 13.2)
      ..lineTo(3.0, 16.6)
      ..lineTo(8.0, 14.2)
      ..close();
    final mitSchwanz = Path.combine(PathOperation.union, aussen, schwanz);

    final innen = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.9 + st, 1.9 + st, 13.2 - 2 * st, 12.4 - 2 * st),
        const Radius.circular(3.4 - st / 2),
      ));
    canvas.drawPath(
      Path.combine(PathOperation.difference, mitSchwanz, innen),
      flaeche(color),
    );

    // --- Fragezeichen ------------------------------------------------------
    // KLEINER und duenner als vorher. Das Fragezeichen war so gross,
    // dass es die Blase ausfuellte und zusammen mit dem Funken gar
    // nichts mehr uebrig blieb. Jetzt sitzt es links oben in der
    // Blase und laesst rechts Platz fuer den Funken.
    const frage = (c: Offset(6.0, 7.4), h: 4.4);
    final r = frage.h / 2.0;
    canvas.drawPath(fragezeichenBogen(frage.c, r), strich(color, 1.05));
    // Punkt mit sichtbarem Abstand zum Bogen.
    canvas.drawCircle(
      Offset(frage.c.dx + r * 0.18, frage.c.dy + r * 0.82),
      r * 0.16,
      flaeche(color),
    );

    // --- Funke IN der Blase ------------------------------------------------
    // Rechts unten in der Blase, nicht neben ihr. Der Funke war
    // vorher ein zweites Motiv neben der Blase und hat die Kachel in
    // zwei Teile geteilt; in der Blase ist es ein Aufdruck und traegt
    // die Aussage "Funke in einem Chat".
    funkeMitSchleier(canvas, const Offset(10.9, 10.7), 1.9, color);
  }
}
