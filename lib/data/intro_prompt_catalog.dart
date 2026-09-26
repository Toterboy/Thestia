/// Rotierende Vorstellungs-Prompts (v0.9.2, Roadmap-Punkt 7).
///
/// BISHER: `intro_editor.dart` zeigte vier feste Chips. Nichts rotierte -
/// wer die App oft öffnete, tippte immer dieselben vier Fragen an.
///
/// JETZT: vier Themen mit je drei offenen Erzähl-Prompts. Angezeigt wird
/// pro Thema eine Frage, die sich stündlich verschiebt. Dadurch bekommt
/// jeder Nutzer bei jedem Oeffnen eine frische Mischung, ohne dass die Chip-Leiste
/// überladen wirkt.
///
/// ZWEI EIGENTÜMLICHKEITEN, die absicht sind:
///
/// 1. **Die Auswahl darf sich nicht verschieben, während der Editor offen
///    ist.** Ein Chip, der unter dem Finger weiterspringt, ist unbenutzbar.
///    Deshalb wird der Seed einmal in `initState` gewürfelt und dann für die
///    Lebensdauer des Widgets gehalten - nicht bei jedem `build` neu
///    berechnet.
///
/// 2. **Offene Prompts statt Quizfragen.** Die Vorstellung soll erzählt
///    werden, nicht Multiple-Choice. Die Formulierungen sind bewusst
///    offen ("Wie sieht dein gewöhnlicher Sonntag aus?") und vermeiden
///    sensible Bereiche (Familie, Geld, Gesundheit).
///
/// Die Prompts sind L10n-Keys. `test/intro_prompt_catalog_test.dart` prüft,
/// dass jeder Key in DE **und** EN existiert.
library;

class IntroPromptTheme {
  const IntroPromptTheme({
    required this.id,
    required this.promptKeys,
  });

  /// Technische ID, nur für Rotation und Tests.
  final String id;

  /// L10n-Keys der Prompts zu diesem Thema, in fester Reihenfolge.
  final List<String> promptKeys;
}

class IntroPromptCatalog {
  const IntroPromptCatalog._();

  /// Themen in Anzeigereihenfolge. Jedes bekommt einen eigenen Chip.
  static const List<IntroPromptTheme> themes = [
    IntroPromptTheme(id: 'everyday', promptKeys: [
      'intro.prompt.weekend',
      'intro.prompt.everyday.sunday',
      'intro.prompt.everyday.coffee',
    ]),
    IntroPromptTheme(id: 'people', promptKeys: [
      'intro.prompt.friends',
      'intro.prompt.people.proud',
      'intro.prompt.people.call',
    ]),
    IntroPromptTheme(id: 'humor', promptKeys: [
      'intro.prompt.laugh',
      'intro.prompt.humor.embarrassing',
      'intro.prompt.humor.silent',
    ]),
    IntroPromptTheme(id: 'dream', promptKeys: [
      'intro.prompt.dream',
      'intro.prompt.dream.learn',
      'intro.prompt.dream.trip',
    ]),
  ];

  /// Alle Keys flach, für den Paritätstest.
  static List<String> get allPromptKeys =>
      [for (final t in themes) ...t.promptKeys];

  /// Liefert pro Thema [perTheme] Prompts, verschoben um [seed].
  ///
  /// Der Seed muss pro Editor-Instanz **konstant** bleiben, sonst
  /// springen die Chips während des Bearbeitens (siehe Klassendoku).
  ///
  /// Der Theme-Zähler geht in den Index ein, damit die Themen NICHT im
  /// Gleichtakt rotieren: sonst bekäme man immer "den ersten Prompt aus
  /// jedem Thema" zusammen und die Vielfalt wäre nur drei Varianten breit.
  /// Mit Offset sind es echte Mischungen (Muster wie Dating-Hour-Fragen).
  static List<String> rotated({required int seed, int perTheme = 1}) {
    if (perTheme < 1) return const [];
    return [
      for (var themeIndex = 0; themeIndex < themes.length; themeIndex++)
        for (var i = 0; i < perTheme; i++)
          themes[themeIndex]
              .promptKeys[(seed + themeIndex + i) % themes[themeIndex].promptKeys.length],
    ];
  }

  /// Stabiler Seed aus der Uhrzeit: wechselt stündlich, aber nicht
  /// sekündlich. Wird einmal beim Öffnen des Editors gezogen.
  static int seedFor(DateTime now) =>
      (now.difference(DateTime(now.year, now.month, now.day)).inHours) +
      now.day * 7;
}
