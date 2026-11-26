// Der Teil '_CountdownText'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.endsAt});

  final DateTime endsAt;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}
