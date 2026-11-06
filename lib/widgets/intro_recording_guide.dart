import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Drei-Schritte-Leitfaden als Begleitung WAEHREND der Audio-Aufnahme.
///
/// WARUM (03.11.2026, ROADMAP-Punkt "Vorstellungs-Vorlagen (Text +
/// Audio)"): Die Text-Vorstellung hat rotierende Prompt-Karten
/// (`lib/data/intro_prompt_catalog.dart`), die Audio-Vorstellung hatte
/// nichts. Wer 60 Sekunden redete, lief ins Leere und sagte am Ende
/// "Ja, also... ich bin halt so".
///
/// Der Leitfaden gibt drei Winkel in fester Reihenfolge:
///
///   1. Wer bist du?
///   2. Was macht dich aus?
///   3. Warum bist du hier?
///
/// KEINE PFlicht: Die Aufnahme bleibt frei, der Text bleibt frei. Der
/// Leitfaden ist eine Stütze, kein Fragebogen - wer ihn ignorieren
/// will, kann das. Er verhindert nur die leere Vorstellung.
///
/// ZWEI ENTSCHEIDUNGEN, die absicht sind:
///
/// 1. **Automatisch nach Zeit, aber ueberschreibbar.** Ohne Automatik
///    haette man drei Schritte manuell antippen muessen, bevor man
///    ueberhaupt anfangen kann - das ist genau die Huerde, die wir
///    abbauen wollen. Mit Automatik laeuft der Leitfaden von selbst;
///    ein Tipp auf einen Schritt uebernimmt aber die Steuerung (der
///    Nutzer hat das letzte Wort).
///
/// 2. **Nach dem dritten Schritt bleibt der dritte stehen.** Wer weiter
///    redet, soll nicht in eine Schleife geschickt werden. Die
///    Aufnahme laeuft bis 5 Minuten, der Leitfaden hat aber nur drei
///    Winkel - danach ist er erledigt und traegt nichts mehr bei.
class IntroRecordingGuide extends StatefulWidget {
  const IntroRecordingGuide({
    super.key,
    required this.elapsedSeconds,
    this.paused = false,
  });

  /// Laufzeit der Aufnahme in Sekunden. Die Pause zaehlt nicht mit
  /// (das ist die Semantik von `_recordSeconds` im Editor).
  final int elapsedSeconds;

  /// Bei Pause wird der Leitfaden abgeblendet - es passiert ja nichts.
  final bool paused;

  /// Dauer eines Schrittes in Sekunden.
  ///
  /// 15 Sekunden: kurz genug, dass alle drei Winkel auch in einer
  /// kurzen Vorstellung (Mindestlaenge 10 Sekunden) vorkommen, lang
  /// genug, dass man pro Winkel mindestens einen Satz sagen kann.
  static const int stepSeconds = 15;

  /// Die drei Winkel (L10n-Keys), in fester Reihenfolge.
  static const List<String> stepKeys = <String>[
    'intro.guide.step1',
    'intro.guide.step2',
    'intro.guide.step3',
  ];

  /// Welcher Schritt ist nach [seconds] Aufnahmezeit aktiv?
  ///
  /// Nach dem dritten Schritt bleibt der dritte stehen.
  static int stepForSeconds(int seconds) {
    if (seconds <= 0) return 0;
    final index = seconds ~/ stepSeconds;
    if (index >= stepKeys.length) return stepKeys.length - 1;
    return index;
  }

  @override
  State<IntroRecordingGuide> createState() => _IntroRecordingGuideState();
}

class _IntroRecordingGuideState extends State<IntroRecordingGuide> {
  /// Vom Nutzer gewaehlter Schritt. Solange `null`, laeuft die
  /// automatische Auswahl nach Zeit; ein Tipp uebernimmt dauerhaft.
  int? _manualStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final automatisch = IntroRecordingGuide.stepForSeconds(
      widget.elapsedSeconds,
    );
    final aktiv = _manualStep ?? automatisch;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Opacity(
        opacity: widget.paused ? 0.55 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forum_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.t(context, 'intro.guide.title'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < IntroRecordingGuide.stepKeys.length; i++)
              _stepRow(context, i, aktiv),
            const SizedBox(height: 2),
            Text(
              L10n.t(context, 'intro.guide.hint'),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Eine Zeile des Leitfadens: Nummer, Text, Zustand.
  ///
  /// Drei Zustaende, klar unterscheidbar:
  ///   * aktiv   - gefuellter Kreis, Text in der Akzentfarbe, fett
  ///   * erledigt- Haken im Kreis, Text zurueckgenommen
  ///   * offen   - offener Kreis, Text zurueckgenommen
  Widget _stepRow(BuildContext context, int index, int aktiv) {
    final scheme = Theme.of(context).colorScheme;
    final istAktiv = index == aktiv;
    final istVorbei = index < aktiv;

    return InkWell(
      onTap: () => setState(() => _manualStep = index),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            // Nummer-Kreis: gefuellt = aktiv, Haken = erledigt.
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: istAktiv
                    ? scheme.primary
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                border: Border.all(
                  color: istAktiv || istVorbei
                      ? scheme.primary
                      : scheme.outlineVariant,
                ),
              ),
              child: istVorbei
                  ? Icon(Icons.check, size: 14, color: scheme.primary)
                  : Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: istAktiv
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                L10n.t(context, IntroRecordingGuide.stepKeys[index]),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: istAktiv ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: istAktiv ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (istAktiv)
              Icon(Icons.graphic_eq, size: 16, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
