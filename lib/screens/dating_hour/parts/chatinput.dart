// Der Teil '_ChatInput'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Chat-Eingabebereich.
///
/// Nutzt die eigene Tastatur der App (v0.10.1): die Systemtastatur des
/// Geraets sieht keinen einzelnen Buchstaben.
class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SecureComposer(
      controller: controller,
      hintText: L10n.t(context, 'dh.chat.hint'),
      onSend: onSend,
      // Im Dating Hour ist der Chat eine Zeile - Enter sendet.
      enterSends: true,
      maxLines: 3,
    );
  }
}
