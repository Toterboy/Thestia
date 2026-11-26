// Der Teil '_VoiceMessage'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Sprachnachricht im NEUEN Design (v0.9.0): Play/Pause-Knopf,
/// Wellenform-Visualisierung (deterministische Balken aus der Message-ID)
/// mit Fortschritt und Dauer. Entschlüsselte Dateien werden nach der
/// Wiedergabe gelöscht (Audit M-17) - die Nachricht kann daher nur
/// EINMAL angehört werden; der Wiederholungs-Versuch zeigt einen
/// verständlichen Hinweis statt eines Roh-Fehlers.
class _VoiceMessage extends StatefulWidget {
  const _VoiceMessage({
    required this.msgId,
    required this.path,
    required this.durationSeconds,
    required this.textColor,
    required this.mine,
  });

  final String msgId;
  final String path;
  final int durationSeconds;
  final Color textColor;
  final bool mine;

  @override
  State<_VoiceMessage> createState() => _VoiceMessageState();
}
