import 'package:flutter/material.dart';

import 'package:thestia/theme/app_theme.dart';

/// Zeigt Interessen als abgerundete "Chips" an.
class InterestChips extends StatelessWidget {
  const InterestChips({
    required this.interests,
    this.highlighted = false,
    super.key,
  });

  final List<String> interests;

  /// true = gemeinsame Interessen (hervorgehoben, mit Herz).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: interests
          .map(
            (i) => Chip(
              label: Text(i),
              avatar: highlighted
                  ? Icon(
                      Icons.favorite,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    )
                  : null,
              backgroundColor: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: highlighted
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: highlighted ? FontWeight.w600 : null,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Visueller Distanz-/Info-Badge.
class InfoBadge extends StatelessWidget {
  const InfoBadge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// Platzhalter-Bild für den Blind Mode (kein Foto sichtbar).
class BlindPhotoPlaceholder extends StatelessWidget {
  const BlindPhotoPlaceholder({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final blind = Theme.of(context).extension<BlindModeTheme>() ??
        const BlindModeTheme(placeholderColor: Color(0xFFE1E1EC));
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            blind.placeholderColor,
            blind.placeholderColor.withValues(alpha: 0.6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off, size: 48, color: Colors.white70),
            const SizedBox(height: 8),
            Text(
              label ?? 'Foto nach Match sichtbar',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

