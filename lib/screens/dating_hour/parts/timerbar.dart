// Der Teil '_TimerBar'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Timer-Balken oben im Chat.
class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.remainingSeconds, required this.totalSeconds});
  final int remainingSeconds;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = remainingSeconds / totalSeconds;
    final color = remainingSeconds > 60
        ? Colors.green
        : remainingSeconds > 30
        ? Colors.orange
        : Colors.red;

    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(color: color.withValues(alpha: 0.2)),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
          if (remainingSeconds <= 30)
            Positioned.fill(child: _PulsingBorder(color: color)),
        ],
      ),
    );
  }
}
