// Der Teil '_Page'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_privacy_once_screen.dart';

class _Page extends StatelessWidget {
  const _Page({
    required this.questionKey,
    required this.subtitle,
    required this.child,
  });

  /// Interview-Frage als L10n-Key (Thestia-Bubble statt Formular-Überschrift).
  final String questionKey;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      // NUTZERWUNSCH (01.11.2026): "Der scrollstrich in der Einrichtung
      // kann etwas weiter an den Rand."
      //
      // Vorher lag das GANZE Padding (all: 24) AUSSERHALB des
      // Scrollbars - der Strich stand damit 24 px vom Kartenrand weg
      // (plus den System-Rand der Navigationsleiste). Jetzt sitzt der
      // Scrollbar am Kartenrand, und nur der INHALT hat seinen
      // Abstand.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Interview-Stil: Thestia stellt die Frage (Chat-Optik).
                InterviewBubble(text: L10n.t(context, questionKey)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  // Platz für die Tastatur: Der Inhalt bleibt so über dem
                  // Keyboard scrollbar, statt dahinter zu verschwinden.
                  bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
