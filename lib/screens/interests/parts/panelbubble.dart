// Der Teil '_PanelBubble'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Die Blase unter den Reitern.
///
/// Der Inhalt startet direkt unter dem Reiter und schiebt die Funken
/// beim Aufklappen nach unten.
///
/// Die Ecken sind oben wie unten gerundet (NUTZERWUNSCH 31.10.2026):
/// Der Reiter ist jetzt eine Pille, und eine flach angeschlossene
/// Blase darunter passte nicht mehr dazu - die gerundete Unterseite
/// des Reiters stiesse auf die eckige Oberseite der Blase.
class _PanelBubble extends StatelessWidget {
  const _PanelBubble({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
          bottom: Radius.circular(24),
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      // GLEICHE HOEHE (NUTZERWUNSCH 01.11.2026: "Gesendet und
      // Erhalten sind die Pop up maessigen Fenster nicht gleich gross
      // nach unten").
      //
      // Die beiden Leertexte haben verschiedene Laenge, dadurch waren
      // die Fenster unterschiedlich hoch - und beim Wechsel ruckte
      // alles darunter nach. Die Mindesthoehe macht beide gleich
      // hoch, solange der Inhalt nicht ueber sie hinaus waechst.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 236),
        child: child,
      ),
    );
  }
}
