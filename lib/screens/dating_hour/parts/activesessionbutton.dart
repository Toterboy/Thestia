// Der Teil '_ActiveSessionButton'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Button, der die aktive Session des Users während eines Events anzeigt.
class _ActiveSessionButton extends ConsumerStatefulWidget {
  const _ActiveSessionButton({required this.eventId});
  final String eventId;

  @override
  ConsumerState<_ActiveSessionButton> createState() =>
      _ActiveSessionButtonState();
}
