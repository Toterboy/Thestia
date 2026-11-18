// Der Teil '_SignedAppealImageState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _SignedAppealImageState extends ConsumerState<_SignedAppealImage> {
  Future<String?>? _urlFuture;
  String? _loadedPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureUrl();
  }

  @override
  void didUpdateWidget(covariant _SignedAppealImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _ensureUrl();
  }

  void _ensureUrl() {
    if (widget.path.isEmpty) {
      _urlFuture = null;
      _loadedPath = null;
      return;
    }
    if (_loadedPath == widget.path && _urlFuture != null) return;
    _loadedPath = widget.path;
    _urlFuture = ref
        .read(supabaseStorageServiceProvider)
        .getSignedUrlFor(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final future = _urlFuture;
    if (future == null) {
      return const ColoredBox(
        color: Color(0x22000000),
        child: Icon(Icons.image_not_supported),
      );
    }
    return FutureBuilder<String?>(
      future: future,
      builder: (context, snap) {
        final url = snap.data;
        if (url != null) {
          // SICHERHEIT (Audit 16.11.2026): Das Moderationsbild laedt ueber
          // den gepinnten Client - `Image.network` haengt am
          // System-Trust-Store.
          return PinnedNetworkImage(
            url: url,
            fit: BoxFit.cover,
            cacheWidth: 96 * 3,
            errorBuilder: (context, _, _) => const ColoredBox(
              color: Color(0x22000000),
              child: Icon(Icons.image_not_supported),
            ),
          );
        }
        return const ColoredBox(
          color: Color(0x22000000),
          child: Icon(Icons.image_not_supported),
        );
      },
    );
  }
}
