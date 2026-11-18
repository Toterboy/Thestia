// Der Teil '_DecisionButtons'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Entscheidungs-Buttons (Annehmen/Ablehnen).
class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({required this.onAccept, required this.onReject});
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.t(context, 'dh.chat.timeUp'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // DIE KNOEPFE (BEFUND 18.11.2026, gefunden von einem Test):
            // Mit Symbol brauchte der Knopf mehr Platz, als er hat - bei
            // grosser Schrift (oder der breiten Test-Schrift im Test)
            // lief die Beschriftung ueber den Rand.
            //
            // DER WEG: Die Symbole sind weg. "Annehmen" und "Ablehnen"
            // sagen alles - und so passt die Beschriftung immer.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: Text(L10n.t(context, 'dh.chat.decline')),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(L10n.t(context, 'dh.chat.accept')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              L10n.t(context, 'dh.chat.bothMustAccept'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
