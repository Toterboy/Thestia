// Der Teil '_BugReportsTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _BugReportsTab extends ConsumerStatefulWidget {
  const _BugReportsTab();

  @override
  ConsumerState<_BugReportsTab> createState() => _BugReportsTabState();
}
