import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ruhiger Ladeindikator - der Ersatz fuer den kreisenden Ring.
///
/// NUTZERWUNSCH (31.10.2026): "der kurze Ladekreis ist stoerend fuer die
/// Animation dort". Ein Ring, der nach 200 ms wieder verschwindet, ist
/// ein Blitzer: er zieht den Blick auf sich, unterbricht die Bewegung,
/// in der er gerade auftaucht, und macht aus einem weichen Ueberblenden
/// einen harten Schnitt.
///
/// Dieser Platzhalter ist das Gegenteil:
///
///   * keine harte Kante, kein Kreislauf, kein Sprung am Ende
///   * drei Balken, die langsam ein- und ausblenden
///   * versetzte Phasen - sie atmen nacheinander, nicht im Gleichtakt
///   * er verschwindet genauso leise, wie er kam
///
/// Er ist bewusst kein Ersatz fuer eine Statusanzeige, sondern ein
/// "hier passiert gerade etwas"-Zeichen. Wie lange er steht, sagt er
/// nicht - das weiss der, der wartet, ohne dass die Oberflaeche es
/// aufregen muss.
class CalmLoading extends StatefulWidget {
  const CalmLoading({
    this.lines = 3,
    this.maxWidth = 320,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    super.key,
  });

  /// Anzahl der Balken.
  final int lines;

  /// Hoechstbreite der Balkengruppe. Ohne diese Begrenzung waeren die
  /// Balken auf einem Tablet so breit, dass sie nicht mehr wie ein
  /// Platzhalter wirken.
  final double maxWidth;

  /// Abstand zum Rand.
  final EdgeInsets padding;

  @override
  State<CalmLoading> createState() => _CalmLoadingState();
}

class _CalmLoadingState extends State<CalmLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final verfuegbar = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.maxWidth;
        final breite = math.min(verfuegbar, widget.maxWidth);

        return Center(
          child: Padding(
            padding: widget.padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(widget.lines, (i) {
                // Versetzte Phase: der n-te Balken beginnt um
                // n * 0,18 des Durchlaufs. Das Atmen dadurch nacheinander
                // statt gleichzeitig - und der Rhythmus ist nicht so
                // vorhersehbar, dass man ihn als Ladekreislauf liest.
                final begin = (i * 0.18).clamp(0.0, 0.55);
                final ende = math.min(begin + 0.45, 1.0);
                final anim = CurvedAnimation(
                  parent: _controller,
                  curve: Interval(
                    begin,
                    ende,
                    curve: Curves.easeInOut,
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FadeTransition(
                    opacity:
                        Tween<double>(begin: 0.30, end: 1.0).animate(anim),
                    child: Container(
                      width: breite * (i.isEven ? 1.0 : 0.62),
                      height: 12,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
