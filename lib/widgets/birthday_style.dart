import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Geburtstags-Stile (Nutzerwunsch: schick, nicht kitschig): 5 wählbare
/// Designs für das Profil am Geburtstag. Der Stil wirkt NUR am Geburtstag
/// (Tag/Monat des Geburtsdatums) - sonst ist das Profil unverändert.
///
/// Slugs (serverseitig per CHECK erzwungen, Migration 115):
/// classic, midnight, sage, rose, mono.
class BirthdayStyle {
  const BirthdayStyle._();

  static const List<String> values = [
    'classic',
    'midnight',
    'sage',
    'rose',
    'mono',
  ];

  static String labelKey(String style) => 'birthday.style.$style';

  static bool isKnown(String style) => values.contains(style);

  static String orDefault(String? style) =>
      (style != null && isKnown(style)) ? style : values.first;
}

/// Vorschaukarte für einen Geburtstags-Stil: MINI-PROFIL-SCREEN-VORSCHAU
/// (NUTZERWUNSCH: "ein richtiger Profilscreen" + "Themes besonders") -
/// dezent, kein Kitsch: Avatar-Kreis, Namenszeile, Interessen-Chips und
/// ein stil-eigener EFFEKTRAND (metallic Schein bei Midnight/Mono,
/// sanftes Schimmern bei Rose/Sage/Gold). Der Effekt lebt IM Stil und
/// ist nie nur eine Farbänderung.
class BirthdayStylePreview extends StatelessWidget {
  const BirthdayStylePreview({
    required this.style,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = _foregroundFor(style, context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 128,
        decoration: BoxDecoration(
          gradient: _gradientFor(style, context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.4),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: _glowFor(style, context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini-Profil-Kopf (wie ein Profil-Screen gestaucht).
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                gradient: _headerWashFor(style, context),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fg.withValues(alpha: 0.25),
                      border: Border.all(
                          color: fg.withValues(alpha: 0.6)),
                    ),
                    child: Icon(Icons.person, size: 17, color: fg),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name-Zeile (weicher Balken).
                        Container(
                          width: 52,
                          height: 5,
                          decoration: BoxDecoration(
                            color: fg.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 38,
                          height: 3,
                          decoration: BoxDecoration(
                            color: fg.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.cake_outlined,
                    size: 15,
                    color: fg.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Interessen-Zeile (zwei Chips andeuten).
                  Row(
                    children: [
                      _miniChip(fg),
                      const SizedBox(width: 4),
                      _miniChip(fg),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _line(fg, 64, 0.35),
                  const SizedBox(height: 4),
                  _line(fg, 46, 0.25),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, BirthdayStyle.labelKey(style)),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: fg,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kleine Interessen-Chip-Andeutung in der Vorschau.
  Widget _miniChip(Color fg) => Container(
        width: 30,
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: fg.withValues(alpha: 0.22),
          border: Border.all(color: fg.withValues(alpha: 0.4)),
        ),
      );

  /// Feiner Balken (Platzhalter für Textzeilen).
  Widget _line(Color fg, double w, double alpha) => Container(
        width: w,
        height: 3,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  /// Dezente Verläufe je Stil (Light/Dark-tauglich über Scheme-Farben
  /// gemischt mit Stil-Akzent).
  static LinearGradient _gradientFor(String style, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerHighest;
    switch (style) {
      case 'midnight':
        return const LinearGradient(
          colors: [Color(0xFF1A2340), Color(0xFF2E3E6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'sage':
        return LinearGradient(
          colors: [const Color(0xFF9CAF88), surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'rose':
        return LinearGradient(
          colors: [const Color(0xFFE8B4B8), surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'mono':
        return const LinearGradient(
          colors: [Color(0xFF2B2B2B), Color(0xFF5A5A5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'classic':
      default:
        return LinearGradient(
          colors: [const Color(0xFFC9A227).withValues(alpha: 0.55), surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  /// Kopf-Waschung (leichter Schein im Profil-Kopfbereich, je Stil
  /// anders - Midnight/Mono dunkler Schein, Rose/Sage/Gold warm).
  static LinearGradient _headerWashFor(String style, BuildContext context) {
    switch (style) {
      case 'midnight':
        return const LinearGradient(
          colors: [Color(0x33B39DDB), Color(0x111A2340)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 'mono':
        return const LinearGradient(
          colors: [Color(0x33FFFFFF), Color(0x112B2B2B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 'rose':
        return const LinearGradient(
          colors: [Color(0x44FFD9E0), Color(0x22E8B4B8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 'sage':
        return const LinearGradient(
          colors: [Color(0x44D7E4C7), Color(0x119CAF88)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 'classic':
      default:
        return const LinearGradient(
          colors: [Color(0x44F3DFA2), Color(0x11C9A227)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
    }
  }

  /// Stil-eigener Effektrand (NUTZERWUNSCH "Themes besonders, mit
  /// Effekten"): Midnight/Mono erhalten einen metallischen Doppelschein,
  /// Rose einen warmen Rosé-Glow, Sage einen erdigen Schimmer, Gold
  /// (classic) einen zarten goldenen Schein. Subtil - nie kitschig.
  static List<BoxShadow> _glowFor(String style, BuildContext context) {
    switch (style) {
      case 'midnight':
        return [
          BoxShadow(
              color: const Color(0xFF6C7BFF).withValues(alpha: 0.28),
              blurRadius: 10,
              spreadRadius: 1),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14),
        ];
      case 'mono':
        return [
          BoxShadow(
              color: Colors.white.withValues(alpha: 0.18),
              blurRadius: 8,
              spreadRadius: 1),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12),
        ];
      case 'rose':
        return [
          BoxShadow(
              color: const Color(0xFFE8B4B8).withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: 1),
        ];
      case 'sage':
        return [
          BoxShadow(
              color: const Color(0xFF9CAF88).withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 1),
        ];
      case 'classic':
      default:
        return [
          BoxShadow(
              color: const Color(0xFFC9A227).withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 1),
        ];
    }
  }

  static Color _foregroundFor(String style, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (style) {
      case 'midnight':
      case 'mono':
        return Colors.white;
      default:
        return scheme.onSurface;
    }
  }
}

/// Auswahl-Zeile für die 5 Geburtstags-Stile (Einrichtung + Bearbeiten).
class BirthdayStylePicker extends StatelessWidget {
  const BirthdayStylePicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'birthday.styleTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          L10n.t(context, 'birthday.pickHint'),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final style in BirthdayStyle.values)
              BirthdayStylePreview(
                style: style,
                selected: BirthdayStyle.orDefault(selected) == style,
                onTap: () => onSelected(style),
              ),
          ],
        ),
      ],
    );
  }
}

/// Dezenter Geburtstags-Chip ("Alles Gute zum Geburtstag!", kein Kitsch:
/// kleine Torte + Text in einer Pill).
class BirthdayChip extends StatelessWidget {
  const BirthdayChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cake_outlined,
              size: 14, color: scheme.onTertiaryContainer),
          const SizedBox(width: 6),
          Text(
            L10n.t(context, 'birthday.todayTitle'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Dezenter Stil-Rahmen fürs Profilbild am Geburtstag: 3 px Verlauf als
/// Border um das Kind-Widget (kein Konfetti, kein Kitsch).
class BirthdayStyleFrame extends StatelessWidget {
  const BirthdayStyleFrame({
    required this.style,
    required this.active,
    required this.child,
    required this.borderRadius,
    super.key,
  });

  final String style;
  final bool active;
  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: BirthdayStylePreview._gradientFor(
            BirthdayStyle.orDefault(style), context),
        borderRadius: BorderRadius.circular(borderRadius + 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
    );
  }
}
