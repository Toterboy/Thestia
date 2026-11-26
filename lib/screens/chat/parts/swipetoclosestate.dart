// Der Teil '_SwipeToCloseState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _SwipeToCloseState extends State<_SwipeToClose> {
  /// Der zurückgelegte Weg (negativ = nach links).
  double _weg = 0.0;

  /// Wie weit gewischt werden muss, damit das Fenster schließt.
  static const double _schwelle = 70;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        _weg += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        final weg = _weg;
        _weg = 0;
        if (weg.abs() < _schwelle) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      },
      child: widget.child,
    );
  }
}
