// Der Teil '_CooledMatchTile'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Kachel für "Erschlossene Funken" (status = cooled): gedimmt, mit
/// Re-Funke-Button (ein Tap, ohne Frist, ohne Benachrichtigung).
class _CooledMatchTile extends StatelessWidget {
  const _CooledMatchTile({
    required this.match,
    required this.onOpen,
    required this.onProfile,
    required this.onRespark,
    required this.onDelete,
  });

  final MatchWithState match;
  final VoidCallback onOpen;
  final VoidCallback onProfile;
  final VoidCallback onRespark;

  /// Endgültig löschen (NUTZERWUNSCH, 28.10.2026: "Funke
  /// löschen"). Bei einem archivierten Funke ist das die einzige
  /// Möglichkeit, ihn wegzuräumen - "Archivieren" waere
  /// sinnlos, er ist ja schon archiviert.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListTile(
        onTap: onOpen,
        leading: GestureDetector(
          onTap: onProfile,
          child: const CircleAvatar(child: Icon(Icons.person_outline)),
        ),
        // NUTZERWUNSCH (31.10.2026): "Verifizierung soll fuer alle
        // Personen sichtbar sein" - auch in der Funken-Liste.
        //
        // NUTZERWUNSCH (22.11.2026): "Name und Alter nicht nebeneinander
        // sondern untereinander aktuell (wenn refunke button da). So ist
        // das nicht okay!" Der Re-Funke-Button braucht Platz - in einer
        // Zeile wurde "Name, Alter" abgeschnitten. Der Name steht
        // jetzt oben, das Alter darunter.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(child: Text(p.name)),
                if (p.isVerified) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: L10n.t(context, 'verify.badge'),
                    child: Icon(
                      Icons.verified,
                      size: 18,
                      color: Colors.lightBlue.shade400,
                    ),
                  ),
                ],
                // Der automatische Funke (Migration 177) - auch hier
                // sichtbar, die Rueckfrage kommt beim Antippen.
                if (match.autoMatch) ...[
                  const SizedBox(width: 6),
                  const _AutoMatchBadge(),
                ],
              ],
            ),
            Text(
              '${p.age ?? '?'} ${L10n.t(context, 'common.years')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Text(
          p.bio.isNotEmpty ? p.bio : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            FilledButton.tonalIcon(
              onPressed: onRespark,
              icon: const Icon(Icons.local_fire_department, size: 18),
              label: Text(L10n.t(context, 'interests.resparkBtn')),
            ),
            // Endgueltig loeschen (NUTZERWUNSCH, 28.10.2026).
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: L10n.t(context, 'interests.deleteSpark'),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
