import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/generated/terms_de.dart';
import 'package:thestia/generated/terms_en.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/legal_text_screen.dart';

/// Volltext der Nutzungsbedingungen, aus [kTermsDe] gerendert.
///
/// BEFUND (14.11.2026, Betreiber): "Die Nutzungsbedingungen funktionieren
/// in der App nicht." Vorher verlinkte die App auf die Webseite: das
/// braucht einen installierten Browser und eine erreichbare Seite, und
/// in der App stand selbst nichts. Jetzt steht der Text im Binary -
/// wie bei der Datenschutzerklärung, die Play ohnehin als Text in der
/// App verlangt.
///
/// Quelle ist `tool/make_terms.py` (dort stehen beide Sprachfassungen).
/// `python tool/make_terms_app.py` erzeugt daraus diese beiden Dateien;
/// dasselbe Skript erzeugt die Webseiten. App und Website können so
/// nicht auseinanderlaufen.
///
/// Die Sprache richtet sich nach der App-Sprache.
class TermsTextScreen extends ConsumerWidget {
  const TermsTextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(localeProvider).languageCode == 'en'
        ? kTermsEn
        : kTermsDe;

    return LegalTextScreen(
      blocks: blocks,
      title: L10n.t(context, 'privacy.termsTitle'),
      // Die Webfassung bleibt erreichbar - dort steht dieselbe Fassung
      // (beide entstehen aus tool/make_terms.py).
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://thestia.de/nutzungsbedingungen'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(L10n.t(context, 'privacy.termsWeb')),
          ),
        ),
      ),
    );
  }
}
