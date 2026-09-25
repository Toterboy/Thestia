import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Sprachumschalter (DE/EN) in zwei Varianten:
///
/// - [compact] (Login-Screen): Translate-Icon mit KREIS-Hintergrund in
///   `primaryContainer` (passt sich automatisch an Light/Dark und die
///   jeweilige Farbwelt an), Tap öffnet ein Popup-Menü.
/// - Default (Einstellungen): Das GANZE Feld „Sprache" ist tappbar und
///   klappt nach unten auf; darunter wählt man zwischen Deutsch/Englisch.
class LanguageSwitch extends ConsumerStatefulWidget {
  const LanguageSwitch({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<LanguageSwitch> createState() => _LanguageSwitchState();
}

class _LanguageSwitchState extends ConsumerState<LanguageSwitch> {
  bool _expanded = false;

  String _label(BuildContext context, String code) =>
      code == 'de'
          ? L10n.t(context, 'language.german')
          : L10n.t(context, 'language.english');

  void _select(String code) {
    saveLocale(ref, Locale(code));
    // Nach der Auswahl zuklappen, damit das Feld kompakt bleibt.
    if (mounted) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final current = locale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    if (widget.compact) {
      // Login: runder Button in Primärfarbe (gleicher Look wie der
      // "Einloggen"-FilledButton), folgt Light/Dark und der Farbwelt.
      // WICHTIG: `child` statt `icon` nutzen - der icon-Weg wickelt das
      // Widget in ein IconButton, das es auf iconSize (~24 px) zwingt,
      // wodurch der Kreis SCHRUMPFT und das Symbol übergroß wirkt.
      return PopupMenuButton<String>(
        tooltip: L10n.t(context, 'settings.language'),
        position: PopupMenuPosition.under,
        initialValue: current,
        onSelected: _select,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: EdgeInsets.zero,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.translate,
            size: 22,
            color: scheme.onPrimary,
          ),
        ),
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            value: 'de',
            checked: current == 'de',
            child: Text(L10n.t(context, 'language.german')),
          ),
          CheckedPopupMenuItem(
            value: 'en',
            checked: current == 'en',
            child: Text(L10n.t(context, 'language.english')),
          ),
        ],
      );
    }

    // Einstellungen: Ganzes Feld, klappt nach unten auf.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.translate, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    L10n.t(context, 'settings.language'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _label(context, current),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            children: [
              for (final code in const ['de', 'en'])
                ListTile(
                  leading: Icon(
                    current == code
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: current == code ? scheme.primary : null,
                  ),
                  title: Text(_label(context, code)),
                  onTap: () => _select(code),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
