// Der Teil '_WaitingForPartner'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Warten auf Partner-Entscheidung.
class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'dh.chat.voted'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'dh.chat.resultPending'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (onBack != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: Text(L10n.t(context, 'dh.chat.backToOverview')),
                onPressed: onBack,
              ),
          ],
        ),
      ),
    );
  }
}
