// Der Teil '_AutoMatchBadge'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Dezentes Kennzeichen fuer einen automatisch entstandenen Funke
/// (Migration 177).
///
/// Der Funke kam nach 10 Minuten Dating Hour zustande, nicht durch ein
/// beidseitiges "Ja". Das Sternchen macht das kenntlich - der Tooltip
/// sagt, was es ist.
class _AutoMatchBadge extends StatelessWidget {
  const _AutoMatchBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: L10n.t(context, 'dh.autoMatch.badge'),
      child: Icon(
        Icons.auto_awesome,
        size: 16,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
      ),
    );
  }
}
