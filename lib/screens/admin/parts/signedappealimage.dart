// Der Teil '_SignedAppealImage'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

/// Bild einer Appeal-Zeile.
///
/// Eigenes StatefulWidget, weil das Signed-URL-Future GECACHT werden muss:
/// Stand es in `build`, feuerte jeder Rebuild (Liste, Pull-to-refresh,
/// _load()) für jede sichtbare Zeile einen neuen Signed-URL-Request ab.
/// Zusätzlich begrenzt `cacheWidth` die Dekodierung auf die 96-px-Kachel.
class _SignedAppealImage extends ConsumerStatefulWidget {
  const _SignedAppealImage({required this.path});

  final String path;

  @override
  ConsumerState<_SignedAppealImage> createState() => _SignedAppealImageState();
}
