// Der Teil '_LocationChecksTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _LocationChecksTabState extends ConsumerState<_LocationChecksTab> {
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
      final rows = await db.fetchLocationChecks();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['checkedAt'] = DateTime.tryParse(
          '${copy['checkedAt']}',
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
    final thema = Theme.of(context);
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyIcon: Icons.location_on_outlined,
      emptyTitle: L10n.t(context, 'admin.locationsTitle'),
      emptyText: L10n.t(context, 'admin.locationsEmpty'),
      onRetry: _load,
      // Der Hinweis steht ueber der Liste: ohne ihn haelt der Admin
      // das Flag fuer ein Verdict.
      header: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(
          L10n.t(context, 'admin.locationsHint'),
          style: thema.textTheme.bodySmall,
        ),
      ),
      itemBuilder: (context, data) {
        final verified = data['isVerified'] == true;
        return ListTile(
          leading: Icon(
            Icons.location_off_outlined,
            color: thema.colorScheme.error,
          ),
          title: Text(data['name'] as String? ?? '?'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.tf(context, 'admin.locationsCheckedAt', {
                  'date': _fmtTs(context, data['checkedAt']),
                }),
                style: thema.textTheme.bodySmall,
              ),
              Text(
                verified
                    ? L10n.t(context, 'admin.locationsVerified')
                    : L10n.t(context, 'admin.locationsUnverified'),
                style: thema.textTheme.bodySmall,
              ),
              // Die User-ID: ohne sie kann der Admin den Fall nicht
              // zuordnen (der Name ist frei gewaehlt).
              SelectableText(
                data['userId'] as String? ?? '?',
                style: thema.textTheme.bodySmall?.copyWith(
                  color: thema.colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
