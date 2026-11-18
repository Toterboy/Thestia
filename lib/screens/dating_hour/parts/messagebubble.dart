// Der Teil '_MessageBubble'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Nachrichtenblase.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.mine,
    this.showName = false,
    this.senderName = '',
  });
  final Message msg;
  final bool mine;

  /// Namens-Header über der Bubble anzeigen (Gruppenstart)?
  final bool showName;

  /// Anzuzeigender Absendername.
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    String timeLabel = '';
    bestEffortSync('Hm.format', () {
      timeLabel = DateFormat.Hm().format(msg.timestamp.toLocal());
    });

    // Der System-Hinweis (z. B. die Fuenf-Minuten-Marke) steht
    // mittig in der Mitte - so wie die Eisbrecher-Fragen im normalen
    // Chat. Er gehoert niemandem, also steht er auch nicht links
    // oder rechts bei einer Person.
    if (msg.type == MessageType.notice) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            msg.text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showName && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
              child: Text(
                senderName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: mine
                    ? const Radius.circular(4)
                    : const Radius.circular(18),
                bottomLeft: mine
                    ? const Radius.circular(18)
                    : const Radius.circular(4),
              ),
            ),
            child: Text(msg.text, style: TextStyle(color: textColor)),
          ),
          if (timeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
              child: Text(
                timeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
