// Der Teil '_BansTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _BansTabState extends ConsumerState<_BansTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// Suchbegriff für E-Mail, Begründung und Person. Leer = keine Filterung.
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filtert die Sperren clientseitig über alle drei sichtbaren Felder:
  /// der Admin sucht meistens einen Teil der E-Mail, manchmal aber das
  /// Stichwort aus der Begründung ("Beleidigung"), weil ihm der Absender
  /// unbekannt ist. Die Logik selbst liegt in [filterBans] und ist dort
  /// getestet.
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
    // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der Aufruf stehen,
    // wenn die Function keine Antwort bekam.
    final response = await SupabaseService.rufeEdgeFunktion(
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

  /// Formular: Nutzer sperren (E-Mail oder User-ID + Pflicht-Begründung).
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
                    enableIMEPersonalizedLearning: false,
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
                    enableIMEPersonalizedLearning: false,
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
                  refreshAdminCounts(ref);
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

  /// Entsperrt eine E-Mail (banned_emails-Eintrag löschen + GoTrue-Entsperren).
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
      refreshAdminCounts(ref);
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
    // Gefiltert schon im build, nicht in einem Setter: die Liste ist die
    // Quelle der Wahrheit, der Suchbegriff ist nur ein Blick darauf.
    final filtered = filterBans(_items, _query);
    final searching = _query.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  enableIMEPersonalizedLearning: false,
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: L10n.t(context, 'admin.searchBansHint'),
                    labelText: L10n.t(context, 'admin.searchBans'),
                    border: const OutlineInputBorder(),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: L10n.t(context, 'admin.searchBansClear'),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Der Knopf bleibt neben dem Feld, damit er bei aktiver
              // Suche nicht aus dem Bild gescrollt ist.
              FilledButton.icon(
                onPressed: _busy ? null : _showBanDialog,
                icon: const Icon(Icons.person_add_disabled),
                label: Text(L10n.t(context, 'admin.banUser')),
              ),
            ],
          ),
        ),
        Expanded(
          child: _AsyncList(
            loading: _loading,
            error: _error,
            items: filtered,
            emptyIcon: Icons.block,
            emptyTitle: L10n.t(context, 'admin.emptyBansTitle'),
            // Zwei verschiedene Leerfälle: "keine Sperren überhaupt" und
            // "deine Suche passt zu nichts". Zusammen in einem Text war
            // genau das, was die Suche unbrauchbar machte - der Admin
            // las "Keine Sperren vorhanden" und dachte, die Datenbank sei leer.
            emptyText: searching
                ? L10n.t(context, 'admin.searchBansEmpty')
                : L10n.t(context, 'admin.noBans'),
            onRetry: _load,
            // Trefferzahl, solange gefiltert wird. Ohne sie weiß der
            // Admin nicht, ob er 2 von 300 oder 2 von 2 sieht.
            header: searching && filtered.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      L10n.tf(context, 'admin.searchBansResult', {
                        'count': '${filtered.length}',
                        'total': '${_items.length}',
                      }),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : null,
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
