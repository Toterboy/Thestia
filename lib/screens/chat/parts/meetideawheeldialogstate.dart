// Der Teil '_MeetIdeaWheelDialogState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _MeetIdeaWheelDialogState extends State<_MeetIdeaWheelDialog> {
  bool _spinning = false;
  String? _result;
  int _index = 0;

  Future<void> _spin() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    final rng = Random();
    final target = rng.nextInt(widget.categories.length);
    // Abnehmende Zyklen: wirkt wie ein echtes Rad, das ausläuft.
    var delay = 60;
    var rounds = 24 + rng.nextInt(8);
    var i = 0;
    while (rounds > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
      rounds--;
      i++;
      if (i % 6 == 0) delay += 25; // auslaufen
    }
    // Landen auf dem Ziel.
    while (_index != target) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
    }
    if (!mounted) return;
    setState(() {
      _result = widget.categories[target];
      _spinning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.casino_outlined,
        color: Theme.of(context).colorScheme.primary,
        size: 36,
      ),
      title: Text(L10n.t(context, 'chat.wheelTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _result ?? widget.categories[_index % widget.categories.length],
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (_result == null)
              FilledButton.icon(
                onPressed: _spin,
                icon: const Icon(Icons.refresh),
                label: Text(L10n.t(context, 'chat.wheelSpin')),
              )
            else ...[
              Text(
                L10n.t(context, 'chat.wheelHint'),
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_result != null)
          TextButton(
            onPressed: _spin,
            child: Text(L10n.t(context, 'chat.wheelAgain')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.t(context, 'common.cancel')),
        ),
        if (_result != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: Text(L10n.t(context, 'chat.wheelSend')),
          ),
      ],
    );
  }
}
