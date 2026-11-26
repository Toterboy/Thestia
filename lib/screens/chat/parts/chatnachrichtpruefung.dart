// Die Nachricht überdenken (NUTZERWUNSCH 26.11.2026).
//
// DER WEG: Der Nutzer stellt im Drei-Punkte-Menü des Chats ein, WANN
// die App vor dem Senden nachfragt und FÜR WEN. Das Ergebnis steht in
// den App-Einstellungen (global) und in den Ausnahmen je Kontakt.
//
// Die Datei ist ein eigener Teil, weil die Hauptdatei des Chats sonst
// über die Grenze von 1000 Zeilen käme (test/code_datei_groessen_test.dart).

part of '../chat_detail_screen.dart';

extension _ChatNachrichtPruefung on _ChatDetailScreenState {
  /// Der Eintrag "Nachricht überdenken" im Drei-Punkte-Menü.
  ///
  /// DER WEG: Er steht in der Gruppe "Gespräch" - es geht um das
  /// Senden, nicht um die Sicherheit.
  PopupMenuItem<String> _nachrichtPruefMenueEintrag() {
    return PopupMenuItem(
      value: 'nachrichtPruef',
      child: ListTile(
        leading: const Icon(Icons.psychology_alt_outlined),
        title: Text(L10n.t(context, 'chat.nachrichtPruefTitle')),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  /// Öffnet die Einstellungen "Nachricht überdenken" für diesen Chat.
  Future<void> _zeigeNachrichtPruefEinstellungen() async {
    final match = _match;
    if (match == null) return;
    await zeigeNachrichtPruefEinstellungen(
      context,
      ref,
      kontaktId: match.partner.id,
      kontaktName: match.partner.name,
    );
  }

  /// Der Extra-Knopf im Eingabefeld (prüft die Nachricht von Hand).
  ///
  /// DER WEG: Der Knopf steht nur da, wenn er etwas zu tun hat - im
  /// Modus "aus" wäre er eine tote Fläche. Als Liste, damit er
  /// optional in die Eingabeleiste passt.
  List<Widget> _nachrichtPruefKnopf() {
    final match = _match;
    if (match == null) return const <Widget>[];
    final einstellung = ref.read(settingsProvider).nachrichtPruef;
    if (!einstellung.zeigtKnopf(match.partner.id)) return const <Widget>[];
    return <Widget>[
      IconButton(
        icon: const Icon(Icons.psychology_alt_outlined),
        tooltip: L10n.t(context, 'chat.nachrichtPruefKnopf'),
        onPressed: _pruefeVonHand,
      ),
    ];
  }
}
