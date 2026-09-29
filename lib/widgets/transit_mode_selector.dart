import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';

/// Selbst gebaute Reichweiten-Auswahl fuer Transit Spark.
///
/// Ersetzt das Material-`SegmentedButton`, das nur zwei gleichwertige
/// Textsegmente zeigte. Die beiden Modi unterscheiden sich aber nicht
/// kosmetisch, sondern in der Signal-Schwelle
/// ([TransitMode.rssiThreshold]): `convention` akzeptiert nur Signale
/// staerker als -75 dBm, `transit` alles bis -100 dBm. Das war im
/// Segment-Button nicht erkennbar - der Nutzer konnte den Unterschied
/// nur an den RSSI-Zahlen unten ablesen.
///
/// Deshalb zeigt jede Option drei Ebenen: Icon-Badge, Name und eine
/// kurze Erklaerung, welcher Bereich gemeint ist. Die gewaehlte Option
/// ist zusaetzlich mit Haken und farbiger Kante markiert.
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

  @override
  Widget build(BuildContext context) {
    // Eine Option je Zeile: die Erklaerungstexte sind zwei bis drei
    // Zeilen lang und wuerden nebeneinander auf schmalen Geraeten
    // abgeschnitten.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in TransitMode.values) ...[
          _Option(
            mode: mode,
            selected: mode == value,
            enabled: enabled,
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

/// Eine einzelne waehlbare Option.
class _Option extends StatelessWidget {
  const _Option({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.title,
    required this.description,
    required this.thresholdLabel,
    required this.onTap,
  });

  final TransitMode mode;
  final bool selected;
  final bool enabled;
  final String title;
  final String description;
  final String thresholdLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final borderColor = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: 0.6);
    final background = selected
        ? scheme.primary.withValues(alpha: 0.10)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final titleColor =
        selected ? scheme.primary : scheme.onSurface;
    final muted = selected
        ? scheme.onSurface
        : scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      selected: selected,
      enabled: enabled,
      button: true,
      label: '$title. $description',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconBadge(
                        icon: mode.icon,
                        selected: selected,
                        scheme: scheme,
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
                                      color: titleColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted, height: 1.35),
                            ),
                            const SizedBox(height: 6),
                            _ThresholdChip(
                              label: thresholdLabel,
                              selected: selected,
                              scheme: scheme,
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

/// Icon in abgerundetem Quadrat, das den gewaehlten Zustand traegt.
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.selected,
    required this.scheme,
  });

  final IconData icon;
  final bool selected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        size: 21,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Kleines Label mit der konkreten RSSI-Schwelle.
///
/// Zeigt die Zahl an, damit der Unterschied zwischen den Modi nicht
/// nur behauptet, sondern nachlesbar ist.
class _ThresholdChip extends StatelessWidget {
  const _ThresholdChip({
    required this.label,
    required this.selected,
    required this.scheme,
  });

  final String label;
  final bool selected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
