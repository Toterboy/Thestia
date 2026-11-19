import 'package:flutter/material.dart';

/// Auswahlfeld (Radio) mit klarer visueller Hervorhebung der gewählten
/// Option.
///
/// Es wird bewusst NUR EIN Indikator verwendet: der gefüllte Radio-Kreis.
/// Zusätzlich wird das gesamte Feld bei Auswahl dezent hinterlegt, wobei
/// der Rahmen exakt dieselbe Rundung wie die übrigen Kartenfelder der App
/// (BorderRadius 24) erhält - kein eckiger Kasten.
///
/// Implementierung: bewusst KEIN ListTile (dessen tileColor/Shape-Decoration
/// konnte die Hervorhebung über die Zeilen-Bounds hinaus malen und ließ
/// Icon/Text oben anschnippen). Stattdessen eine explizite Material/Row:
/// Der Hervorhebungs-Container ist exakt an die Zeile gebunden, Icon und
/// Text sind per Row-CrossAxisAlignment vertikal zentriert.
///
/// Verwendet die native [RadioGroup] (Material) mit groupValue/onChanged
/// und die [Radio]-Kinder ohne eigene groupValue/onChanged (deprecated).
class SelectableTile<T> extends StatelessWidget {
  const SelectableTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final T value;
  final T? groupValue;
  final String title;
  final ValueChanged<T?> onChanged;

  /// Optionale Erklaerung unter dem Titel.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: (v) => onChanged(v),
      child: Padding(
        // Kleiner Abstand zwischen den Zeilen, damit die Hervorhebung
        // benachbarte Elemente nie berührt/überdeckt.
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha((255 * 0.5).round())
              : Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Radio<T>(
                    value: value,
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: subtitle == null
                        ? Text(
                            title,
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
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
