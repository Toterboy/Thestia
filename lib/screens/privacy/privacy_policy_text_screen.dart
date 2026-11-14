import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thestia/generated/privacy_policy_de.dart';
import 'package:thestia/generated/privacy_policy_en.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/legal_text_screen.dart';

/// Volltext der Datenschutzerklärung, aus [kPrivacyPolicyDe] gerendert.
///
/// Google Play verlangt die Erklärung an zwei getrennten Stellen: als
/// URL im Store-Eintrag **und** als Text innerhalb der App selbst
/// ("a privacy policy link or text within the app itself"). Der Text
/// steht deshalb hier im Binary und wird nicht aus einer URL
/// nachgeladen. Eine URL kann falsch, verschoben oder nicht erreichbar
/// sein; der Text nicht.
///
/// Quelle ist `docs/DATENSCHUTZ.md` (deutsch) und
/// `docs/DATENSCHUTZ_EN.md` (englisch). Wird eine davon geändert,
/// erzeugt `python tool/make_privacy_policy.py` beide Ausgaben neu:
/// diese Texte, `passkey-assets/datenschutz.html` und
/// `passkey-assets/en/datenschutz.html` für den Store-Eintrag. So können
/// App und Store nicht auseinanderlaufen.
///
/// Die Sprache richtet sich nach der App-Sprache (NUTZERWUNSCH
/// 03.11.2026: alles auf Deutsch und Englisch). Wer die App auf
/// Englisch stellt, bekommt also auch die englische Erklärung - und
/// umgekehrt.
class PrivacyPolicyTextScreen extends ConsumerWidget {
  const PrivacyPolicyTextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Die zur App-Sprache passende Fassung.
    final blocks = ref.watch(localeProvider).languageCode == 'en'
        ? kPrivacyPolicyEn
        : kPrivacyPolicyDe;

    return LegalTextScreen(
      blocks: blocks,
      title: L10n.t(context, 'privacy.policyTitle'),
    );
  }
}
