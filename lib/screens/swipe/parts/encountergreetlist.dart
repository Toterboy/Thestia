// Der Teil '_EncounterGreetList'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Gruessen-Sektion (v0.9.1): Frische Encounters als anonyme Eintraege
/// ("vor 2 Minuten") - jeder EINMAL per Soft-Ping ansprechbar. Kein
/// Name, kein Foto: Die Person bleibt anonym, bis sie den Gruß annimmt.
class _EncounterGreetList extends ConsumerStatefulWidget {
  const _EncounterGreetList();

  @override
  ConsumerState<_EncounterGreetList> createState() =>
      _EncounterGreetListState();
}
