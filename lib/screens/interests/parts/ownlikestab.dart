// Der Teil '_OwnLikesTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
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
  /// Inhalt - dafür braucht es EINEN Scrollbereich für die ganze
  /// Seite. Ohne dieses Flag hätte jeder Abschnitt einen eigenen,
  /// und die Seite wäre zweimal scrollbar.
  final bool embedded;

  @override
  ConsumerState<_OwnLikesTab> createState() => _OwnLikesTabState();
}
