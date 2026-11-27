// Der Teil '_CooledMatchTile'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
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
  /// Möglichkeit, ihn wegzuräumen - "Archivieren" wäre
  /// sinnlos, er ist ja schon archiviert.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    // BEFUND (27.11.2026, Betreiber): "Die Schrift links vom Button ist
    // einzeln jeder Buchstabe untereinander."
    //
    // Die Ursache: Alle drei Aktionen standen in der `trailing`-Leiste
    // einer ListTile. Die Leiste braucht rund 250 Pixel - auf einem
    // kleinen Telefon blieb für den Text nur eine Zeichenbreite übrig,
    // und Flutter brach den Text deshalb Buchstabe für Buchstabe um.
    //
    // Die Lösung: Der Text bekommt den ganzen Rest der Breite (er
    // bricht über zwei oder drei Zeilen um, wie gewünscht), und die
    // Aktionen stehen in einer eigenen Spalte daneben: der Re-Funke-
    // Knopf oben, die beiden kleinen Knöpfe darunter.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Das Profil (ein Tap öffnet es).
                GestureDetector(
                  onTap: onProfile,
                  child: const CircleAvatar(child: Icon(Icons.person_outline)),
                ),
                const SizedBox(width: 12),
                // Der Text: Name, Alter und Beschreibung. Er bekommt
                // den ganzen Rest der Breite.
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // NUTZERWUNSCH (31.10.2026): "Verifizierung soll
                          // für alle Personen sichtbar sein" - auch in der
                          // Funken-Liste.
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
                              // Der automatische Funke (Migration 177) -
                              // auch hier sichtbar, die Rückfrage kommt
                              // beim Antippen.
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
                          const SizedBox(height: 2),
                          Text(
                            p.bio.isNotEmpty
                                ? p.bio
                                : L10n.t(context, 'interests.noBio'),
                            // ZWEI BIS DREI ZEILEN: Der Text bricht um,
                            // aber nicht Buchstabe für Buchstabe.
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // DIE AKTIONEN: eine eigene Zeile unter dem Text.
            //
            // BEFUND (27.11.2026, Betreiber): "Die Schrift links vom
            // Button ist einzeln jeder Buchstabe untereinander."
            //
            // DER GRUND: Der Knopf "Re-Funke" ist allein schon 170 Pixel
            // breit (mit dem Wort). Neben dem Text blieb davon nur eine
            // Zeichenbreite übrig - und Flutter brach den Text deshalb
            // Buchstabe für Buchstabe um. Stehen die Aktionen unter dem
            // Text, hat der Text die ganze Breite (über zwei bis drei
            // Zeilen) - und bei großer Schrift rutschen die Knöpfe auf
            // eine zweite Zeile, statt etwas abzuschneiden.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRespark,
                  icon: const Icon(Icons.local_fire_department, size: 18),
                  label: Text(L10n.t(context, 'interests.resparkBtn')),
                ),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: L10n.t(context, 'profile.detail.aboutMe'),
                  onPressed: onProfile,
                ),
                // Endgültig löschen (NUTZERWUNSCH, 28.10.2026).
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: L10n.t(context, 'interests.deleteSpark'),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
