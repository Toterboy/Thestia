// Der Teil '_UnifiedPushTileState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

class _UnifiedPushTileState extends ConsumerState<_UnifiedPushTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    UnifiedPushService.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool want) async {
    setState(() => _busy = true);
    try {
      if (want) {
        await UnifiedPushService.enable();
      } else {
        await UnifiedPushService.disable();
      }
      final active = await UnifiedPushService.isEnabled();
      if (mounted) setState(() => _enabled = active);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? false;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(L10n.t(context, 'settings.unifiedPush')),
      subtitle: Text(
        enabled
            ? L10n.t(context, 'settings.unifiedPushOn')
            : L10n.t(context, 'settings.unifiedPushOff'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: enabled,
      onChanged: _busy ? null : (v) => _toggle(v),
    );
  }
}
