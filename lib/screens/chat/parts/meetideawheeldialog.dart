// Der Teil '_MeetIdeaWheelDialog'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Das Ideen-Rad (v0.8.0): dreht mit abnehmender Geschwindigkeit und
/// landet auf einer zufälligen Date-Kategorie. Rückgabe via Navigator.pop
/// (gewählter Vorschlag) oder null (Abbruch).
class _MeetIdeaWheelDialog extends StatefulWidget {
  const _MeetIdeaWheelDialog({required this.categories});

  final List<String> categories;

  @override
  State<_MeetIdeaWheelDialog> createState() => _MeetIdeaWheelDialogState();
}
