// Der Teil '_CountdownTextState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endsAt.difference(DateTime.now());
    final m = remaining.inMinutes.clamp(0, 45);
    final s = remaining.inSeconds.clamp(0, 45 * 60) % 60;
    return Text(
      L10n.tf(context, 'transit.remaining', {
        'time': '$m:${s.toString().padLeft(2, '0')}',
      }),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
