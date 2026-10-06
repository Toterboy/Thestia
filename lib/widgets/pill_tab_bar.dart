import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pillen-foermiger Tab-Indikator.
///
/// Material `TabBar` mit `indicator` ist ein Unterstrich mit festem
/// Abstand zum Tab-Label - bei sechs Tabs mit Icon und Text steht der
/// Strich zwischen den Labels, nicht hinter dem aktiven. Das war im
/// Admin-Screen die Ursache fuer "ich weiss nicht, wo ich bin": der
/// Indikator war breiter als sein Tab.
///
/// Hier wandert eine gefuellte Pille HINTER den aktiven Tab. Sie ist an
/// Breite und Position des Labels gebunden ([AnimatedPositioned] +
/// [_PillIndicator]) und damit bei jedem Tabwechsel korrekt.
///
/// Warum kein `TabBar`: die Pille muss waehrend der Animation die
/// Breite des Ziellabels annehmen, und ein `TabBar`-Painter kennt die
/// Label-Geometrie nicht. Stattdessen ein eigener Controller-Wrapper,
/// der `TabController` weiter bedient (inkl. `TabBarView`-Synchronisation).
class PillTabBar extends StatelessWidget {
  const PillTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;

  /// Ein Eintrag je Tab: Label, Symbol und optionale Kennzahl-Badges.
  final List<PillTab> tabs;

  /// Eckenradius der Pille. 999 macht aus jedem Rechteck eine Pille
  /// unabhaengig von der Hoehe.
  static const double _pillRadius = 999;

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder liegt HIER, nicht beim Aufrufer: die Auswahl ist
    // Teilzustand dieses Widgets. Haette der Aufrufer sie zu bauen,
    // zeigte die Leiste nach einem Wischen erst beim naechsten
    // Fremd-Rebuild die neue Auswahl - die Pille stuende am falschen Tab.
    return SizedBox(
      // 52 statt 48: Icon + Label brauchen bei 1,3-facher Schriftgroesse
      // mehr, sonst schneidet der Text ab (Barrierefreiheitstest).
      height: 52,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (var i = 0; i < tabs.length; i++)
              _PillTabItem(
                tab: tabs[i],
                selected: controller.index == i,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.animateTo(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Tab: Label, Symbol, optionale Kennzahl (Badge).
class PillTab {
  const PillTab({
    required this.label,
    required this.icon,
    this.count,
  });

  final String label;
  final IconData icon;

  /// Optionale Zahl rechts im Label (Kennzahlen). `null` blendet sie aus,
  /// `0` blendet sie ebenfalls aus - eine Null braucht keinen Platz.
  final int? count;
}

class _PillTabItem extends StatelessWidget {
  const _PillTabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final PillTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final showCount = (tab.count ?? 0) > 0;

    // Schluessel fuer den Test. Die Pillen tragen alle denselben Aufbau,
    // ohne Schluessel kaeme der Test nicht an die dritte Pille heran
    // (ListView baut nur die sichtbaren Kinder auf).
    final pillKey = ValueKey('pill_tab_${tab.label}');
    final countKey = ValueKey('pill_tab_count_${tab.label}');

    return Semantics(
      key: pillKey,
      container: true,
      selected: selected,
      button: true,
      label: showCount ? '${tab.label}. ${tab.count}' : tab.label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            // Die Pille ist der Hintergrund dieses Containers: fuellig bei
            // Auswahl, transparent sonst. AnimatedContainer weiter unten
            // faehrt die Farbe weich.
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(PillTabBar._pillRadius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(PillTabBar._pillRadius),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius:
                      BorderRadius.circular(PillTabBar._pillRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 18, color: fg),
                    const SizedBox(width: 7),
                    Text(
                      tab.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (showCount) ...[
                      const SizedBox(width: 6),
                      // Kennzahl als eigene Kachel, nicht im Text: so
                      // bleibt sie auch bei grosser Schrift lesbar.
                      Container(
                        key: countKey,
                        constraints: const BoxConstraints(minWidth: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : scheme.outline,
                          borderRadius: BorderRadius.circular(
                            PillTabBar._pillRadius,
                          ),
                        ),
                        child: Text(
                          '${tab.count}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
