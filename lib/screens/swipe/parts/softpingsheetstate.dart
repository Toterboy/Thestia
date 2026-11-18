// Der Teil '_SoftPingSheetState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _SoftPingSheetState extends ConsumerState<_SoftPingSheet> {
  static const _presets = ['wave', 'again', 'coffee'];
  String? _selected;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'transit.pingSheetTitle'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            L10n.t(context, 'transit.pingSheetHint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(
              children: [
                for (final key in _presets)
                  RadioListTile<String>(
                    value: key,
                    title: Text(L10n.t(context, 'transit.preset.$key')),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            enableIMEPersonalizedLearning: false,
            autocorrect: false,
            enableSuggestions: false,
            controller: _customCtrl,
            maxLength: 140,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: L10n.t(context, 'transit.pingCustomHint'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected == null
                  ? null
                  : () async {
                      final ok = await ref
                          .read(transitProvider.notifier)
                          .sendSoftPing(
                            token: widget.token,
                            messageKey: _selected!,
                            customLine: _customCtrl.text.trim().isEmpty
                                ? null
                                : _customCtrl.text.trim(),
                          );
                      if (context.mounted) Navigator.of(context).pop(ok);
                    },
              child: Text(L10n.t(context, 'transit.pingSend')),
            ),
          ),
        ],
      ),
    );
  }
}
