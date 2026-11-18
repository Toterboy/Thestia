// Der Teil '_OwnLikesTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _OwnLikesTab extends ConsumerStatefulWidget {
  const _OwnLikesTab({this.embedded = false, super.key});

  /// Eingebettet: Der Abschnitt steht in einem fremden Scrollbereich
  /// (der Seite) und scrollt deshalb NICHT selbst.
  ///
  /// NUTZERWUNSCH (28.10.2026): die Funken stehen immer unter dem
  /// Inhalt - dafuer braucht es EINEN Scrollbereich fuer die ganze
  /// Seite. Ohne dieses Flag haette jeder Abschnitt einen eigenen,
  /// und die Seite waere zweimal scrollbar.
  final bool embedded;

  @override
  ConsumerState<_OwnLikesTab> createState() => _OwnLikesTabState();
}
