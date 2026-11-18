// Der Teil '_SoftPingInbox'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Soft-Ping-Eingang (Empfaenger-Sicht, v0.9.1): Offene Gruesse mit
/// Annehmen (-> Funke) oder Ausblenden (still, Absender sieht nichts).
class _SoftPingInbox extends ConsumerStatefulWidget {
  const _SoftPingInbox();

  @override
  ConsumerState<_SoftPingInbox> createState() => _SoftPingInboxState();
}
