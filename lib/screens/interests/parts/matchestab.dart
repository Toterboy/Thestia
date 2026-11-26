// Der Teil '_MatchesTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _MatchesTab extends ConsumerStatefulWidget {
  const _MatchesTab({this.embedded = false, super.key});

  /// Eingebettet: Der Abschnitt steht im Scrollbereich der Seite und
  /// scrollt deshalb nicht selbst (siehe [_OwnLikesTab.embedded]).
  final bool embedded;

  @override
  ConsumerState<_MatchesTab> createState() => _MatchesTabState();
}
