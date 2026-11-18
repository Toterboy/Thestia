// Der Teil '_PrimaryActionButton'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Primärer Aktions-Button.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aktiv = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          // BEFUND (07.11.2026, Betreiber): "Dating-Hour-Wartebereich
          // mit Theme-Farbe." Der Wartezustand war fest grau - in einem
          // App-Bild, in dem die Farbe das Thema traegt, sah das
          // abgeschnitten aus. Jetzt kommt die Wartefarbe aus dem
          // Theme (primaryContainer), der Text aus dem Theme
          // (onPrimaryContainer) - und die Farbe folgt dem gewaehlten
          // Theme mit.
          backgroundColor: aktiv ? color : scheme.primaryContainer,
          foregroundColor: aktiv
              ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                    ? Colors.white
                    : scheme.onSurface)
              : scheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
