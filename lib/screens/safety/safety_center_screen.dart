import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';

/// Safety Center: zentrale Anlaufstelle bei Belästigung, Stalking oder
/// Bedrohung – mit externen Hilfsangeboten und In-App-Maßnahmen.
///
/// Alle externen Links öffnen bewusst im Systembrowser/Telefon-App
/// (url_launcher); die App selbst übermittelt dabei keine Nutzungsdaten.
class SafetyCenterScreen extends ConsumerStatefulWidget {
  const SafetyCenterScreen({super.key});

  @override
  ConsumerState<SafetyCenterScreen> createState() => _SafetyCenterScreenState();
}

class _SafetyCenterScreenState extends ConsumerState<SafetyCenterScreen> {
  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'safety.linkFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'safety.centerTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(
              context,
            ).colorScheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.emergency_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bei akuter Gefahr rufe sofort die Polizei: 110. '
                      'Du bist nicht allein. Die folgenden Stellen helfen '
                      'kostenlos und vertraulich.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, 'safety.sectionHelp'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: Text(L10n.t(context, 'safety.hotline1')),
            subtitle: Text(L10n.t(context, 'safety.hotline1Sub')),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '116016')),
          ),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: Text(L10n.t(context, 'safety.hotline2')),
            subtitle: Text(L10n.t(context, 'safety.hotline2Sub')),
            trailing: const Icon(Icons.call),
            onTap: () =>
                _open(context, Uri(scheme: 'tel', path: '08001110111')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(L10n.t(context, 'safety.hotline3')),
            subtitle: Text(L10n.t(context, 'safety.hotline3Sub')),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(context, Uri.parse('https://www.klicksafe.de')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(L10n.t(context, 'safety.hotline4')),
            subtitle: Text(L10n.t(context, 'safety.hotline4Sub')),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(context, Uri.parse('https://weisser-ring.de')),
          ),
          const Divider(height: 32),
          Text(
            L10n.t(context, 'safety.sectionProtect'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _SchutzKachel(
            icon: Icons.flag_outlined,
            titelKey: 'safety.reportSomeone',
            textKey: 'safety.reportSomeoneBody',
          ),
          const _SchutzKachel(
            icon: Icons.block_outlined,
            titelKey: 'safety.blockSomeone',
            textKey: 'safety.blockSomeoneBody',
          ),
          const _SchutzKachel(
            icon: Icons.lock_person_outlined,
            titelKey: 'safety.protectOwnImages',
            textKey: 'safety.protectOwnImagesBody',
          ),
          // Alter & Täuschung (v0.9.1, Jugendschutz): Warnung vor falschen
          // Altersangaben, Meldegrund "Falsches Alter", Treffen-Regeln.
          const _SchutzKachel(
            icon: Icons.cake_outlined,
            titelKey: 'safety.ageTitle',
            textKey: 'safety.ageBody',
          ),
          // NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen
          // sollen beide als einzelne Screens, damit der Safety Center
          // Screen nicht überladen wird, wenn es viele blockierungen
          // und oder Meldungen gibt."
          //
          // Vorher standen beide Listen hier - eine Zeile je Eintrag.
          // Bei vielen Blockierungen oder Meldungen wurde der Screen
          // unbrauchbar. Jetzt führen zwei Kacheln zu je einem Screen.
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: Text(L10n.t(context, 'safety.blockedUsers')),
            subtitle: Text(L10n.t(context, 'safety.blockedUsersSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.blockedUsers),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(L10n.t(context, 'safety.myReports')),
            subtitle: Text(L10n.t(context, 'safety.myReportsSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.myReports),
          ),
          // BEFUND (14.11.2026, Betreiber): "Meine Daten exportieren bei
          // Safety Center obwohl schon bei Datenschutz und Account."
          //
          // Der Export stand hier ZWEIMAL: im Safety Center und unter
          // Datenschutz & Account. Zwei Wege für dieselben Knopf sind
          // einer zu viel - und der hier war der schlechtere (das
          // Safety Center ist die Seite für Sofortmassnahmen bei
          // Belästigung, nicht für Datenauskunft). Der Weg bleibt:
          // Datenschutz & Account.
          const Divider(height: 32),
          Text(
            L10n.t(context, 'safety.stalkingGuide'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            L10n.t(context, 'safety.stalkingBody'),
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Ein aufklappbarer Schutz-Punkt als weiche Kachel.
///
/// NUTZERWUNSCH (27.10.2026): beim Aufklappen eines Punktes im Bereich
/// "Schutz in Thestia" zogen sich Linien ÜBER und UNTER den Punkt.
/// Das ist die Standardzeichnung des Material-3-ExpansionTile im
/// aufgeklappten Zustand und passte nicht zum weichen Design der App.
///
/// Zwei Änderungen, beide im Projekt schon bewährt (Dating Hour
/// "So funktioniert's", Spice-Fragen):
///   * die Kachel sitzt in einer Card mit dem Radius der App (24),
///   * shape/collapsedShape OHNE BorderSide - dadurch zeichnet das
///     ExpansionTile keine Linien.
///
/// Statt der Linien gibt es jetzt eine weiche Card, die sich beim
/// Aufklappen mit aufflächen trägt. Das ist dasselbe Muster wie in
/// den beiden anderen Screens - die App sieht damit an allen drei
/// Stellen gleich aus.
class _SchutzKachel extends StatelessWidget {
  const _SchutzKachel({
    required this.icon,
    required this.titelKey,
    required this.textKey,
  });

  final IconData icon;
  final String titelKey;
  final String textKey;

  @override
  Widget build(BuildContext context) {
    // Ohne BorderSide. Mit BorderSide zeichnet das ExpansionTile die
    // Linien, die der Nutzer bemerkt hat.
    final kachelForm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: kachelForm,
        collapsedShape: kachelForm,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          L10n.t(context, titelKey),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(L10n.t(context, textKey)),
          ),
        ],
      ),
    );
  }
}
