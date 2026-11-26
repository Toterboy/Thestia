// Der Teil '_PhotoModerationListState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _PhotoModerationListState extends ConsumerState<_PhotoModerationList> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final service = ref.read(photoModerationServiceProvider);
    // Ohne try/catch blieb `_loading` bei einem Netzwerkfehler dauerhaft
    // true (Endlos-Spinner) und der Fehler landete unhandled.
    try {
      _entries = await service.fetchPendingReviews();
    } catch (e) {
      // Fehler merken statt schlucken: fetchPendingReviews liefert zwar
      // selbst [] statt zu werfen, aber der Admin soll einen Ladefehler
      // von einer leeren Queue unterscheiden können - die Kennzahl
      // oben zählt nämlich die Queue mit.
      if (kDebugMode) debugPrint('[Admin] Reviews laden fehlgeschlagen: $e');
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.approvePhoto(id, adminId);
    await _load();
    refreshAdminCounts(ref);
  }

  Future<void> _reject(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.rejectPhoto(id, adminId);
    await _load();
    refreshAdminCounts(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Über _AsyncList statt eigenes ListView: das war der einzige Tab mit
    // einem abweichenden Rahmen (Divider zwischen Zeilen statt Karten) und
    // ohne Pull-to-refresh.
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _entries,
      emptyIcon: Icons.photo_library_outlined,
      emptyTitle: L10n.t(context, 'admin.emptyModerationTitle'),
      emptyText: L10n.t(context, 'admin.noModeration'),
      onRetry: _load,
      itemBuilder: (context, data) {
        final userId = data['user_id'] as String? ?? '?';
        final userName = data['user']?['name'] as String? ?? userId;
        final hashFull = data['photo_hash'] as String? ?? '';
        // Guard: kürzerer Hash darf keinen RangeError werfen.
        final hash = hashFull.length > 12
            ? '${hashFull.substring(0, 12)}…'
            : hashFull;
        final created = data['created_at'] as String? ?? '';
        // Cloud-KI-Befund (HuggingFace) - nur wenn ein echter Cloud-
        // Check lief (kein 'moderation_disabled'-Marker).
        final hfLabel = data['hf_label'] as String?;

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
                onPressed: () => _approve(data['id'] as int),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: L10n.t(context, 'admin.rejectTooltip'),
                onPressed: () => _reject(data['id'] as int),
              ),
            ],
          ),
        );
      },
    );
  }
}
