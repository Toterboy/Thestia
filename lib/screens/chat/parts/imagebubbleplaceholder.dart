// Der Teil '_ImageBubblePlaceholder'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _ImageBubblePlaceholder extends StatelessWidget {
  const _ImageBubblePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [Colors.purple, Colors.blue]),
      ),
      child: const Center(
        child: Icon(Icons.image, color: Colors.white, size: 40),
      ),
    );
  }
}
