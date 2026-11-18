// Der Teil '_PhotoAppealsTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

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
      refreshAdminCounts(ref);
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
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _appeals,
      emptyIcon: Icons.image_search,
      emptyTitle: L10n.t(context, 'admin.emptyAppealsTitle'),
      emptyText: L10n.t(context, 'admin.noAppeals'),
      onRetry: _load,
      itemBuilder: (context, data) => _AppealCard(
        appeal: data,
        busy: _busy.contains(data['id']),
        onDecide: (approve) => _decide(data, approve),
      ),
    );
  }
}
