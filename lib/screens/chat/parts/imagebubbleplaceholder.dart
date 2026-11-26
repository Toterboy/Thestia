// Der Teil '_ImageBubblePlaceholder'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _ImageBubblePlaceholder extends StatelessWidget {
  const _ImageBubblePlaceholder();

  @override
  Widget build(BuildContext context) {
    // NUTZERWUNSCH (22.11.2026): "Keinen Rand um Bilder im Chat." Der
    // farbige Verlauf (lila/blau) um das Bild-Symbol wirkte wie ein
    // Rahmen - der Platzhalter ist jetzt neutral grau, wie der
    // View-Once-Platzhalter.
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade300,
      ),
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 40),
      ),
    );
  }
}
