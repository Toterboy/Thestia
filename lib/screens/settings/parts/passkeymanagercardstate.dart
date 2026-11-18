// Der Teil '_PasskeyManagerCardState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

// Passkeys sind ein Supabase-Beta-Feature (@experimental). DER GRUND:
// Die Anweisung stand frueher in der Hauptdatei - beim Teilen muss sie
// auch in diesem Teil stehen, sonst meldet der Analyser 4 Warnungen.
// ignore_for_file: experimental_member_use

part of '../settings_screen.dart';

class _PasskeyManagerCardState extends ConsumerState<_PasskeyManagerCard> {
  List<Passkey>? _passkeys;
  String? _error;
  bool _needsStepUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool stepUpFirst = false}) async {
    setState(() {
      _error = null;
      _needsStepUp = false;
    });
    try {
      if (stepUpFirst) {
        if (!await _ensurePasskeyAal2(context, ref)) return;
      }
      final list = await PasskeyAuth.listRegistered();
      if (!mounted) return;
      setState(() => _passkeys = list);
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final aal2Needed =
          text.contains('aal2') || text.contains('mfa') || text.contains('403');
      setState(() {
        _passkeys = null;
        _needsStepUp = aal2Needed;
        _error = aal2Needed
            ? L10n.t(context, 'passkey.stepUpHint')
            : L10n.t(context, 'passkey.loadError');
      });
    }
  }

  Future<void> _rename(Passkey passkey) async {
    final ctrl = TextEditingController(text: passkey.friendlyName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'passkey.renameTitle')),
        content: TextField(
          enableIMEPersonalizedLearning: false,
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: L10n.t(ctx, 'passkey.renameLabel'),
            hintText: L10n.t(ctx, 'passkey.renameHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(L10n.t(ctx, 'common.save')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await PasskeyAuth.rename(passkeyId: passkey.id, friendlyName: name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AppException
          ? L10n.exc(context, e)
          : L10n.t(context, 'passkey.renameFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _delete(Passkey passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(ctx).colorScheme.error,
          size: 36,
        ),
        title: Text(L10n.t(context, 'settings.passkeyDeleteTitle')),
        content: Text(
          L10n.tf(context, 'passkey.deleteBody', {
            'name': passkey.friendlyName ?? L10n.t(context, 'passkey.name'),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'settings.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (!await _ensurePasskeyAal2(context, ref)) return;
      await PasskeyAuth.delete(passkeyId: passkey.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'settings.passkeyDeleted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AppException
          ? L10n.exc(context, e)
          : L10n.t(context, 'settings.deleteFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  String _formatDate(DateTime? utc) {
    if (utc == null) return '';
    try {
      return DateFormat('dd.MM.yyyy').format(utc.toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _passkeys == null
        ? (_error ?? L10n.t(context, 'passkey.managerSub'))
        : L10n.tf(context, 'passkey.managerHint', {
            'count': '${_passkeys!.length}',
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: Text(L10n.t(context, 'settings.passkeysManage')),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: L10n.t(context, 'common.refresh'),
            onPressed: _error != null && _needsStepUp
                ? () => _load(stepUpFirst: true)
                : _load,
            icon: const Icon(Icons.refresh),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        for (final passkey in _passkeys ?? const <Passkey>[])
          ListTile(
            leading: const Icon(Icons.fingerprint, size: 20),
            title: Text(
              passkey.friendlyName ?? L10n.t(context, 'passkey.name'),
            ),
            subtitle: Text(
              [
                L10n.tf(context, 'settings.passkeyCreatedAt', {
                  'date': _formatDate(passkey.createdAt),
                }),
                if (passkey.lastUsedAt != null)
                  L10n.tf(context, 'settings.passkeyLastUsed', {
                    'date': _formatDate(passkey.lastUsedAt),
                  }),
              ].join(' · '),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: L10n.t(context, 'settings.passkeyRename'),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _rename(passkey),
                ),
                IconButton(
                  tooltip: L10n.t(context, 'settings.delete'),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _delete(passkey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
