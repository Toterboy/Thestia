import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/guardian_provider.dart';
import 'package:thestia/widgets/buttons.dart';

/// Der Screen zum 18. Geburtstag.
///
/// Wer bei der Registrierung 16 oder 17 war, hatte eine elterliche
/// Freigabe. Mit 18 entscheidet der Jugendliche selbst:
///
///   * Zugriff beenden,
///   * fuer 1 bis 6 Monate weiter behalten,
///   * erstmal weiter behalten.
///
/// Der Screen erscheint einmalig. Bis zur Entscheidung bleibt der
/// Zugriff bestehen - das ist die Entscheidung des Betreibers
/// ("wo man den Zugriff der Eltern entfernen, fuer 1-6 Monate weiter
/// behalten oder erstmal weiter behalten kann").
class GuardianTransitionScreen extends ConsumerStatefulWidget {
  const GuardianTransitionScreen({super.key});

  @override
  ConsumerState<GuardianTransitionScreen> createState() =>
      _GuardianTransitionScreenState();
}

class _GuardianTransitionScreenState
    extends ConsumerState<GuardianTransitionScreen> {
  int _monate = 3;
  bool _busy = false;

  Future<void> _entscheiden(String policy, {int? monate}) async {
    setState(() => _busy = true);
    final result = await ref
        .read(guardianProvider.notifier)
        .setAccessPolicy(policy, graceMonths: monate);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isOk) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'guardian.errorGeneric')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'guardian.transitionTitle')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.t(context, 'guardian.transitionText'),
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 28),

              // 1) Beenden
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _entscheiden('ended'),
                child: Text(L10n.t(context, 'guardian.transitionEnd')),
              ),
              const SizedBox(height: 20),

              // 2) Nachfrist
              Text(
                L10n.tf(context, 'guardian.graceLabel', {
                  'months': '$_monate',
                }),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: _monate.toDouble(),
                min: 1,
                max: 6,
                divisions: 5,
                label: '$_monate',
                onChanged: (v) => setState(() => _monate = v.round()),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _entscheiden('grace', monate: _monate),
                child: Text(
                  L10n.tf(context, 'guardian.transitionGrace', {
                    'months': '$_monate',
                  }),
                ),
              ),
              const SizedBox(height: 20),

              // 3) Weiter behalten
              PrimaryButton(
                label: L10n.t(context, 'guardian.transitionKeep'),
                loading: _busy,
                onPressed: _busy ? null : () => _entscheiden('indefinite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
