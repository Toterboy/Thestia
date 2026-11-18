// Der Teil '_MatchTile'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _MatchTile extends ConsumerWidget {
  const _MatchTile({
    required this.match,
    required this.onTap,
    required this.onProfile,
    required this.onCool,
    required this.onHide,
    required this.onPin,
    required this.onDelete,
    this.pinned = false,
    this.unreadCount = 0,
  });

  /// Wie viele Nachrichten von dieser Person ungelesen sind.
  ///
  /// BEFUND (09.11.2026): "Zudem sollen Chats mit ungelesenen
  /// Nachrichten hervorgehoben ... sein."
  final int unreadCount;

  final MatchWithState match;
  final VoidCallback onTap;
  final VoidCallback onProfile;
  final VoidCallback onCool;
  final VoidCallback onHide;

  /// Fixiert (NUTZERWUNSCH, 28.10.2026: "fixieren").
  final VoidCallback onPin;

  /// Endgültig löschen (NUTZERWUNSCH, 28.10.2026: "Funke
  /// löschen").
  final VoidCallback onDelete;

  /// Ist der Funke fixiert? Dann steht er oben und traegt eine Nadel.
  final bool pinned;

  /// Blockieren aus dem Funken-Menü (NUTZERWUNSCH): Gleicher Dialog und
  /// Ablauf wie im Chat (Bestätigung -> blockUser -> Funken-Tab).
  ///
  /// Die Arbeit macht [bestaetigeBlockieren] - die kann jede Person,
  /// nicht nur einen Funke. Vorher gab es diese Trennung, und genau
  /// deshalb war das Blockieren bei einem blossen Like nicht
  /// erreichbar (NUTZERWUNSCH 01.11.2026).
  Future<void> _confirmBlockTile(
    BuildContext context,
    WidgetRef ref,
    MatchWithState m,
  ) async {
    await bestaetigeBlockieren(context, ref, m.partner.id, m.partner.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = match.partner;
    // Quiz-Hinweis erst nach 50-70 Nachrichten (pro Chat deterministisch,
    // gleiche Schwelle wie im Chat-Screen).
    final threshold = 50 + (match.matchId.toString().hashCode.abs() % 21);
    // Der QUIZ-HINWEIS bleibt unveraendert: er zaehlt die Nachrichten
    // in DIESEM Chat (lokaler Verlauf) - so wie es seit jeher war.
    //
    // BEFUND (11.11.2026, Betreiber): "Also nur fuer v0.10.1 nicht
    // drueber." Das Verhalten der bestehenden Funktionen bleibt, was es
    // ist; neu ist nur die kleine ZAHL in der Kachel.
    final lokaleNachrichten = ref
        .watch(chatProvider.notifier)
        .messagesFor(match.matchId.toString())
        .length;
    final showQuizHint =
        !match.quizPassed &&
        match.createdVia == 'find_match' &&
        lokaleNachrichten >= threshold;
    final scheme = Theme.of(context).colorScheme;
    final ungelesen = unreadCount > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // BEFUND (09.11.2026, Betreiber): "Zudem sollen Chats mit
      // ungelesenen Nachrichten hervorgehoben ... sein." Der Rand und
      // die Flaeche faellen auf, solange ungelesene Nachrichten da sind.
      color: ungelesen ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: ungelesen
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: ListTile(
        onTap: onTap,
        leading: GestureDetector(
          onTap: onProfile,
          child: CircleAvatar(
            radius: 28,
            child: match.quizPassed
                ? const Icon(Icons.person)
                : const Icon(Icons.visibility_off),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                [
                  '${p.name}, ${p.age ?? '?'}',
                  if (p.distanceKm > 0)
                    p.distanceLabel((key) => L10n.t(context, key)),
                ].join(' · '),
              ),
            ),
            // Die kleine Zahl der Nachrichten dieser Person.
            //
            // BEFUND (09.11.2026, Betreiber): "Außerdem soll mit einer
            // kleinen Zahl gekennzeichnet werden, wie viele Nachrichten
            // die Person geschrieben hat."
            //
            // BEFUND (11.11.2026): Die Zahl kommt vom SERVER
            // (Migration 210) - sie stimmt damit auf allen Geraeten und
            // steht auch da, wenn der Chat hier nie geoeffnet wurde.
            // Neu in v0.10.1; das Verhalten der uebrigen Kachel
            // (Quiz-Hinweis u. Ae.) bleibt unveraendert.
            if (match.messageCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${match.messageCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            // Der automatische Funke (Migration 177): er kam nicht von
            // beiden Seiten zustande. Das Sternchen weist darauf hin -
            // die Rueckfrage kommt beim Antippen.
            if (match.autoMatch) ...[
              const SizedBox(width: 6),
              const _AutoMatchBadge(),
            ],
            // Die Nadel: der Funke ist fixiert und steht deshalb oben.
            if (pinned)
              Icon(
                Icons.push_pin,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback).
          ],
        ),
        subtitle: Text(
          match.quizPassed
              ? L10n.t(context, 'interests.photoUnlocked')
              : showQuizHint
              ? L10n.t(context, 'interests.quizPending')
              : p.bio.isNotEmpty
              ? p.bio
              : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // v0.9.1: Kein Bild-/Status-Icon mehr; die 3 Punkte stehen ganz
        // rechts.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: L10n.t(context, 'chat.more'),
              onSelected: (value) {
                switch (value) {
                  case 'pin':
                    onPin();
                  case 'cool':
                    onCool();
                  case 'delete':
                    onDelete();
                  case 'hide':
                    onHide();
                  case 'report':
                    showReportUserDialog(
                      context: context,
                      ref: ref,
                      reportedUserId: p.id,
                      reportedUserName: p.name,
                    );
                  case 'block':
                    _confirmBlockTile(context, ref, match);
                }
              },
              itemBuilder: (ctx) => [
                // Fixieren (NUTZERWUNSCH, 28.10.2026: "fixieren").
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(
                      pinned ? Icons.push_pin_outlined : Icons.push_pin,
                    ),
                    title: Text(L10n.t(context, 'interests.pinSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Archivieren (frueher "kühlen" - der Name war
                // missverstaendlich, der Funke wird ja nicht geloescht).
                PopupMenuItem(
                  value: 'cool',
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(L10n.t(context, 'interests.archiveSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Endgueltig loeschen.
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: Text(L10n.t(context, 'interests.deleteSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'hide',
                  child: ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: Text(L10n.t(context, 'interests.hideOneBtn')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                // NUTZERWUNSCH: Melden/Blockieren auch im Funken-Menü.
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(L10n.t(context, 'profile.detail.reportUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text(L10n.t(context, 'profile.detail.blockUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
