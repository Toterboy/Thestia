import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';

/// KI-Herkunfts-Badge (Nutzerwunsch Transparenz): Zwei klar
/// unterschiedliche Batches für lokale vs. Drittanbieter-KI.
///
/// - [AiBadge.local]: On-Device-KI (z. B. Altersschätzung, Bildprüfung
///   per gebündeltem ONNX-Modell) - keine Daten verlassen das Gerät.
/// - [AiBadge.cloud]: Cloud-KI über Drittanbieter (z. B. HuggingFace) -
///   Daten werden zur Prüfung an einen externen Dienst gesendet.
class AiBadge extends StatelessWidget {
  /// Kompakter Standard-Badge (lokale KI) mit explizitem Sprachcode -
  /// verwendet in Dialog-Titeln (z. B. NSFW-Befund, lokale Prüfung).
  const AiBadge({required this.languageCode, super.key})
      : _local = true,
        _compact = true;

  const AiBadge.local({super.key})
      : languageCode = null,
        _local = true,
        _compact = false;

  const AiBadge.cloud({super.key})
      : languageCode = null,
        _local = false,
        _compact = false;

  const AiBadge.localCompact({super.key})
      : languageCode = null,
        _local = true,
        _compact = true;

  const AiBadge.cloudCompact({super.key})
      : languageCode = null,
        _local = false,
        _compact = true;

  /// Expliziter Sprachcode für den Badge-Text (null = Kontext-Locale).
  final String? languageCode;

  final bool _local;
  final bool _compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = languageCode == 'en'
        ? (_local ? 'On-device AI' : 'Cloud AI')
        : L10n.t(
            context, _local ? 'ai.localBadge' : 'ai.cloudBadge');
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: _compact ? 6 : 8, vertical: _compact ? 2 : 4),
      decoration: BoxDecoration(
        color: _local
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: _local
            ? null
            : Border.all(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _local ? Icons.memory_outlined : Icons.cloud_outlined,
            size: _compact ? 12 : 14,
            color: _local
                ? scheme.onTertiaryContainer
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: (_compact
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(
              color: _local
                  ? scheme.onTertiaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
