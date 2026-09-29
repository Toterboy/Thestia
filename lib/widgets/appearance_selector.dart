import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Selbst gebaute Auswahl für den Erscheinungsmodus (Hell / System /
/// Dunkel).
///
/// Ersetzt drei [SelectableTile]-Radiozeilen in den Einstellungen.
///
/// Warum das nicht einfach ein SegmentedButton bleibt: Hell/System/Dunkel
/// sind keine gleichwertigen Textsegmente. "System" ist die Voreinstellung
/// und folgt dem Gerät, "Hell" und "Dunkel" erzwingen etwas. In einer
/// Liste aus drei gleich aussehenden Radiozeilen ist das nicht
/// unterscheidbar, und die Option, die man NICHT anfassen muss, sieht aus
/// wie die, die man anfassen muss.
///
/// Der Aufbau entspricht bewusst [TransitModeSelector] (Icon-Badge,
/// Titel, Erklärung, Haken): in der Einrichtung stehen beide Auswahlen
/// untereinander, und unterschiedliche Widget-Familien an gleichwertigen
/// Stellen wirken wie ein Unfall.
class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Aktiver Modus: 'light' | 'system' | 'dark'.
  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _order = ['light', 'system', 'dark'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in _order) ...[
          _AppearanceOption(
            mode: mode,
            selected: mode == value,
            title: L10n.t(context, 'appearance.$mode'),
            description: L10n.t(context, 'appearanceDesc.$mode'),
            onTap: () => onChanged(mode),
          ),
          if (mode != _order.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.mode,
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  static const Map<String, IconData> _icons = {
    'light': Icons.light_mode_outlined,
    'system': Icons.brightness_auto_outlined,
    'dark': Icons.dark_mode_outlined,
  };

  /// Kleiner Vorschau-Kasten: hell/verlaufend/dunkel. Zeigt die Wahl
  /// optisch an, ohne den Text erklären zu müssen.
  static const Map<String, List<Color>> _preview = {
    'light': [Color(0xFFFFF8FA), Color(0xFFF3E6EE)],
    'system': [Color(0xFFFFF8FA), Color(0xFF2B1620)],
    'dark': [Color(0xFF2B1620), Color(0xFF150A10)],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = _icons[mode] ?? Icons.brightness_auto_outlined;
    final colors = _preview[mode] ?? _preview['system']!;

    final borderColor = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: 0.6);
    final background = selected
        ? scheme.primary.withValues(alpha: 0.10)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final titleColor = selected ? scheme.primary : scheme.onSurface;
    final muted = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      selected: selected,
      button: true,
      label: '$title. $description',
      child: ExcludeSemantics(
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
              onTap: () {
                // Gleiches Optionstipp bleibt ohne Haptik, wie beim
                // TransitModeSelector.
                if (!selected) HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _Preview(colors: colors, selected: selected),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon,
                                  size: 17, color: selected ? scheme.primary : muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: titleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_circle,
                                    size: 18, color: scheme.primary),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, height: 1.35),
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
    );
  }
}

/// Mini-Vorschau des jeweiligen Erscheinungsbilds als Verlaufskachel.
class _Preview extends StatelessWidget {
  const _Preview({required this.colors, required this.selected});

  final List<Color> colors;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(
          width: selected ? 2 : 1,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}
