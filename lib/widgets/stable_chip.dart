import 'package:flutter/material.dart';

/// Ein auswählbarer Chip, dessen Größe sich beim Auswählen **nicht**
/// ändert.
///
/// BEFUND (13.11.2026, Betreiber): "Wenn man Buttons auswählt, z. B. in
/// den Profileinstellungen, sollen sie sich nicht in die nächste Zeile
/// durch auswählen verschieben."
///
/// DIE URSACHE: Material blendet im ausgewählten Zustand ein Häkchen
/// ein. Das Chip wird dadurch breiter, der `Wrap` (die Reihen der
/// Chips) packt neu - und das gerade geklickte Chip springt in die
/// nächste Zeile. Das fühlt sich an wie ein Fehlklick: der Nutzer
/// tippt, und der Knopf wandert weg.
///
/// DIE LÖSUNG: Das Häkchen wird nicht eingeblendet. Die Auswahl bleibt
/// sichtbar - Material 3 füllt das gewählte Chip in der Akzentfarbe
/// (bei den "mag ich nicht"-Chips in der Fehlerfarbe) - und die
/// Größe bleibt, was sie war.
///
/// Der Chip ist bewusst kein Drop-in für `FilterChip`: es gibt nur die
/// beiden Varianten, die die App braucht (Mehrfach- und Einfachauswahl).
class StableChip extends StatelessWidget {
  const StableChip.filter({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.selectedColor,
    this.checkmarkColor,
    super.key,
  }) : _einfach = false;

  const StableChip.choice({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.selectedColor,
    this.checkmarkColor,
    super.key,
  }) : _einfach = true;

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool _einfach;

  @override
  Widget build(BuildContext context) {
    if (_einfach) {
      return ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        // Ohne Häkchen bleibt die Breite gleich - der Wrap springt nicht.
        showCheckmark: false,
        selectedColor: selectedColor,
        checkmarkColor: checkmarkColor,
      );
    }
    return FilterChip(
      label: label,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: selectedColor,
      checkmarkColor: checkmarkColor,
    );
  }
}
