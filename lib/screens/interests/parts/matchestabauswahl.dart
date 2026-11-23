// Der Teil '_FunkenAuswahlLeiste'.
//
// DER WEG (23.11.2026): Die Datei 'matchestabstate.dart' war durch die
// Auswahl-Leiste ueber die 1000-Zeilen-Grenze gekommen. Die Leiste ist
// ein eigenes Widget - sie gehoert in eine eigene Datei.

part of '../interessen_screen.dart';

/// Die Knopf-Leiste des Auswahl-Modus ("Verwalten") in der Funken-Liste.
///
/// Zwei Knöpfe: "Abbrechen" und "Ausblenden (N)".
///
/// BEFUND (23.11.2026, gefunden von einem Test): Die beiden Knöpfe
/// passten nebeneinander nicht in einen 390-px-Bildschirm - der
/// "Ausblenden"-Knopf wurde um 118 Pixel abgeschnitten (mit gelb-schwarzen
/// Streifen). Grund: Die Knöpfe sind breit (Schriftgroesse + Rand +
/// Symbol), und bei grosser Systemschrift passt gar nichts mehr.
///
/// DER WEG: Ein Wrap statt einer Zeile. Passen beide Knöpfe nebeneinander,
/// stehen sie wie vorher (Abbrechen links, Ausblenden rechts). Passen sie
/// nicht, rueckt der zweite Knopf eine Zeile tiefer - abgeschnitten wird
/// nichts.
class _FunkenAuswahlLeiste extends StatelessWidget {
  const _FunkenAuswahlLeiste({
    required this.anzahl,
    required this.onAbbrechen,
    required this.onAusblenden,
  });

  /// Wie viele Funke sind ausgewaehlt?
  final int anzahl;

  /// Der Auswahl-Modus wird beendet (die Auswahl geht verloren).
  final VoidCallback onAbbrechen;

  /// Die ausgewaehlten Funke werden ausgeblendet.
  final VoidCallback onAusblenden;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: onAbbrechen,
            icon: const Icon(Icons.close, size: 18),
            label: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton.icon(
            onPressed: anzahl == 0 ? null : onAusblenden,
            icon: const Icon(Icons.visibility_off, size: 18),
            label: Text(
              L10n.tf(context, 'interests.hideSelected', {'n': '$anzahl'}),
            ),
          ),
        ],
      ),
    );
  }
}
