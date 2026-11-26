// Der Teil '_PasskeyTile'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

/// "Passkey erstellen"-Kachel mit Doppel-Tap-Schutz: Solange die
/// Registrierung läuft (inkl. 2FA-Step-up), ist die Kachel gesperrt.
/// Zwei parallele Zeremonien brechen sich sonst gegenseitig ab
/// ("Anfrage abgebrochen von Thestia" / "credential verification failed").
class _PasskeyTile extends ConsumerStatefulWidget {
  const _PasskeyTile();

  @override
  ConsumerState<_PasskeyTile> createState() => _PasskeyTileState();
}
