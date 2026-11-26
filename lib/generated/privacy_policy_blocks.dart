// GENERIERTE DATEI - NICHT VON HAND ÄNDERN.
// Neu erzeugen mit: python tool/web/make_privacy_policy.py

/// Ein Abschnitt der Datenschutzerklärung für die Anzeige in der
/// App.
///
/// Google Play verlangt die Erklärung nicht nur als Link im Store,
/// sondern ausdrücklich auch als Text innerhalb der App selbst.
/// Deshalb steht sie hier und wird im Privacy-Screen gelesen, statt
/// nur verlinkt zu werden - eine URL kann falsch oder nicht erreichbar
/// sein, dieser Text nicht.
class PrivacyBlock {
  const PrivacyBlock(this.kind, this.text, {this.cells});

  /// h1, h2, h3, p, li oder table.
  final String kind;

  /// Fliesstext bzw. Überschrift. Für [kind] == 'table' leer.
  final String text;

  /// Zellen einer Tabellenzeile. Nur bei [kind] == 'table' gesetzt.
  final List<String>? cells;
}
