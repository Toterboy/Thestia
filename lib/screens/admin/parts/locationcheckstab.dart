// Der Teil '_LocationChecksTab'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _LocationChecksTab extends ConsumerStatefulWidget {
  const _LocationChecksTab();

  @override
  ConsumerState<_LocationChecksTab> createState() => _LocationChecksTabState();
}
