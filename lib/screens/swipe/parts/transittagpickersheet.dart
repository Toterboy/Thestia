// Der Teil '_TransitTagPickerSheet'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _TransitTagPickerSheet extends StatefulWidget {
  const _TransitTagPickerSheet({
    required this.titleKey,
    required this.hintKey,
    required this.requireSelection,
    this.customHintKey,
    this.initialCustomText = '',
  });

  final String titleKey;
  final String hintKey;
  final bool requireSelection;
  final String? customHintKey;
  final String initialCustomText;

  @override
  State<_TransitTagPickerSheet> createState() => _TransitTagPickerSheetState();
}
