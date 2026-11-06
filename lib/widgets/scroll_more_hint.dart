import 'package:flutter/material.dart';

/// Dezenter "Strich" am rechten Rand, der anzeigt, dass der Inhalt
/// weiter nach unten geht (Nutzerwunsch für die Profil-Seite: die
/// Buttons "Profil" und "Bug melden" waren ohne Scrollen unsichtbar).
///
/// Der Strich erscheint nur, solange tatsächlich Inhalt unterhalb der
/// Sichtweite liegt, verschwindet am Seitenende (weiche Ein-/Ausblendung)
/// und färbt sich im Design (Primärfarbe, subtil). Er ist nicht
/// interaktiv ([IgnorePointer]) und blockiert keine Gesten.
class ScrollMoreHint extends StatefulWidget {
  const ScrollMoreHint({required this.child, super.key});

  /// Der Scrollbare Inhalt (z. B. eine [SingleChildScrollView]).
  final Widget child;

  @override
  State<ScrollMoreHint> createState() => _ScrollMoreHintState();
}

class _ScrollMoreHintState extends State<ScrollMoreHint> {
  bool _canScrollDown = false;

  void _updateFromMetrics(ScrollMetrics metrics) {
    final canScroll = metrics.extentAfter > 24;
    if (canScroll != _canScrollDown && mounted) {
      setState(() => _canScrollDown = canScroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // Feuert auch beim Layout (Initialzustand, Tastatur, Inhaltsänderung).
      onNotification: (n) {
        _updateFromMetrics(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        // Zusätzlich bei jedem Scroll-Ereignis (drag/fling).
        onNotification: (n) {
          _updateFromMetrics(n.metrics);
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _canScrollDown ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      width: 4,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
