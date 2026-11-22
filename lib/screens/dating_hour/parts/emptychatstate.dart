// Der Teil '_EmptyChatState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Leerer Chat-State mit Ice-Breaker.
class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({
    required this.partnerName,
    required this.onIceBreaker,
  });
  final String partnerName;
  final VoidCallback onIceBreaker;

  @override
  Widget build(BuildContext context) {
    // BEFUND (22.11.2026, Fuzzing): Der Leer-Zustand ist 228 Pixel hoch
    // (Symbol, zwei Texte, Knopf). Ist der Chatbereich kleiner - im
    // Entscheidungsfenster stehen unten die Frage-Chips, das
    // Eingabefeld UND die Entscheidungs-Knoepfe -, lief der Inhalt
    // aus dem Bild: "A RenderFlex overflowed by 48 pixels".
    //
    // DER WEG: Der Inhalt darf scrollen. Mit dem ConstrainedBox bleibt
    // er mittig, solange er passt; passt er nicht, wird gescrollt statt
    // zu ueberlaufen.
    return LayoutBuilder(
      builder: (context, grenzen) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: grenzen.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10n.tf(context, 'dh.chat.sayHello', {'name': partnerName}),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ihr habt 5 Minuten Zeit, euch kennenzulernen. '
                    'Danach entscheidet ihr beide: Funke oder weitersuchen?',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lightbulb_outline),
                    label: Text(L10n.t(context, 'dh.chat.icebreakerBtn')),
                    onPressed: onIceBreaker,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
