import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Screen fuer "dieses Build ist zu alt".
///
/// Wird gezeigt, wenn der installierte Build unter dem serverseitigen
/// Mindest-Build liegt (`app_config.min_app_version_build`). Zwei
/// Faelle:
///
///   * **Beim Start** (main.dart): der Wert stand schon im lokalen
///     Cache. Der Screen blockiert dann - ein zu alter Build darf
///     nicht weiterlaufen.
///   * **Waehrend der App** (app.dart): der Server ist strenger
///     geworden, seitdem der Cache gefuellt wurde. Der Hinweis
///     erscheint dann als Deckschicht ueber der laufenden App.
///
/// [onDismiss] ist nur im zweiten Fall gesetzt: dort kann der Nutzer
/// die Deckschicht wegtippen und weiterarbeiten. Beim Start ist der
/// Screen eine Sperre - deshalb bleibt "Trotzdem fortfahren" dort
/// ohne Wirkung.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({this.onDismiss, super.key});

  /// Wird aufgerufen, wenn der Nutzer "Trotzdem fortfahren" waehlt.
  /// `null` = der Bildschirm ist eine Sperre (Startfall).
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.system_update_alt,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  L10n.t(context, 'update.required'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.t(context, 'update.body'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.shop_outlined),
                  label: Text(L10n.t(context, 'update.now')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onDismiss ?? () {},
                  child: Text(L10n.t(context, 'update.later')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    final uris = [
      Uri.parse('market://details?id=com.thestia.app'),
      Uri.parse(
          'https://play.google.com/store/apps/details?id=com.thestia.app'),
    ];
    for (final uri in uris) {
      try {
        // Nur den ersten Eintrag versuchen, der ueberhaupt startbar
        // ist - sonst tappt der Nutzer auf einen Store, den es auf
        // dem Geraet nicht gibt.
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // naechste Option versuchen
      }
    }
  }
}
