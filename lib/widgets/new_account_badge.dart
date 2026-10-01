import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';

/// Hinweis auf ein junges Konto.
///
/// Ein Hinweis, kein Beweis - auch echte neue Nutzer fallen darunter.
/// Er soll davor schuetzen, dass man dauerhaft von Accounts
/// angeschrieben wird, die es gerade erst gibt, ohne dabei ein
/// Erstellungsdatum offenzulegen.
///
/// Bewusst KEIN [Chip]: der Chip ist an dieser Stelle ein Fremdkoerper.
/// Er sitzt als pillfoermige Plakette mit eigener Schriftgroesse neben
/// dem Namen, wo bereits das Verifiziert-Badge steht. Zwei unterschiedlich
/// gewichtige Platten nebeneinander wuerden um die Aufmerksamkeit
/// konkurrieren, die dem Verifiziert-Badge gehoert.
///
/// Die Form folgt dem Verifiziert-Badge: gleiche Hoehe, gleicher
/// Abstand, gleiche Position in der Zeile - damit die Namenszeile bei
/// beiden Zustaenden gleich hoch bleibt und nichts springt.
class NewAccountBadge extends StatelessWidget {
  const NewAccountBadge({super.key, this.profile});

  /// Das Profil, dessen Kontoalter geprueft wird.
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    // Ohne Alter keine Anzeige: eine falsche Entwarnung waere
    // schaedlicher als ein fehlender Hinweis.
    if (p == null || !p.isRecentlyCreated) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Tooltip(
      message: L10n.t(context, 'profile.newAccountTooltip'),
      child: Semantics(
        // Als Text fuer Screenreader, nicht nur als Grafik.
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
