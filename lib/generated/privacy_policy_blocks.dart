// GENERIERTE DATEI - NICHT VON HAND AENDERN.
// Neu erzeugen mit: python tool/make_privacy_policy.py

/// Ein Abschnitt der Datenschutzerklaerung fuer die Anzeige in der
/// App.
///
/// Google Play verlangt die Erklaerung nicht nur als Link im Store,
/// sondern ausdruecklich auch als Text innerhalb der App selbst.
/// Deshalb steht sie hier und wird im Privacy-Screen gelesen, statt
/// nur verlinkt zu werden - eine URL kann falsch oder nicht erreichbar
/// sein, dieser Text nicht.
class PrivacyBlock {
  const PrivacyBlock(this.kind, this.text, {this.cells});

  /// h1, h2, h3, p, li oder table.
  final String kind;

  /// Fliesstext bzw. Ueberschrift. Fuer [kind] == 'table' leer.
  final String text;

  /// Zellen einer Tabellenzeile. Nur bei [kind] == 'table' gesetzt.
  final List<String>? cells;
}
