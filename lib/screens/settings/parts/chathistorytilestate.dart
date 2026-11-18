// Der Teil '_ChatHistoryTileState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

class _ChatHistoryTileState extends ConsumerState<_ChatHistoryTile> {
  _HistoryMode _mode = _HistoryMode.all;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final storage = ref.read(localStorageProvider);
        final enabled = await storage.getBool('chat_history_local') ?? true;
        final all = await storage.getBool('chat_history_all') ?? true;
        if (!mounted) return;
        setState(() {
          _mode = enabled
              ? (all ? _HistoryMode.all : _HistoryMode.cap200)
              : _HistoryMode.off;
        });
      } catch (_) {
        if (mounted) setState(() => _mode = _HistoryMode.all);
      }
    }());
  }

  Future<void> _apply(_HistoryMode mode) async {
    setState(() => _busy = true);
    try {
      final storage = ref.read(localStorageProvider);
      await storage.saveBool('chat_history_local', mode != _HistoryMode.off);
      await storage.saveBool('chat_history_all', mode == _HistoryMode.all);
      ref
          .read(chatProvider.notifier)
          .setHistoryPersistence(
            mode != _HistoryMode.off,
            limit: mode == _HistoryMode.cap200 ? 200 : null,
          );
      if (mounted) setState(() => _mode = mode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMode() async {
    final picked = await showDialog<_HistoryMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'chathist.dialogTitle')),
        content: RadioGroup<_HistoryMode>(
          groupValue: _mode,
          onChanged: (v) => Navigator.of(ctx).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in _HistoryMode.values)
                RadioListTile<_HistoryMode>(
                  value: mode,
                  title: Text(switch (mode) {
                    _HistoryMode.off => L10n.t(ctx, 'chathist.off.title'),
                    _HistoryMode.cap200 => L10n.t(ctx, 'chathist.cap200.title'),
                    _HistoryMode.all => L10n.t(ctx, 'chathist.all.title'),
                  }),
                  subtitle: Text(switch (mode) {
                    _HistoryMode.off => L10n.t(ctx, 'chathist.off.sub'),
                    _HistoryMode.cap200 => L10n.t(ctx, 'chathist.cap200.sub'),
                    _HistoryMode.all => L10n.t(ctx, 'chathist.all.sub'),
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != _mode) {
      await _apply(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_mode) {
      _HistoryMode.off => L10n.t(context, 'chathist.mode.off'),
      _HistoryMode.cap200 => L10n.t(context, 'chathist.mode.cap200'),
      _HistoryMode.all => L10n.t(context, 'chathist.mode.all'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.history,
        color: _mode == _HistoryMode.off
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(L10n.t(context, 'chathist.tileTitle')),
      subtitle: Text(
        '${L10n.t(context, 'chathist.tileSubPrefix')} '
        '${L10n.t(context, 'chathist.modeWord')} $label. '
        '${L10n.t(context, 'chathist.deleteHint')}',
      ),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _pickMode,
    );
  }
}
