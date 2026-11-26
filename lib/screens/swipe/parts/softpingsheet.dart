// Der Teil '_SoftPingSheet'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Soft-Ping-Sheet: vorgefertigte, freundliche Sätze + optionale kurze
/// eigene Zeile (max. 140 Zeichen, serverseitig gekürzt/gefiltert).
class _SoftPingSheet extends ConsumerStatefulWidget {
  const _SoftPingSheet({required this.token});

  final String token;

  @override
  ConsumerState<_SoftPingSheet> createState() => _SoftPingSheetState();
}
