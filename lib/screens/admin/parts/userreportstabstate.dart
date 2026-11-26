// Der Teil '_UserReportsTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

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
      // Kennzahlen nachziehen: "Offene Meldungen" steht oben und wäre
      // sonst bis zum nächsten Öffnen um genau diese eine zu hoch.
      refreshAdminCounts(ref);
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
      emptyIcon: Icons.flag_outlined,
      emptyTitle: L10n.t(context, 'admin.emptyReportsTitle'),
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
        // Die Karte liefert _AsyncList. Hier steht nur der INHALT - vorher
        // lag ein zweites Card() in diesem Builder, sodass jede Meldung
        // zweimal gerahmt war (außerhalb der Liste noch einmal 12/6
        // eingerückt, also drei Ringe).
        return Padding(
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
        );
      },
    );
  }
}
