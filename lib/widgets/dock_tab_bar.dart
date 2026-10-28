import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Ein Reiter des Docks.
class DockTab {
  const DockTab({
    required this.route,
    required this.icon,
    required this.labelKey,
  });

  /// Ziel-Route des Reiters.
  final String route;

  /// Symbol des Reiters.
  final IconData icon;

  /// L10n-KEY der Beschriftung (kein Text - der Text kommt aus
  /// [L10n.t]).
  final String labelKey;
}

/// Die Reiter-Leiste der App - ein schwebendes DOCK.
///
/// NUTZERWUNSCH (28.10.2026): "Die Reiterleiste unten sieht nicht
/// wirklich anders und mehr besonders oder einzigartig aus. Sie soll
/// vollstaendig ueberarbeitet werden. Die Icons koennen bleiben, aber
/// das Design generell von der Leiste nicht." Und: "Ich moechte die
/// Leiste einfach anders haben, da fast jede Android App sie so hat
/// und damit meine App sehr aehnlich wie die anderen aussieht. Sie
/// soll jedoch etwas besonderes sein, was immer noch sehr
/// benutzerfreundend ist."
///
/// WAS DIESES DOCK ANDERS MACHT:
///   * Die inaktiven Reiter zeigen NUR ihr Symbol.
///   * Der aktive Reiter waechst zu einer gefuellten Pille aus Symbol
///     UND Text. Man sieht also jederzeit, wo man ist, ohne dass vier
///     Textzeilen die halbe Bildschirmbreite belegen - das ist der
///     Unterschied zur Material-Leiste, bei der IMMER alle vier
///     Labels dastehen.
///   * Die Pille waechst weich mit (AnimatedSize), der Text laeuft
///     seitlich ein statt zu springen.
///   * Das Ganze sitzt als schmales Dock ueber dem Rand, nicht als
///     randabfallender Balken.
///
/// BEDIENBARKEIT (der Nutzerwunsch sagt ausdruecklich: "immer noch
/// sehr benutzerfreundend"):
///   * Der aktive Reiter traegt IMMER seinen Text - man ist nie ratlos.
///   * Jeder Reiter hat eine Trefferflaeche von mindestens 44 dp Hoehe.
///   * Die Semantik meldet den aktiven Zustand an Screenreader.
///   * Ein Haptik-Klick bestaetigt den Wechsel.
class DockTabBar extends StatelessWidget {
  const DockTabBar({
    required this.index,
    required this.tabs,
    required this.onSelected,
    super.key,
  });

  /// Index des aktiven Reiters.
  final int index;

  /// Die Reiter der Leiste.
  final List<DockTab> tabs;

  /// Wird beim Wechsel des Reiters aufgerufen.
  final ValueChanged<int> onSelected;

  /// Radius der Pille. 999 macht aus jedem Rechteck eine Pille
  /// unabhaengig von der Hoehe.
  static const double _pilleRadius = 999;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          // FESTE SLOTS: Jeder Reiter bekommt genau ein Viertel der
          // Breite. Dadurch stehen die Symbole IMMER an derselben
          // Stelle - beim Wechsel rutscht nichts.
          //
          // Vorher war die Leiste "spaceEvenly" mit unterschiedlich
          // breiten Reitern: der aktive Reiter wuchs (Symbol + Text)
          // und schob thereby alle anderen beiseite. Das Symbol
          // selbst wanderte innerhalb seiner Pille nach links, der
          // aktive Reiter saß dadurch "komisch" (NUTZERWUNSCH
          // 28.10.2026: "wenn man auf einen Punkt klickt diese
          // Animationsverfärbung besser passend machen, da sie
          // komisch sitzt").
          Expanded(
            child: _DockTabItem(
              tab: tabs[i],
              selected: i == index,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(i);
              },
            ),
          ),
      ],
    );
  }
}

class _DockTabItem extends StatelessWidget {
  const _DockTabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final DockTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final symbolFarbe = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final beschriftung = L10n.t(context, tab.labelKey);

    return Semantics(
      selected: selected,
      button: true,
      label: beschriftung,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DockTabBar._pilleRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Der Punkt hinter dem Symbol: ein Kreis, der IMMER
                // mittig auf dem Symbol sitzt (nicht auf Symbol+Text).
                // Das Symbol bleibt dadurch beim Wechsel exakt an
                // derselben Stelle stehen.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    // Ein weicher Schein: der Punkt hebt sich vom Dock
                    // ab, ohne aufzutragen.
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(tab.icon, size: 21, color: symbolFarbe),
                ),
                const SizedBox(height: 3),
                // Das Label: nur beim aktiven Reiter sichtbar. Der
                // Platz bleibt aber IMMER reserviert, damit die Leiste
                // beim Wechsel nicht springt.
                SizedBox(
                  height: 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: selected ? 1 : 0,
                    child: Text(
                      beschriftung,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
