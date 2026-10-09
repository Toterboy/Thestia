import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Auswahl für den Erscheinungsmodus (Hell / System / Dunkel).
///
/// Drei kurze, gegenseitig ausschliessende Optionen sind der
/// Segmentfall, kein Kartenfall. Die vorherige Fassung stapelte drei
/// grosse Karten mit Icon, Titel und zwei Zeilen Erklaerung; das
/// drueckte in den Einstellungen Farbschema und Chat-Hintergrund weit
/// unter den Bildschirmrand - der Nutzer musste scrollen, um zu sehen,
/// dass es sie ueberhaupt gibt.
///
/// Jetzt: eine Zeile mit drei Segmenten. Jedes traegt sein Symbol
/// (Sonne / automatisch / Mond), damit die Wahl auch ohne Text
/// erkennbar ist. Darunter steht EINE Zeile, die die aktive Option
/// erklaert - die Erklaerungen der beiden anderen stehen im
/// Semantics-Label ihres Segments, damit Screenreader sie genauso
/// vorlesen.
///
/// `Wrap` statt `Row` mit `Expanded`: bei 3,2-facher Schriftgroesse
/// (Barrierefreiheitstest) waere jede feste Segmentbreite ein
/// RenderFlex-Overflow. `Wrap` laesst die Segmente untereinander
/// wandern, statt sie zu beschneiden.
class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Aktiver Modus: 'light' | 'system' | 'dark'.
  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _order = ['light', 'system', 'dark'];

  static const Map<String, IconData> _icons = {
    'light': Icons.light_mode_outlined,
    'system': Icons.brightness_auto_outlined,
    'dark': Icons.dark_mode_outlined,
  };

  /// 24 ist der Radius, den die App an Karten, `SelectableTile` und
  /// Eintragszeilen benutzt.
  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Erklaerung zu einem Modus. Steht als eigene Funktion, damit genau
    // EINE Key-Vorlage ('appearanceDesc.$mode') im Widget vorkommt -
    // der L10n-Test erlaubt benannte dynamische Familien, und eine
    // zweite Vorlage mit anderem Variablennamen waere ein unzulaessiger
    // Key-Familien-Mix.
    String describe(String mode) =>
        L10n.t(context, 'appearanceDesc.$mode');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in _order)
              _Segment(
                mode: mode,
                selected: mode == value,
                radius: _radius,
                icon: _icons[mode] ?? Icons.brightness_auto_outlined,
                title: L10n.t(context, 'appearance.$mode'),
                description: describe(mode),
                onTap: () => onChanged(mode),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Erklaerung der AKTIVEN Option. Nur eine sichtbare Zeile, sonst
        // waere die Auswahl wieder drei Karten hoch.
        Text(
          describe(value),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.mode,
    required this.selected,
    required this.radius,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final double radius;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final borderColor =
        selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6);
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : scheme.surface;
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      selected: selected,
      button: true,
      // Die Erklaerung gehoert hierher: sie ist im sichtbaren Layout nur
      // fuer die aktive Option vorhanden, der Screenreader soll sie aber
      // fuer alle drei vorlesen.
      label: '$title. $description',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: selected ? 1 : 0.75,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: borderColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  // Gleiches Optionstipp bleibt ohne Haptik, wie beim
                  // TransitModeSelector.
                  if (!selected) HapticFeedback.selectionClick();
                  onTap();
                },
                borderRadius: BorderRadius.circular(radius),
                child: ConstrainedBox(
                  // Mindestbreite, damit die drei Segmente bei normaler
                  // Schrift eine Zeile ergeben. Kein Maximum: bei grosser
                  // Schrift darf ein Segment breiter werden.
                  constraints: const BoxConstraints(minWidth: 92),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    // Der Haken liegt als OVERLAY in der oberen rechten
                    // Ecke, nicht als Platzhalter neben dem Text.
                    //
                    // Vorher stand dort in ALLEN Segmenten ein
                    // SizedBox(width: 16), damit die Zeile beim Wechsel
                    // nicht springt. Der Preis war ein um 6 px
                    // nach links verschobener Text: bei "Hell" faellt das
                    // nicht auf, weil der Haken den Platz fuellt, bei
                    // "System" und "Dunkel" stand er schief. Genau das
                    // war die Rueckmeldung.
                    //
                    // Als Overlay costet der Haken keinen Platz, der
                    // Text ist mittig - und die Segmentbreite haengt
                    // nur noch vom Text ab, nicht mehr davon, ob gerade
                    // etwas gewaehlt ist. Das Springen ist damit
                    // ebenfalls weg, und zwar ohne den Trick.
                    child: Stack(
                      // v0.9.2: `alignment: Alignment.center`.
                      //
                      // Ein Stack richtet sein nicht positioniertes Kind
                      // standardmaessig oben links aus. Die Column hier
                      // ist schmal (bei "Hell" rund 40 px), waehrend der
                      // Kasten durch die Mindestbreite von 92 px breiter
                      // ist. Der Inhalt stand deshalb in jedem kurzen
                      // Segment links - Symbol UND Text. Bei "Dunkel"
                      // fiel es kaum auf, weil der Text fast die
                      // Mindestbreite fuellt.
                      //
                      // Der Haken ist Positioned und damit von diesem
                      // Alignment nicht betroffen; er sitzt weiterhin in
                      // der oberen rechten Ecke.
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 22, color: fg),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color:
                                    selected ? scheme.onSurface : fg,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        // Kein Haken: die Auswahl traegt die Kachel
                        // selbst (gefuelltes Icon-Feld, Titelfarbe,
                        // Hintergrund). Ein zusaetzliches Symbol war ein
                        // drittes Signal fuer dieselbe Aussage.
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
