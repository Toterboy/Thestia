import 'package:flutter/material.dart';

/// Kennzahlen-Zeile fuer den Admin-Screen.
///
/// Der Admin-Bereich hat sechs Tabs, aber nur ZWEI davon erzeugen Arbeit
/// (Meldungen und Bugs). Vorher musste der Admin an einem Symbol mit
/// Ziffernpunkt erkennen, dass in einem Tab etwas liegt - dafuer musste er
/// alle sechs Tabs durchklicken.
///
/// Die Zeile beantwortet die Frage "wo muss ich hin" in einer Zeile, ohne
/// selbst Navigation zu uebernehmen: jede Kachel ist als Ganzes antippbar
/// und meldet [onTap]. Die Farbe unterscheidet "hier ist Arbeit" (error-
/// Container) von "nichts offen" (surface), damit die Prioritaet auch ohne
/// Zahl lesbar ist.
///
/// Warum Zaehler und nicht Badges an den Tabs: die Tabs sind sechs gleich
///rangige Kacheln, eine Kennzahl an einer davon wuerde behaupten, die
/// anderen waeren unwichtig. Ausserdem ist die Zeile lesbar, ohne dass der
/// Admin scrollen muss.
class AdminMetricRow extends StatelessWidget {
  const AdminMetricRow({
    super.key,
    required this.metrics,
  });

  final List<AdminMetric> metrics;

  /// Radius wie die Karten der App (24 an `SelectableTile`, `EmptyState`).
  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            Expanded(
              child: _MetricTile(
                metric: metrics[i],
                radius: _radius,
              ),
            ),
            if (i != metrics.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Eine Kennzahl: Wert, Label, optionale Zusatzzeile.
class AdminMetric {
  const AdminMetric({
    required this.label,
    required this.value,
    this.subtitle,
    this.urgent = false,
    this.onTap,
    this.semanticsLabel,
  });

  /// Kurzbezeichnung der Kennzahl (z. B. "Offene Meldungen").
  final String label;

  /// Der Zahlenwert als Text. Als String uebergeben, damit ein Wert wie
  /// "> 99" darstellbar bleibt, ohne eine eigene Formatierungslogik.
  final String value;

  /// Optionale zweite Zeile (z. B. "letzte 24 Stunden").
  final String? subtitle;

  /// `true` faerbt die Kachel als "hier liegt Arbeit". Nicht nur Deko:
  /// die Kennzahlen-Zeile muss auch bei farbloser Wahrnehmung erkennbar
  /// bleiben, daher bleibt die Zahl immer sichtbar.
  final bool urgent;

  /// Optionaler Tipp auf die Kachel (springt im Admin-Screen zum Tab).
  final VoidCallback? onTap;

  /// Ersetzt die automatisch gebaute Semantik, falls [value] kein reiner
  /// Zahlenwert ist (z. B. "> 99").
  final String? semanticsLabel;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.metric,
    required this.radius,
  });

  final AdminMetric metric;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = metric.urgent
        ? scheme.errorContainer.withValues(alpha: 0.45)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final fg = metric.urgent ? scheme.onErrorContainer : scheme.onSurface;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              // Tabellarische Ziffern: die Zahl springt nicht, wenn sie
              // sich aendert. Ohne das zappelt die Zeile bei jedem
              // Nachladen.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg.withValues(alpha: 0.8),
            ),
          ),
          if (metric.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              metric.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );

    final body = metric.onTap == null
        ? content
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: metric.onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
          );

    return Semantics(
      container: true,
      button: metric.onTap != null,
      label: metric.semanticsLabel ??
          '${metric.label}: ${metric.value}'
              '${metric.subtitle != null ? ', ${metric.subtitle}' : ''}',
      child: ExcludeSemantics(child: body),
    );
  }
}
