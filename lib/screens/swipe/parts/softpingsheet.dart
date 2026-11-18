// Der Teil '_SoftPingSheet'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Soft-Ping-Sheet: vorgefertigte, freundliche Saetze + optionale kurze
/// eigene Zeile (max. 140 Zeichen, serverseitig gekuerzt/gefiltert).
class _SoftPingSheet extends ConsumerStatefulWidget {
  const _SoftPingSheet({required this.token});

  final String token;

  @override
  ConsumerState<_SoftPingSheet> createState() => _SoftPingSheetState();
}
