// Der Teil '_UnifiedPushTile'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

/// Schalter fuer Google-freien Push via UnifiedPush (F-Droid-Variante).
///
/// Benoetigt eine Distributor-App (z. B. ntfy). Der Endpunkt wird
/// serverseitig im Profil gespeichert; eingehende Pushes zeigt der
/// [UnifiedPushService] lokal an.
class _UnifiedPushTile extends ConsumerStatefulWidget {
  const _UnifiedPushTile();

  @override
  ConsumerState<_UnifiedPushTile> createState() => _UnifiedPushTileState();
}
