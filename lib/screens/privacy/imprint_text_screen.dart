import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/generated/imprint_de.dart';
import 'package:thestia/generated/imprint_en.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/legal_text_screen.dart';

/// Volltext des Impressums, aus [kImprintDe] gerendert.
///
/// BEFUND (20.11.2026, Betreiber): "Das Impressum in der App
/// funktioniert nicht." Die App verlinkte auf
/// `https://thestia.de/impressum`. Diese Domain ist ein VERIFIZIERTER
/// APP-LINK (assetlinks.json + `android:autoVerify` im Manifest):
/// Android öffnet einen solchen Link in der App selbst, nicht im
/// Browser. Die App bekam also ihren eigenen Link und zeigte nichts.
///
/// Wie bei den Nutzungsbedingungen (14.11.2026) steht der Text jetzt
/// im Binary. Quelle ist die Webfassung
/// (`passkey-assets/impressum.html`); `python tool/web/make_imprint_app.py`
/// erzeugt daraus die beiden Sprachfassungen - App und Website können
/// so nicht auseinanderlaufen.
///
/// Die Sprache richtet sich nach der App-Sprache.
class ImprintTextScreen extends ConsumerWidget {
  const ImprintTextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final english = ref.watch(localeProvider).languageCode == 'en';
    final blocks = english ? kImprintEn : kImprintDe;

    return LegalTextScreen(
      blocks: blocks,
      title: L10n.t(context, 'privacy.imprintTitle'),
      // Die Webfassung bleibt erreichbar - aber über auth.thestia.de.
      //
      // WARUM NICHT thestia.de: Diese Domain ist der App-Link (siehe
      // oben) - der Button würde die App selbst öffnen statt der
      // Seite. auth.thestia.de ist nicht für die App verifiziert,
      // dort öffnet sich der Browser.
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(
                english
                    ? 'https://auth.thestia.de/en/impressum'
                    : 'https://auth.thestia.de/impressum',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(L10n.t(context, 'privacy.imprintWeb')),
          ),
        ),
      ),
    );
  }
}
