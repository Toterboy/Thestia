// Das Sync-Date im Chat (Plan 0.11.0, "Begegnung statt Bildschirm").
//
// DER WEG: Zwei Menschen, die weit auseinander wohnen, treffen sich zur
// selben Zeit an verschiedenen Orten. Der Termin steht serverseitig,
// damit beide Seiten denselben Zeitpunkt sehen.
//
// Die Datei ist ein eigener Teil, weil der Aufbau des Chat-Screens
// sonst über die 1000-Zeilen-Grenze käme (der Test
// code_datei_groessen_test.dart).

part of '../chat_detail_screen.dart';

extension _ChatDetailSyncDate on _ChatDetailScreenState {
  /// Das Sync-Date des Chats (null, wenn es keines gibt).
  ///
  /// DER SERVER: Ohne initialisierten Supabase (im Test, im Demo-Modus)
  /// gibt es keinen Client - und ohne Client kein Sync-Date. Ohne diese
  /// Abfrage würde der ganze Bildschirm beim Aufbau scheitern.
  SyncDate? get termin {
    if (!SupabaseService.isInitialized) return null;
    return ref.watch(syncDateProvider(widget.matchId));
  }

  /// Die Karte des Sync-Dates (steht im Chat, wenn es eins gibt).
  ///
  /// Sie bringt den gemeinsamen Countdown und den Anruf-Knopf mit - das
  /// Date endet mit dem Anruf.
  Widget get syncDateKarte => SyncDateCard(
    matchId: widget.matchId,
    partnerName: _match?.partner.name ?? '',
    onCall: _call,
  );
}
