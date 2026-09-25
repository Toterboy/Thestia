import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/photo_moderation_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/widgets/ai_badge.dart';

/// Hilfsfunktion: Prueft, ob der aktuell eingeloggte Nutzer der Admin ist.
///
/// Die Admin-UUID wird via --dart-define=ADMIN_UUID=... beim Build gesetzt.
/// Ist sie nicht konfiguriert (leerer String), gibt die Funktion IMMER false
/// zurÃ¼ck â€” Admin-Funktionen sind dann deaktiviert (fail-safe).
bool isCurrentUserAdmin() {
  final adminId = AppConstants.adminUserId;
  // Fail-safe: Wenn die Admin-UUID nicht konfiguriert ist, kann NIEMAND
  // Admin sein â€” auch nicht versehentlich durch leere User-ID.
  if (adminId.isEmpty) return false;
  final userId = SupabaseService.currentUser?.id;
  if (userId == null) return false;
  return userId == adminId;
}

/// Geschuetzter Admin-Screen.
///
/// SCHUTZKONZEPT (warum normale Nutzer ihn nicht sehen koennen):
///  1. Route nur aus "Mein Profil" verlinkt; der Screen prueft beim Oeffnen
///     clientseitig [isCurrentUserAdmin] UND serverseitig den RPC
///     `is_current_user_admin` (fail-closed - bei Fehler wird umgeleitet).
///  2. Alle Daten kommen ausschliesslich aus SECURITY DEFINER-RPCs
///     (`admin_list_*`), die `is_current_user_admin()` serverseitig
///     pruefen. Ohne Admin-Flag liefern sie leere Ergebnisse bzw. Fehler -
///     selbst bei manipuliertem Client ist kein Datenzugriff moeglich.
///  3. Schreibaktionen (Verifizierungs-Freigabe) laufen durch die Edge
///     Function `verify-account`, die den Admin-Status ebenfalls
///     serverseitig gegen die profiles-Tabelle prueft.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _serverAdminChecked = false;

  @override
  void initState() {
    super.initState();
    _enforceAdmin();
    _checkServerAdmin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enforceAdmin();
  }

  void _enforceAdmin() {
    if (!isCurrentUserAdmin() && mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _checkServerAdmin() async {
    if (!mounted) return;
    try {
      final result = await SupabaseService.client.rpc('is_current_user_admin');
      if (mounted && result != true) {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      // Fail-closed (Audit H6): SchlÃ¤gt die serverseitige PrÃ¼fung fehl,
      // wird der Admin-Bereich NICHT gerendert.
      if (kDebugMode) {
        debugPrint(
          '[AdminScreen] Server-Admin-Check fehlgeschlagen '
          '(fail-closed): $e',
        );
      }
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } finally {
      if (mounted) setState(() => _serverAdminChecked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isCurrentUserAdmin()) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'admin.deniedTitle'))),
        body: Center(child: Text(L10n.t(context, 'admin.deniedBody'))),
      );
    }

    if (!_serverAdminChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t(context, 'admin.title')),
          bottom: TabBar(
            isScrollable: true,
            // Abgerundete Klick-Animation (kein eckiger Aufblitzer).
            splashBorderRadius: const BorderRadius.all(Radius.circular(24)),
            tabs: [
              Tab(
                text: L10n.t(context, 'admin.tabReports'),
                icon: const Icon(Icons.flag),
              ),
              Tab(
                text: L10n.t(context, 'admin.tabBugs'),
                icon: const Icon(Icons.bug_report),
              ),
              Tab(
                text: L10n.t(context, 'admin.tabVerification'),
                icon: const Icon(Icons.verified),
              ),
              Tab(
                text: L10n.t(context, 'admin.tabModeration'),
                icon: const Icon(Icons.photo_library),
              ),
              Tab(
                text: L10n.t(context, 'admin.tabAppeals'),
                icon: const Icon(Icons.image_search),
              ),
              Tab(
                text: L10n.t(context, 'admin.tabBans'),
                icon: const Icon(Icons.block),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: L10n.t(context, 'admin.close'),
              // WICHTIG: context.go statt Navigator.pop - der Admin-Screen
              // wird per GoRouter-go erreicht (kein Stack-Eintrag), ein
              // Navigator.pop ging hinter die Root-Route und erzeugte
              // einen Blackscreen.
              onPressed: () => context.go(AppRoutes.home),
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _UserReportsTab(),
            _BugReportsTab(),
            _VerificationTab(),
            _PhotoModerationList(),
            _PhotoAppealsTab(),
            _BansTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Gemeinsames Lade-Geruest fuer Server-Listen.
// ===========================================================================
class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.loading,
    required this.error,
    required this.items,
    required this.emptyText,
    required this.itemBuilder,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> items;
  final String emptyText;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.tf(context, 'admin.error', {'error': '$error'})),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: Text(L10n.t(context, 'admin.retry')),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) return Center(child: Text(emptyText));
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        // Card-Look konsistent zur restlichen Nutzeroberfläche.
        itemBuilder: (context, i) => Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: itemBuilder(context, items[i]),
          ),
        ),
      ),
    );
  }
}

