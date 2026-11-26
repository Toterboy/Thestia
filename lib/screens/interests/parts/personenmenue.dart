// Der Teil '_PersonenMenue'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Die Werkzeuge für eine Person in einer Liste.
///
/// NUTZERWUNSCH (01.11.2026): "Die Bearbeitungstools auf der Interessen
/// Seite sehe ich auch nicht. Wenn sie mit Funken erst sichtbar werden
/// ist okay, aber sonst noch ergänzen, also entfernen, blockieren,
/// melden, anpinnen, archivieren usw."
///
/// Bei den FUNKEN gab es diese Werkzeuge schon (das Drei-Punkte-Menü
/// der Funken-Kachel). Bei den LIKES fehlten sie - und die waren nur
/// erreichbar, wenn überhaupt ein Funke existierte. Wer nur geliked
/// hat, konnte nichts machen.
///
/// Das Menü hängt deshalb die allgemeinen Aktionen (Profil,
/// Blockieren, Melden) an die aktionsspezifischen (entfernen,
/// ignorieren, zurück liken) an - und wird von beiden Kachelarten
/// benutzt, damit es an beiden gleich aussieht.
class _PersonenMenue extends ConsumerWidget {
  const _PersonenMenue({
    required this.personId,
    required this.personName,
    this.aktionen = const [],
    this.onAktion,
    this.aktiv = true,
  });

  final String personId;
  final String personName;

  /// Die aktionsspezifischen Einträge.
  final List<_MenueEintrag> aktionen;

  /// Aufruf für einen aktionsspezifischen Eintrag.
  final void Function(String wert)? onAktion;

  /// Bei einem laufenden Vorgang ist das Menü gesperrt.
  final bool aktiv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: L10n.t(context, 'chat.more'),
      enabled: aktiv,
      onSelected: (wert) => _ausfuehren(context, ref, wert),
      itemBuilder: (ctx) => [
        for (final a in aktionen)
          PopupMenuItem(
            value: a.wert,
            child: ListTile(
              leading: Icon(a.icon, color: a.rot ? Colors.red : null),
              title: Text(a.label),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (aktionen.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'profil',
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(L10n.t(context, 'profile.detail.aboutMe')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'melden',
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(L10n.t(context, 'profile.detail.reportUser')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'blockieren',
          child: ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(L10n.t(context, 'profile.detail.blockUser')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _ausfuehren(BuildContext context, WidgetRef ref, String wert) {
    switch (wert) {
      case 'profil':
        context.push(AppRoutes.profileDetailPath(personId));
      case 'melden':
        showReportUserDialog(
          context: context,
          ref: ref,
          reportedUserId: personId,
          reportedUserName: personName,
        );
      case 'blockieren':
        unawaited(bestaetigeBlockieren(context, ref, personId, personName));
      default:
        onAktion?.call(wert);
    }
  }
}
