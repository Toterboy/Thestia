// Der Teil '_PasskeyManagerCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

/// "Passkeys verwalten": Listet alle am Konto registrierten Passkeys
/// (WebAuthn-Credentials) und erlaubt Umbenennen/Löschen. Wichtig für
/// die Fehlersuche, wenn der Server eine NEUE Registrierung nicht
/// bestätigt: Ein alter/defekter Eintrag kann blockieren - löschen und
/// neu anlegen behebt das.
class _PasskeyManagerCard extends ConsumerStatefulWidget {
  const _PasskeyManagerCard();

  @override
  ConsumerState<_PasskeyManagerCard> createState() =>
      _PasskeyManagerCardState();
}
