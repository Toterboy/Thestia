import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/startup_watchdog.dart';

/// Zeigt den Befund über einen gescheiterten Startversuch.
///
/// Der Zweck ist, den Nutzer ohne Computer zu einer brauchbaren
/// Information zu bringen. Ein Nutzer, der nur "Die App konnte nicht
/// gestartet werden" sieht, kann nichts tun; ein Nutzer, der den letzten
/// erreichten Schritt und den Fehlertext kopieren kann, schon.
///
/// Der Text ist absichtlich kopier- und teilbar, nicht nur lesbar: die
/// meisten können keinen Screenshot an sich selbst schicken, aber einen
/// Text in eine Nachricht kopieren und verschicken - das ist der Weg,
/// der ohne Werkzeug funktioniert.
class StartupFailureScreen extends StatelessWidget {
  const StartupFailureScreen({
    super.key,
    required this.failure,
    this.onDismiss,
  });

  final StartupFailure failure;

  /// Weiter, wenn der Start diesmal klappt. `null` heißt: nicht
  /// möglich, der Bildschirm bleibt stehen.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'startupFail.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.report_gmailerrorred_outlined,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'startupFail.heading'),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Kein Tripelcode, keine Rohdaten: der Nutzer soll eine
            // Frage beantworten koennen, nicht Debug-Ausgabe lesen.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Row(
                    label: L10n.t(context, 'startupFail.stepLabel'),
                    value: failure.step ??
                        L10n.t(context, 'startupFail.noStep'),
                  ),
                  if (failure.error != null) ...[
                    const SizedBox(height: 12),
                    _Row(
                      label: L10n.t(context, 'startupFail.errorLabel'),
                      value: failure.error!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, failure.diedBeforeDart
                  ? 'startupFail.explainEarly'
                  : 'startupFail.explainLate'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(L10n.t(context, 'startupFail.copy')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.ios_share),
              label: Text(L10n.t(context, 'startupFail.share')),
            ),
            if (onDismiss != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onDismiss,
                child: Text(L10n.t(context, 'startupFail.continue')),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              L10n.t(context, 'startupFail.hint'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    // Texte und Messenger VOR dem await holen: danach kann der Context
    // weg sein (Route gepoppt), und der Analyzer moniert zu Recht, ihn
    // dann noch zu benutzen.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copiedText = L10n.t(context, 'startupFail.copied');
    final report = failure.toReport();

    await Clipboard.setData(ClipboardData(text: report));
    messenger?.showSnackBar(
      SnackBar(
        content: Text(copiedText),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failedText = L10n.t(context, 'startupFail.shareFailed');
    final report = failure.toReport();
    try {
      await SharePlus.instance.share(
        ShareParams(text: report),
      );
    } catch (_) {
      // Teilen ist nicht verfuegbar (z. B. kein Empfaenger). Der
      // Kopierknopf ist der verlaessliche Weg.
      messenger?.showSnackBar(
        SnackBar(
          content: Text(failedText),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        SelectableText(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontFamily: 'monospace')),
      ],
    );
  }
}
