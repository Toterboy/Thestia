// Der Teil '_SoftPingInbox'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Soft-Ping-Eingang (Empfänger-Sicht, v0.9.1): Offene Grüße mit
/// Annehmen (-> Funke) oder Ausblenden (still, Absender sieht nichts).
class _SoftPingInbox extends ConsumerStatefulWidget {
  const _SoftPingInbox();

  @override
  ConsumerState<_SoftPingInbox> createState() => _SoftPingInboxState();
}
