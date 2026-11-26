// Der Teil '_UserReportsTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _UserReportsTab extends ConsumerStatefulWidget {
  const _UserReportsTab();

  @override
  ConsumerState<_UserReportsTab> createState() => _UserReportsTabState();
}
