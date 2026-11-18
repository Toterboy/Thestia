// Der Teil '_PerSecond'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Baut sein Child jede Sekunde neu (v0.9.1, Akku): Sekunden-Anzeigen
/// (Countdown, Timer-Balken) ticken isoliert, statt den ganzen Screen
/// pro Sekunde zu rebuilden.
class _PerSecond extends StatefulWidget {
  const _PerSecond({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_PerSecond> createState() => _PerSecondState();
}
