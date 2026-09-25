import 'package:flutter/material.dart';

import 'package:thestia/models/habitude_level.dart';

/// Drei-Button-Auswahl (Täglich / Gelegentlich / Nie) für eine
/// Konsum-Präferenz (Rauchen, Alkohol, andere Drogen).
///
/// Die Reihenfolge der Buttons ist aufsteigend (Nie → Täglich), damit die
/// visuelle Hierarchie der Rangfolge entspricht.
class HabitudeSelector extends StatelessWidget {
  const HabitudeSelector({
    super.key,
    required this.topic,
    required this.value,
    required this.onChanged,
  });

  /// Thema der Auswahl (bestimmt die Überschrift).
  final HabitudeTopic topic;

  /// Aktuell gewählte Stufe (oder null = keine Angabe).
  final HabitudeLevel? value;

  /// Wird aufgerufen, wenn der Nutzer eine Stufe wählt bzw. die Auswahl
  /// aufhebt (bei erneutem Tippen auf die aktive Stufe).
  final ValueChanged<HabitudeLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Aufsteigende Reihenfolge: Nie, Gelegentlich, Täglich.
    final levels = HabitudeLevel.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topic.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: levels.map((level) {
            final selected = value == level;
            return ChoiceChip(
              label: Text(level.label),
              selected: selected,
              onSelected: (_) => onChanged(selected ? null : level),
            );
          }).toList(),
        ),
      ],
    );
  }
}