String _fmtTs(BuildContext context, dynamic ts) {
  final dt = ts is DateTime ? ts : DateTime.tryParse(ts?.toString() ?? '');
  if (dt == null) return L10n.t(context, 'admin.unknown');
  return DateFormat('dd.MM.yyyy HH:mm').format(dt);
}

// ===========================================================================
// Tab 1: Nutzer-Meldungen (user_reports-Tabelle via admin_list_user_reports)
// ===========================================================================
class _UserReportsTab extends ConsumerStatefulWidget {
  const _UserReportsTab();

  @override
  ConsumerState<_UserReportsTab> createState() => _UserReportsTabState();
}

class _UserReportsTabState extends ConsumerState<_UserReportsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchUserReports();
      // JSONB-Felder (createdAt als ISO-String) normalisieren.
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['createdAt'] = DateTime.tryParse(
          '${copy['createdAt']}',
        )?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resolve(String id) async {
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      await db.resolveUserReport(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.reportResolveFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: L10n.t(context, 'admin.noReports'),
      onRetry: _load,
      itemBuilder: (context, data) {
        final theme = Theme.of(context);
        final type =
            data['reportType'] as String? ?? L10n.t(context, 'admin.unknown');
        final description = (data['description'] as String? ?? '').trim();
        final status = data['status'] as String? ?? 'pending';
        final reportedId = data['reportedUserId'] as String? ?? '?';
        final reporterShort = '${data['reporterId'] ?? '?'}';
        final messagesCount =
            (data['messages'] as List<dynamic>? ?? <dynamic>[]).length;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(
                        status == 'pending'
                            ? L10n.t(context, 'admin.statusPending')
                            : status,
                      ),
                      backgroundColor: status == 'pending'
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        type,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  L10n.tf(context, 'admin.reportedUser', {'id': reportedId}),
                ),
                SelectableText(
                  L10n.tf(context, 'admin.reporter', {
                    'id': reporterShort.length > 12
                        ? '${reporterShort.substring(0, 12)}…'
                        : reporterShort,
                  }),
                ),
                Text(
                  L10n.tf(context, 'admin.messagesAttached', {
                    'count': '$messagesCount',
                  }),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(description),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fmtTs(context, data['createdAt']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (status == 'pending')
                      TextButton(
                        onPressed: () => _resolve(data['id'] as String),
                        child: Text(L10n.t(context, 'admin.resolved')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 2: Bug Reports (bug_reports-Tabelle via admin_list_bug_reports)
// ===========================================================================
class _BugReportsTab extends ConsumerStatefulWidget {
  const _BugReportsTab();

  @override
  ConsumerState<_BugReportsTab> createState() => _BugReportsTabState();
}

class _BugReportsTabState extends ConsumerState<_BugReportsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchBugReports();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['createdAt'] = DateTime.tryParse(
          '${copy['createdAt']}',
        )?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: L10n.t(context, 'admin.noBugs'),
      onRetry: _load,
      itemBuilder: (context, data) {
        final theme = Theme.of(context);
        final description = (data['description'] as String? ?? '').trim();
        final deviceInfo = (data['deviceInfo'] as String? ?? '').trim();
        final attachments = data['attachmentCount'] as int? ?? 0;
        final userId = data['userId'] as String? ?? '';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  description.isNotEmpty
                      ? description
                      : L10n.t(context, 'admin.noDescription'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.tf(context, 'admin.attachments', {
                    'count': '$attachments',
                    'time': _fmtTs(context, data['createdAt']),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                if (deviceInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    deviceInfo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (userId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    L10n.tf(context, 'admin.user', {'id': userId}),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 3: Verifizierungen (Videos im privaten Bucket freigeben/ablehnen)
// ===========================================================================
class _VerificationTab extends ConsumerStatefulWidget {
  const _VerificationTab();

  @override
  ConsumerState<_VerificationTab> createState() => _VerificationTabState();
}

class _VerificationTabState extends ConsumerState<_VerificationTab> {
  List<Map<String, dynamic>> _items = [];
  // Stichproben: Auto-Freigaben für die nachträgliche Kontrolle
  // (v0.9.0, Manipulationsschutz).
  List<Map<String, dynamic>> _auditItems = [];
  bool _loading = true;
  String? _error;
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchPendingVerifications();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['submittedAt'] = DateTime.tryParse(
          '${copy['submittedAt']}',
        )?.toLocal();
        return copy;
      }).toList();
      // Größte Altersabweichung zuerst (v0.9.1, 80-als-22-Fälle oben).
      _items.sort((a, b) => _deviation(b).compareTo(_deviation(a)));
      // Stichproben laden - EIGENER try/catch: Fehlt die RPC (Migration
      // 120 noch nicht deployed), darf die Pending-Queue NICHT brechen.
      try {
        final auditRows = await db.fetchAutoVerifications();
        _auditItems = auditRows.map((r) {
          final copy = Map<String, dynamic>.from(r);
          copy['submittedAt'] = DateTime.tryParse(
            '${copy['submittedAt']}',
          )?.toLocal();
          return copy;
        }).toList();
      } catch (e) {
        debugPrint('[Admin] Auto-Stichproben n/a (Migration 120?): $e');
        _auditItems = [];
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Betrag |KI-Schätzung - angegebenes Alter| (-1 = unbekannt).
  static double _deviation(Map<String, dynamic> data) {
    final est = (data['estimatedAge'] as num?)?.toDouble();
    final stated = (data['statedAge'] as num?)?.toDouble();
    if (est == null || stated == null) return -1;
    return (est - stated).abs();
  }

  Future<void> _review(String targetUserId, {required bool approve}) async {
    setState(() => _busyUserId = targetUserId);
    try {
      await SupabaseService.client.functions.invoke(
        'verify-account',
        body: {
          'action': 'review',
          'targetUserId': targetUserId,
          'isVerified': approve,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.reviewFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  /// Kurzlebige signierte URL vom Server holen und Video ansehen.
  Future<void> _watch(String targetUserId) async {
    // Vor den Awaits einlesen (kein BuildContext über async-Gaps).
    final noUrl = L10n.t(context, 'admin.noVideoUrl');
    final browserFailed = L10n.t(context, 'admin.browserOpenFailed');
    try {
      final response = await SupabaseService.client.functions.invoke(
        'verification-media',
        body: {'targetUserId': targetUserId},
      );
      final url = (response.data as Map?)?['url'] as String?;
      if (url == null) {
        throw StateError(noUrl);
      }
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(browserFailed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.videoFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    }
  }

  /// Karte für einen Verifizierungsfall (Pending-Queue und Auto-
  /// Stichproben teilen sich Darstellung + Aktionen).
  Widget _verificationCard(BuildContext context, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '?';
    final userId = data['userId'] as String? ?? '?';
    final busy = _busyUserId == userId;
    // KI-Schätzung vs. angegebenes Alter (v0.9.1, Migration 095).
    final est = (data['estimatedAge'] as num?)?.toDouble();
    final stated = (data['statedAge'] as num?)?.toDouble();
    final dev = _VerificationTabState._deviation(data);
    final ageLine = (est == null || stated == null)
        ? L10n.tf(context, 'admin.ageNoAi', {
            'stated': stated?.toStringAsFixed(0) ?? '?',
          })
        : L10n.tf(context, 'admin.ageAi', {
            'stated': stated.toStringAsFixed(0),
            'est': est.toStringAsFixed(0),
            'dev': dev.toStringAsFixed(0),
          });
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: dev > 2
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35)
          : null,
      child: ListTile(
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(userId),
            Text(
              ageLine,
              style: TextStyle(
                fontWeight: dev > 2 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: L10n.t(context, 'admin.watchVideo'),
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => _watch(userId),
                  ),
                  IconButton(
                    tooltip: L10n.t(context, 'admin.approve'),
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _review(userId, approve: true),
                  ),
                  IconButton(
                    tooltip: L10n.t(context, 'admin.rejectWithVideo'),
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _review(userId, approve: false),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.tf(context, 'admin.error', {'error': '$_error'})),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(L10n.t(context, 'admin.retry')),
            ),
          ],
        ),
      );
    }
    // Pending-Queue UND Auto-Stichproben in EINER scrollbaren Liste
    // (v0.9.0, Manipulationsschutz): Auto-Freigaben wurden bisher
    // nirgends mehr angezeigt - jetzt sind sie nachträglich prüfbar
    // (Video ansehen, bei Missbrauch entziehen).
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(L10n.t(context, 'admin.noVerifications')),
              ),
            )
          else
            for (final data in _items) ...[
              _verificationCard(context, data),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              L10n.t(context, 'admin.auditTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (_auditItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(L10n.t(context, 'admin.auditEmpty')),
              ),
            )
          else
            for (final data in _auditItems) ...[
              _verificationCard(context, data),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 4: Foto-Moderation (unveraendert uebernommen, mit Hash-Guard)
// ===========================================================================
class _PhotoModerationList extends ConsumerStatefulWidget {
  const _PhotoModerationList();

  @override
  ConsumerState<_PhotoModerationList> createState() =>
      _PhotoModerationListState();
}

class _PhotoModerationListState extends ConsumerState<_PhotoModerationList> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(photoModerationServiceProvider);
    _entries = await service.fetchPendingReviews();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.approvePhoto(id, adminId);
    await _load();
  }

  Future<void> _reject(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.rejectPhoto(id, adminId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return Center(child: Text(L10n.t(context, 'admin.noModeration')));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = _entries[i];
        final userId = entry['user_id'] as String? ?? '?';
        final userName = entry['user']?['name'] as String? ?? userId;
        final hashFull = entry['photo_hash'] as String? ?? '';
        // Guard: kuerzerer Hash darf keinen RangeError werfen.
        final hash = hashFull.length > 12
            ? '${hashFull.substring(0, 12)}…'
            : hashFull;
        final created = entry['created_at'] as String? ?? '';
        // Cloud-KI-Befund (HuggingFace) - nur wenn ein echter Cloud-
        // Check lief (kein 'moderation_disabled'-Marker).
        final hfLabel = entry['hf_label'] as String?;

        return ListTile(
          title: Text('$userName ($hash...)'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(created),
              if (hfLabel != null &&
                  hfLabel.isNotEmpty &&
                  hfLabel != 'moderation_disabled') ...[
                const SizedBox(height: 4),
                const AiBadge.cloudCompact(),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: L10n.t(context, 'admin.approveTooltip'),
                onPressed: () => _approve(entry['id'] as int),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: L10n.t(context, 'admin.rejectTooltip'),
                onPressed: () => _reject(entry['id'] as int),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 5: Sperren (banned_emails, Anzeige)
// ===========================================================================
class _BansTab extends ConsumerStatefulWidget {
  const _BansTab();

  @override
  ConsumerState<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends ConsumerState<_BansTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchBannedEmails();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['bannedAt'] = DateTime.tryParse('${copy['bannedAt']}')?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Ruft die Edge Function `admin-ban` auf (Service-Role-Aktionen).
  /// [actionFailedMessage] baut die lokalisierte Fallback-Fehlermeldung
  /// aus dem HTTP-Status (Aufrufer haben BuildContext, _invoke nicht).
  Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body,
    String Function(int status) actionFailedMessage,
  ) async {
    final response = await SupabaseService.client.functions.invoke(
      'admin-ban',
      body: body,
    );
    final data = (response.data as Map?)?.cast<String, dynamic>() ?? {};
    if (response.status != 200) {
      throw StateError(
        data['error']?.toString() ?? actionFailedMessage(response.status),
      );
    }
    return data;
  }

  /// Formular: Nutzer sperren (E-Mail oder User-ID + Pflicht-BegrÃ¼ndung).
  Future<void> _showBanDialog() async {
    final targetCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    var notifyUser = true;
    final formKey = GlobalKey<FormState>();
    // Nachrichten vor den Awaits einlesen (kein BuildContext über async-Gaps).
    final bannedMsg = L10n.t(context, 'admin.banned');
    final banFailedMsg = L10n.t(context, 'admin.banFailed');
    String actionFailed(int status) =>
        L10n.tf(context, 'admin.actionFailed', {'status': '$status'});

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(L10n.t(ctx, 'admin.banUser'))),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: targetCtrl,
                    decoration: InputDecoration(
                      labelText: L10n.t(ctx, 'admin.banTarget'),
                      hintText: L10n.t(ctx, 'admin.banTargetHint'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? L10n.t(ctx, 'admin.required')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: L10n.t(ctx, 'admin.banReason'),
                      hintText: L10n.t(ctx, 'admin.banReasonHint'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? L10n.t(ctx, 'admin.minChars')
                        : null,
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: notifyUser,
                    onChanged: (v) => setState(() => notifyUser = v ?? true),
                    title: Text(L10n.t(ctx, 'admin.notifyUser')),
                    subtitle: Text(L10n.t(ctx, 'admin.notifySub')),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  Text(
                    L10n.t(ctx, 'admin.banHint'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(ctx, 'admin.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final messenger = ScaffoldMessenger.of(ctx);
                try {
                  await _invoke({
                    'action': 'ban',
                    'emailOrUserId': targetCtrl.text.trim(),
                    'reason': reasonCtrl.text.trim(),
                    'notifyUser': notifyUser,
                  }, actionFailed);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(bannedMsg),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e is StateError ? e.message : banFailedMsg),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(L10n.t(ctx, 'admin.ban')),
            ),
          ],
        ),
      ),
    );
  }

  /// Entsperrt eine E-Mail (banned_emails-Eintrag lÃ¶schen + GoTrue-Entsperren).
  Future<void> _unban(Map<String, dynamic> entry) async {
    final email = entry['email'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'admin.unbanTitle')),
        content: Text(L10n.tf(ctx, 'admin.unbanBody', {'email': email})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'admin.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'admin.unban')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    // Vor den Awaits einlesen (kein BuildContext über async-Gaps).
    String actionFailed(int status) =>
        L10n.tf(context, 'admin.actionFailed', {'status': '$status'});
    try {
      await _invoke({'action': 'unban', 'emailOrUserId': email}, actionFailed);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'admin.unbanned', {'email': email})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : L10n.t(context, 'admin.unbanFailed'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _showBanDialog,
              icon: const Icon(Icons.person_add_disabled),
              label: Text(L10n.t(context, 'admin.banUser')),
            ),
          ),
        ),
        Expanded(
          child: _AsyncList(
            loading: _loading,
            error: _error,
            items: _items,
            emptyText: L10n.t(context, 'admin.noBans'),
            onRetry: _load,
            itemBuilder: (context, data) {
              final email = data['email'] as String? ?? '?';
              final reason = (data['reason'] as String? ?? '').trim();
              final bannedBy = data['bannedBy'] as String? ?? '?';
              return ListTile(
                title: SelectableText(email),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reason.isNotEmpty) SelectableText(reason),
                    Text(
                      L10n.tf(context, 'admin.bannedBy', {
                        'time': _fmtTs(context, data['bannedAt']),
                        'by': bannedBy,
                      }),
                    ),
                  ],
                ),
                leading: const Icon(Icons.block, color: Colors.red),
                trailing: IconButton(
                  icon: const Icon(Icons.lock_open, color: Colors.green),
                  tooltip: L10n.t(context, 'admin.unban'),
                  onPressed: _busy ? null : () => _unban(data),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Tab 5: Bild-Prüfung (v0.8.1 Einspruchs-Verfahren)
//
// Nutzer, deren Profilbild die LOKALE NSFW-Prüfung abgelehnt hat, können
// Einspruch einlegen. Das Bild liegt dann verschlüsselt-frei (nur
// Owner + Admin via Storage-Policy) unter {uid}/appeals/ im privaten
// avatars-Bucket und wird hier zur Entscheidung angezeigt.
//   - Freigeben: Nutzer erhält Push + kann das Bild in der App als
//     Profilbild übernehmen (Client verschlüsselt dabei selbst).
//   - Ablehnen: Nutzer erhält Push; die Appeals-Datei wird vom Client
//     beim Quittieren gelöscht.
// ===========================================================================
class _PhotoAppealsTab extends ConsumerStatefulWidget {
  const _PhotoAppealsTab();

  @override
  ConsumerState<_PhotoAppealsTab> createState() => _PhotoAppealsTabState();
}

class _PhotoAppealsTabState extends ConsumerState<_PhotoAppealsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appeals = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      final appeals = await db.adminListPhotoAppeals();
      if (mounted) setState(() => _appeals = appeals);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> appeal, bool approve) async {
    final id = appeal['id'] as String? ?? '';
    if (id.isEmpty || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      await db.adminDecidePhotoAppeal(id: id, approve: approve);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.decideFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.tf(context, 'admin.error', {'error': '$_error'})),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(L10n.t(context, 'admin.retry')),
            ),
          ],
        ),
      );
    }
    if (_appeals.isEmpty) {
      return Center(child: Text(L10n.t(context, 'admin.noAppeals')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _appeals.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final a = _appeals[i];
          return _AppealCard(
            appeal: a,
            busy: _busy.contains(a['id']),
            onDecide: (approve) => _decide(a, approve),
          );
        },
      ),
    );
  }
}

class _AppealCard extends ConsumerWidget {
  const _AppealCard({
    required this.appeal,
    required this.busy,
    required this.onDecide,
  });

  final Map<String, dynamic> appeal;
  final bool busy;
  final void Function(bool approve) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = appeal['storagePath'] as String? ?? '';
    final status = appeal['status'] as String? ?? 'pending';
    final label = appeal['localLabel'] as String? ?? '';
    final score = (appeal['localScore'] as num?)?.toDouble() ?? 0;
    final userName =
        appeal['userName'] as String? ?? L10n.t(context, 'admin.unknown');
    final createdAt =
        DateTime.tryParse(appeal['createdAt'] as String? ?? '') ??
        DateTime.now();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: FutureBuilder<String?>(
                      future: ref
                          .read(supabaseStorageServiceProvider)
                          .getSignedUrlFor(path),
                      builder: (context, snap) {
                        final url = snap.data;
                        if (url != null) {
                          return Image.network(url, fit: BoxFit.cover);
                        }
                        return const ColoredBox(
                          color: Color(0x22000000),
                          child: Icon(Icons.image_not_supported),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.tf(context, 'admin.appealSubmitted', {
                          'time': createdAt.toLocal().toString().substring(
                            0,
                            16,
                          ),
                        }),
                      ),
                      Text(
                        L10n.tf(context, 'admin.appealFinding', {
                          'label': label.isEmpty ? 'n/a' : label,
                          'score': (score * 100).toStringAsFixed(0),
                        }),
                      ),
                      // KI-Transparenz (Nutzerwunsch): Dieser Befund stammt
                      // aus der lokalen On-Device-KI.
                      const SizedBox(height: 4),
                      const AiBadge.localCompact(),
                      const SizedBox(height: 4),
                      _StatusChip(status: status),
                    ],
                  ),
                ),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onDecide(false),
                    icon: const Icon(Icons.close),
                    label: Text(L10n.t(context, 'admin.rejectTooltip')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : () => onDecide(true),
                    icon: const Icon(Icons.check),
                    label: Text(L10n.t(context, 'admin.approve')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => (L10n.t(context, 'admin.statusOpen'), Colors.orange),
      'approved' => (L10n.t(context, 'admin.statusApproved'), Colors.green),
      'rejected' => (L10n.t(context, 'admin.statusRejected'), Colors.red),
      'notified' => (L10n.t(context, 'admin.statusNotified'), Colors.blueGrey),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
