import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zwei gekoppelte Regler für die Altersspanne (Mindest-/Höchstalter).
///
/// WICHTIG: Bewusst KEIN RangeSlider. Bei identischen Werten (z. B. 18-18)
/// lässt ein RangeSlider nur den Start-Regler greifen - der End-Regler ist
/// nicht erreichbar und die Werte "frieren" ein (die Regler wirken
/// ausgegraut und bewegen sich nicht). Zwei einzelne Slider schieben sich
/// stattdessen gegenseitig mit:
///  - Mindestalter über das Höchstalter gezogen -> Höchstalter wandert mit
///  - Höchstalter unter das Mindestalter gezogen -> Mindestalter wandert mit
///
/// Die GRENZEN (boundsMin/boundsMax) müssen die STATISCHEN Sicherheits-
/// grenzen sein (AgeSafetyRules.minFilterAge/maxFilterAge) - NIEMALS die
/// aktuell gewählten Werte, sonst kollabiert der Spielraum auf exakt die
/// Auswahl und nichts lässt sich mehr bewegen.
class AgeRangeSliders extends StatelessWidget {
  const AgeRangeSliders({
    required this.minValue,
    required this.maxValue,
    required this.boundsMin,
    required this.boundsMax,
    required this.onChanged,
    required this.minLabelPrefix,
    required this.maxLabelPrefix,
    required this.labelSuffix,
    super.key,
  })  : assert(boundsMin <= boundsMax),
        assert(minValue >= boundsMin && minValue <= boundsMax),
        assert(maxValue >= boundsMin && maxValue <= boundsMax);

  /// Aktuell gewähltes Mindestalter.
  final int minValue;

  /// Aktuell gewähltes Höchstalter.
  final int maxValue;

  /// Statische untere Grenze (z. B. 16, bei der Dating Hour 18).
  final int boundsMin;

  /// Statische obere Grenze (z. B. 99).
  final int boundsMax;

  /// Wird mit der gekoppelten Auswahl (min, max) aufgerufen.
  final void Function(int min, int max) onChanged;

  final String minLabelPrefix;
  final String maxLabelPrefix;
  final String labelSuffix;

  @override
  Widget build(BuildContext context) {
    final boundsMaxDouble = boundsMax.toDouble();
    final boundsMinDouble = boundsMin.toDouble();
    final divisions = math.max(1, boundsMax - boundsMin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$minLabelPrefix: $minValue $labelSuffix',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: minValue.toDouble(),
          min: boundsMinDouble,
          max: boundsMaxDouble,
          divisions: divisions,
          label: '$minValue',
          onChanged: (v) {
            final newMin = v.round();
            // Mindestalter über das Höchstalter -> Höchstalter schiebt mit.
            onChanged(newMin, math.max(newMin, maxValue));
          },
        ),
        const SizedBox(height: 8),
        Text(
          '$maxLabelPrefix: $maxValue $labelSuffix',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: maxValue.toDouble(),
          min: boundsMinDouble,
          max: boundsMaxDouble,
          divisions: divisions,
          label: '$maxValue',
          onChanged: (v) {
            final newMax = v.round();
            // Höchstalter unter das Mindestalter -> Mindestalter schiebt mit.
            onChanged(math.min(newMax, minValue), newMax);
          },
        ),
      ],
    );
  }
}
