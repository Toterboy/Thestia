import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';

/// Fallback-Fehlerseite für unbekannte/unpassende Routen.
///
/// Zeigt eine freundliche Meldung und einen Button, der den Nutzer
/// abhängig vom Auth-Status sinnvoll weiterleitet (Login bzw. Home).
class ErrorScreen extends ConsumerWidget {
  const ErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: Colors.redAccent),
                const SizedBox(height: 24),
                Text(
                  L10n.t(context, 'error.notFoundTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.t(context, 'error.notFoundBody'),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
FilledButton.icon(
                  icon: const Icon(Icons.home),
                  label: Text(L10n.t(context, 'error.goHome')),
                  onPressed: () {
                    // Auth-/Settings-Status zum Klick-Zeitpunkt frisch lesen,
                    // damit die Zielroute immer korrekt bestimmt wird -
                    // unabhängig davon, wie der Nutzer auf dieser Seite
                    // gelandet ist.
                    final loggedIn =
                        ref.read(authProvider).valueOrNull ?? false;
                    final introSeen = ref.read(settingsProvider).introSeen;

                    // Je nach Status zur passenden Einstiegsseite. Die
                    // Redirect-Logik im Router holt eingeloggte Nutzer bei
                    // Bedarf automatisch zum nächsten offenen Setup-Schritt.
                    final String target;
                    if (loggedIn) {
                      target = AppRoutes.home;
                    } else {
                      target = introSeen ? AppRoutes.login : AppRoutes.welcome;
                    }
                    debugPrint('[ErrorScreen] Button gedrückt, navigiere zu: $target');
                    context.go(target);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

