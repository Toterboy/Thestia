import 'dart:io';

/// Der Quelltext einer Datei MIT ihren Teilen (`parts/`).
///
/// DER WEG: Die Bildschirme sind nach Themen aufgeteilt - der Code
/// steht in den Dateien unter `parts/`. Wer den Quelltext liest, muss
/// deshalb alle Teile mitlesen.
String liesQuelltext(String pfad) {
  final puffer = StringBuffer();
  final datei = File(pfad);
  if (datei.existsSync()) {
    puffer.writeln(datei.readAsStringSync());
  }
  final teile = Directory('${datei.parent.path}/parts');
  if (teile.existsSync()) {
    final dateien = teile.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final teil in dateien) {
      puffer.writeln(teil.readAsStringSync());
    }
  }
  return puffer.toString();
}
