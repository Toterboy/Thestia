import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';

/// Reichweiten-Auswahl fuer Transit Spark.
///
/// Zwei Modi, und sie unterscheiden sich nicht kosmetisch: `transit`
/// nimmt alles bis -100 dBm auf, `convention` nur Signale staerker als
/// -75 dBm. Genau DAS ist die Entscheidung, die der Nutzer trifft -
/// "im Vorbeigehen" gegen "nur die Person direkt neben mir".
///
/// Deshalb ist die Signalschwelle das fuehrende Element der Kachel und
/// nicht eine Zeile Kleingedrucktes: fuenf Balken zeigen, wie stark ein
/// Signal sein muss, damit es diese Kachel zaehlt. Die beiden Modi
/// liefern 1 und 4 von 5 Balken - der Unterschied ist damit optisch
/// sofort da, ohne einen Zahlenwert vergleichen zu muessen.
///
/// Das frueherige Layout hatte den Wert als kleinen Chip unter dem
/// Erklaerungstext und markierte die Auswahl fuenffach (2-px-Rand,
/// Hintergrund, Titelfarbe, gefuelltes Icon-Feld, Haken). Fuenf
/// Signale fuer eine binaere Entscheidung sind zwei zuviel; jetzt
/// sind es Rand und Fuellung.
class TransitModeSelector extends StatelessWidget {
  const TransitModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final TransitMode value;
  final ValueChanged<TransitMode> onChanged;
  final bool enabled;

  /// Eckenradius der Kacheln. 24 ist der Radius, den die App an
  /// Karten, `SelectableTile` und Eintragszeilen benutzt - die
  /// vorherigen 14 waren die einzige Stelle im Projekt mit diesem Wert.
  static const double _radius = 24;

  /// Anzahl der gefuellten Balken (von [bars]) fuer eine RSSI-Schwelle.
  ///
  /// Oeffentlich, weil das der eigentliche Inhalt des Widgets ist: die
  /// beiden Modi unterscheiden sich fuer den Nutzer nur dadurch, dass
  /// hier 1 und 4 Balken stehen. Die Abbildung ist aus der Schwelle
  /// abgeleitet und nicht fest verdrahtet, damit ein geaenderter
  /// Grenzwert die Anzeige mitzieht.
  ///
  /// -100 dBm (Grenze der normalen Reichweite) -> 1 von 5,
  /// -60 dBm (voller Empfang) -> 5 von 5.
  static int filledBars(int rssiThreshold) {
    final t = ((rssiThreshold + 100) / 40).clamp(0.0, 1.0);
    return 1 + (t * 4).round();
  }

  /// Balken gesamt in der Schwellenanzeige.
  static const int bars = 5;

  @override
  Widget build(BuildContext context) {
    // Eine Option je Zeile: die Erklaerungstexte sind zwei bis drei
    // Zeilen lang und wuerden nebeneinander abgeschnitten.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in TransitMode.values) ...[
          _RangeCard(
            mode: mode,
            selected: mode == value,
            enabled: enabled,
            radius: _radius,
            title: L10n.t(context, mode.labelKey),
            description: L10n.t(context, 'transit.modeDesc.${mode.value}'),
            thresholdLabel: L10n.tf(
                context, 'transit.rssiValue', {'value': '${mode.rssiThreshold}'}),
            onTap: () => onChanged(mode),
          ),
          if (mode != TransitMode.values.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.radius,
    required this.title,
    required this.description,
    required this.thresholdLabel,
    required this.onTap,
  });

  final TransitMode mode;
  final bool selected;
  final bool enabled;
  final double radius;
  final String title;
  final String description;
  final String thresholdLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Auswahl: Rand + Fuellung. Beide aus dem Theme, keine
    // Markenfarben im Widget.
    final borderColor =
        selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6);
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : scheme.surface;

    return Semantics(
      container: true,
      selected: selected,
      enabled: enabled,
      button: true,
      label: '$title. $description. $thresholdLabel',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: borderColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: enabled
                    ? () {
                        // Gleiches Optionstipp bleibt ohne Rueckmeldung
                        // und ohne Haptik - nur ein echter Wechsel
                        // bestaetigt die Auswahl.
                        if (!selected) HapticFeedback.selectionClick();
                        onTap();
                      }
                    : null,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ModeBadge(
                        icon: mode.icon,
                        selected: selected,
                        radius: radius,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _Threshold(
                              filled:
                                  TransitModeSelector.filledBars(mode.rssiThreshold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon in einem abgerundeten Feld, das den gewaehlten Zustand traegt.
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({
    required this.icon,
    required this.selected,
    required this.radius,
  });

  final IconData icon;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        // 16 ist der Innenradius der App (Snackbars, Menues, Textfelder).
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        size: 22,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Die Signalschwelle als fuenfstufiger Balken plus Zahl.
///
/// Der Zahlenwert bleibt ein eigener Text, damit er fuer Screenreader
/// und Tests als Text auffindbar bleibt - der Zahler ist aber nicht
/// mehr in einem Chip versteckt, sondern steht als Klartext neben den
/// Balken.
/// Die gefuellten Balken einer Schwelle.
  ///
  /// Ohne Zahlenwert. "Signal ab -100 dBm" sagt einem Nutzer nichts -
  /// die Einheit gehoert zu Funktechnik, nicht zu einer Dating-App. Die
  /// Balken zeigen dasselbe Verhaeltnis und brauchen keine Uebersetzung:
  /// mehr Balken = staerkeres Signal noetig = weniger Reichweite.
  ///
  /// Der Wert bleibt in der Semantics-Beschreibung der Kachel (oben im
  /// `Semantics(... label: ...)`), damit Screenreader ihn vorlesen. Er
  /// ist nur nicht mehr sichtbar.
  class _Threshold extends StatelessWidget {
  const _Threshold({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      key: const Key('transit-threshold-bars'),
      children: [
        for (var i = 0; i < TransitModeSelector.bars; i++)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 6,
              // Aufsteigend: die unteren Baenke kurz, der oberste lang.
              height: 7.0 + i * 3.0,
              decoration: BoxDecoration(
                color: i < filled
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
