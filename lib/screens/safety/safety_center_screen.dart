import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/l10n/app_strings.dart';

/// Safety Center: zentrale Anlaufstelle bei Belästigung, Stalking oder
/// Bedrohung – mit externen Hilfsangeboten und In-App-Maßnahmen.
///
/// Alle externen Links öffnen bewusst im Systembrowser/Telefon-App
/// (url_launcher); die App selbst übermittelt dabei keine Nutzungsdaten.
class SafetyCenterScreen extends ConsumerStatefulWidget {
  const SafetyCenterScreen({super.key});

  @override
  ConsumerState<SafetyCenterScreen> createState() =>
      _SafetyCenterScreenState();
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
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emergency_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bei akuter Gefahr rufe sofort die Polizei: 110. '
                      'Du bist nicht allein. Die folgenden Stellen helfen '
                      'kostenlos und vertraulich.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(L10n.t(context, 'safety.sectionHelp'),
              style: Theme.of(context).textTheme.titleMedium),
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
            subtitle:
                Text(L10n.t(context, 'safety.hotline2Sub')),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '08001110111')),
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
            onTap: () =>
                _open(context, Uri.parse('https://weisser-ring.de')),
          ),
          const Divider(height: 32),
          Text(L10n.t(context, 'safety.sectionProtect'),
              style: Theme.of(context).textTheme.titleMedium),
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
          const _BlockedUsersSection(),
          const SizedBox(height: 8),
          const _MyReportsSection(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(L10n.t(context, 'safety.exportData')),
            subtitle: Text(L10n.t(context, 'safety.exportDataSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          const Divider(height: 32),
          Text(L10n.t(context, 'safety.stalkingGuide'),
              style: Theme.of(context).textTheme.titleMedium),
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
/// "Schutz in Thestia" zogen sich Linien UEBER und UNTER den Punkt.
/// Das ist die Standardzeichnung des Material-3-ExpansionTile im
/// aufgeklappten Zustand und passte nicht zum weichen Design der App.
///
/// Zwei Aenderungen, beide im Projekt schon bewaehrt (Dating Hour
/// "So funktioniert's", Spice-Fragen):
///   * die Kachel sitzt in einer Card mit dem Radius der App (24),
///   * shape/collapsedShape OHNE BorderSide - dadurch zeichnet das
///     ExpansionTile keine Linien.
///
/// Statt der Linien gibt es jetzt eine weiche Card, die sich beim
/// Aufklappen mit aufflaechen traegt. Das ist dasselbe Muster wie in
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

/// Meine Meldungen (v0.8.0): Status-Feedback ohne Details zu Dritten.
class _MyReportsSection extends ConsumerStatefulWidget {
  const _MyReportsSection();

  @override
  ConsumerState<_MyReportsSection> createState() => _MyReportsSectionState();
}

class _MyReportsSectionState extends ConsumerState<_MyReportsSection> {
  List<MyReportEntry>? _reports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await _loadReports();
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      if (mounted) setState(() => _reports = []);
    }
  }

  Future<List<MyReportEntry>> _loadReports() async {
    final response = await SupabaseService.client.rpc('list_my_reports');
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) =>
            MyReportEntry.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'safety.myReports'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_reports == null)
          const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_reports!.isEmpty)
          Text(L10n.t(context, 'safety.noReports'),
              style: const TextStyle(color: Colors.grey))
        else
          for (final report in _reports!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                report.status == 'pending'
                    ? Icons.hourglass_top
                    : Icons.check_circle_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            title: Text(report.reportType.isEmpty
                ? L10n.t(context, 'report.type.default')
                : report.reportType),
              subtitle: Text(report.statusLabel),
            ),
      ],
    );
  }
}

/// Blockierte Nutzer (v0.8.0): Liste mit Entblocken.
class _BlockedUsersSection extends ConsumerStatefulWidget {
  const _BlockedUsersSection();

  @override
  ConsumerState<_BlockedUsersSection> createState() => _BlockedUsersSectionState();
}

class _BlockedUsersSectionState extends ConsumerState<_BlockedUsersSection> {
  List<BlockedUserEntry>? _blocked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response =
          await SupabaseService.client.rpc('list_blocked_users');
      final rows = (response as List<dynamic>? ?? <dynamic>[]);
      final blocked = rows
          .map((row) =>
              BlockedUserEntry.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (mounted) setState(() => _blocked = blocked);
    } catch (_) {
      if (mounted) setState(() => _blocked = []);
    }
  }

  Future<void> _unblock(BlockedUserEntry entry) async {
    try {
      await SupabaseService.client
          .rpc('unblock_user', params: {'p_blocked': entry.blockedUserId});
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'safety.unblockFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'safety.blockedUsers'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_blocked == null)
          const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_blocked!.isEmpty)
          Text(L10n.t(context, 'safety.noBlocked'),
              style: const TextStyle(color: Colors.grey))
        else
          for (final entry in _blocked!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_outlined),
              title: Text(entry.name),
              trailing: TextButton(
                onPressed: () => _unblock(entry),
                child: Text(L10n.t(context, 'safety.unblock')),
              ),
            ),
      ],
    );
  }
}
