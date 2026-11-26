// Der Teil '_BugReportsTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

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
      emptyIcon: Icons.bug_report_outlined,
      emptyTitle: L10n.t(context, 'admin.emptyBugsTitle'),
      emptyText: L10n.t(context, 'admin.noBugs'),
      onRetry: _load,
      itemBuilder: (context, data) {
        final theme = Theme.of(context);
        final description = (data['description'] as String? ?? '').trim();
        final deviceInfo = (data['deviceInfo'] as String? ?? '').trim();
        final attachments = data['attachmentCount'] as int? ?? 0;
        final userId = data['userId'] as String? ?? '';
        // Wie im Meldungs-Tab: kein eigenes Card(), die Liste rahmt.
        return Padding(
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
                Text(
                  L10n.tf(context, 'admin.user', {'id': userId}),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
