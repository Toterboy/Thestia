import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';

/// Hinweis auf ein junges Konto.
///
/// Ein Hinweis, kein Beweis - auch echte neue Nutzer fallen darunter.
/// Er soll davor schützen, dass man dauerhaft von Accounts
/// angeschrieben wird, die es gerade erst gibt, ohne dabei ein
/// Erstellungsdatum offenzulegen.
///
/// Bewusst KEIN [Chip]: der Chip ist an dieser Stelle ein Fremdkörper.
/// Er sitzt als pillförmige Plakette mit eigener Schriftgrösse neben
/// dem Namen, wo bereits das Verifiziert-Badge steht. Zwei unterschiedlich
/// gewichtige Platten nebeneinander würden um die Aufmerksamkeit
/// konkurrieren, die dem Verifiziert-Badge gehört.
///
/// Die Form folgt dem Verifiziert-Badge: gleiche Höhe, gleicher
/// Abstand, gleiche Position in der Zeile - damit die Namenszeile bei
/// beiden Zuständen gleich hoch bleibt und nichts springt.
class NewAccountBadge extends StatelessWidget {
  const NewAccountBadge({super.key, this.profile});

  /// Das Profil, dessen Kontoalter geprüft wird.
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    // Ohne Alter keine Anzeige: eine falsche Entwarnung wäre
    // schädlicher als ein fehlender Hinweis.
    if (p == null || !p.isRecentlyCreated) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Tooltip(
      message: L10n.t(context, 'profile.newAccountTooltip'),
      child: Semantics(
        // Als Text für Screenreader, nicht nur als Grafik.
        label: L10n.t(context, 'profile.newAccountBadge'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            L10n.t(context, 'profile.newAccountBadge'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
