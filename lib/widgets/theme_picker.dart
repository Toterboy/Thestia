import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/theme/app_theme.dart';

/// Farbschema-Auswahl: Kreise mit Vorschau + Label, ausgewählt mit Ring.
///
/// Wird in der Einrichtung (Schritt „Darstellung") und in den Einstellungen
/// genutzt, damit beide identisch funktionieren.
class ThemePicker extends StatelessWidget {
  const ThemePicker({
    required this.selectedName,
    required this.onChanged,
    super.key,
  });

  /// Name des aktiven [ThestiaTheme] (siehe settings.themeName).
  final String selectedName;

  final ValueChanged<ThestiaTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final theme in ThestiaTheme.values)
          _ThemeSwatch(
            theme: theme,
            selected: theme.name == selectedName,
            onTap: () => onChanged(theme),
          ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ThestiaTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${L10n.t(context, 'theme.colorScheme')} ${L10n.t(context, theme.labelKey)}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 78,
          height: 86,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor,
                  border: Border.all(
                    width: selected ? 3.5 : 1.5,
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 22)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                L10n.t(context, theme.labelKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
