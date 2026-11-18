// Der Teil '_AvatarRetryLoader'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_detail_screen.dart';

/// Platzhalter mit Retry-Tap für Partner-Avatare (NUTZERWUNSCH: "Bild
/// einfach nicht sichtbar" -> der Nutzer kann EINMAL selbst nachladen,
/// statt still nichts zu sehen; löscht auch den Memory-Cache-Eintrag).
class _AvatarRetryLoader extends StatelessWidget {
  const _AvatarRetryLoader({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onRetry,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.refresh,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
