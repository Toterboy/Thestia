import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/widgets/app_logo.dart';

/// Kurzer Willkommensscreen nach erfolgreicher Registrierung (v0.9.1).
///
/// Wird EINMALIG nach der E-Mail-Bestätigung gezeigt (Flag
/// `signupWelcomeSeen`), danach geht es direkt in die Einrichtung
/// (der Router erzwingt die offenen Setup-Schritte automatisch).
/// Bei Kill während des Screens greift beim nächsten Start direkt die
/// Einrichtung - der Screen wird nie wiederholt.
class SignupWelcomeScreen extends ConsumerWidget {
  const SignupWelcomeScreen({super.key});

  Future<void> _continue(BuildContext context, WidgetRef ref) async {
    await ref.read(settingsProvider.notifier).markSignupWelcomeSeen();
    if (context.mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 120),
              const SizedBox(height: 32),
              Text(
                L10n.t(context, 'signup.title'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'signup.body'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _continue(context, ref),
                child: Text(L10n.t(context, 'signup.start')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
