import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/l10n/app_strings.dart';

/// Screen mit den Community-Regeln (Netiquette) der App.
/// Oeffentliche Kinderschutz-Seite (Play Child Safety Standards).
///
/// Play verlangt fuer Dating-, Social- und Random-Chat-Apps einen
/// oeffentlich erreichbaren Bereich mit: Verbot von Kindesmissbrauch,
/// benannter Kontaktperson und beschriebenem Meldeweg. Die Seite
/// liegt statisch bei Netlify neben der Datenschutz-Erklaerung.
const String kChildSafetyUrl = 'https://auth.thestia.de/kinderschutz';

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  /// 6 Paragraphen als L10n-Keys (cg.0 bis cg.5) - zweisprachig DE/EN.
  List<({String titleKey, String bodyKey})> _paragraphs() => [
        (titleKey: 'cg.0.title', bodyKey: 'cg.0.body'),
        (titleKey: 'cg.1.title', bodyKey: 'cg.1.body'),
        (titleKey: 'cg.2.title', bodyKey: 'cg.2.body'),
        (titleKey: 'cg.3.title', bodyKey: 'cg.3.body'),
        (titleKey: 'cg.4.title', bodyKey: 'cg.4.body'),
        (titleKey: 'cg.5.title', bodyKey: 'cg.5.body'),
        // v0.10.0: Play verlangt fuer Dating- und Random-Chat-Apps ein
        // AUSDRUECKLICHES Verbot von Kindesmissbrauch (CSAE/CSAM) in den
        // veroeffentlichten Standards. Fehlt es dort, ist das ein
        // Verstoss gegen die Child Safety Standards - unabhaengig von der
        // Altersfreigabe.
        (titleKey: 'cg.6.title', bodyKey: 'cg.6.body'),
      ];

  @override
  Widget build(BuildContext context) {
    final paragraphs = _paragraphs();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.settings);
            }
          },
          tooltip: L10n.t(context, 'common.back'),
        ),
        title: Text(L10n.t(context, 'settings.communityRules')),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: paragraphs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          // Letzte Zeile: Link auf die oeffentliche Kinderschutz-Seite.
          //
          // Play verlangt fuer Dating-Apps einen oeffentlich
          // erreichbaren Kinderschutz-Bereich mit: Verbot von
          // Kindesmissbrauch, benannter Kontaktperson und beschriebenem
          // Meldeweg. Die Seite liegt statisch bei Netlify neben der
          // Datenschutz-Erklaerung.
          if (i == paragraphs.length) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t(context, 'cg.childSafetyLink.title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t(context, 'cg.childSafetyLink.body'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(kChildSafetyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(L10n.t(context, 'cg.childSafetyLink.open')),
                    ),
                  ],
                ),
              ),
            );
          }
          final rule = paragraphs[i];
          final isIntro = i == 0;
          return Card(
            color: isIntro
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, rule.titleKey),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isIntro
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, rule.bodyKey),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isIntro
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
