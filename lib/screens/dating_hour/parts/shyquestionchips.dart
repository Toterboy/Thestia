// Der Teil '_ShyQuestionChips'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

/// Frage-Karten für Schüchterne (v0.8.0): 3 thematische sanfte Vorschläge
/// (Reise / Alltag / Träume) - ein Tap übernimmt die Frage. Die Fragen
/// rotieren pro Runde, damit es nicht repetitive Textbausteine sind.
class _ShyQuestionChips extends StatelessWidget {
  const _ShyQuestionChips({required this.onPick});

  final void Function(String question) onPick;

  static const _themes = <String, List<String>>{
    'Reise ✈️': [
      'Welche Stadt möchte du unbedingt mal besuchen?',
      'Bester Reise-Moment deines Lebens?',
      'Flug, Zug oder Auto, was magst du am liebsten?',
    ],
    'Alltag ☀️': [
      'Was war heute dein kleines Glück?',
      'Kaffee oder Tee, und wie dazu?',
      'Was hilft dir wirklich beim Abschalten?',
    ],
    'Träume 🌙': [
      'Wovon würdest du am liebsten träumen?',
      'Was würdest du machen mit einem freien Monat?',
      'Welcher Traum hat noch nicht angefangen zu brennen?',
    ],
  };

  @override
  Widget build(BuildContext context) {
    // Pro Theme eine Frage, rotiert pro Aufruf (Datum + Stunde).
    final rotation = DateTime.now().hour;
    final chips = <(String, String)>[];
    var themeIndex = 0;
    for (final entry in _themes.entries) {
      final questions = entry.value;
      final q = questions[(rotation + themeIndex) % questions.length];
      chips.add((entry.key, q));
      themeIndex++;
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (theme, question) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(theme, style: const TextStyle(fontSize: 12)),
                tooltip: question,
                onPressed: () => onPick(question),
              ),
            ),
        ],
      ),
    );
  }
}
