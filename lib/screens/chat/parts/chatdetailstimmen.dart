// Der Nudge Richtung Anruf (Plan 0.11.0, "Begegnung statt Bildschirm").
//
// DER WEG: "Bei Distanz-Funken den Chat sanft Richtung Anruf/
// Sprachnachricht nudge ('Stimmen verbinden mehr als Texte')." Wer weit
// weg wohnt, schreibt sich Text - dabei verbunden man sich viel besser.
//
// Die Datei ist ein eigener Teil, weil der Aufbau des Chat-Screens
// sonst über die 1000-Zeilen-Grenze käme (der Test
// code_datei_groessen_test.dart).

part of '../chat_detail_screen.dart';

extension _ChatDetailStimmen on _ChatDetailScreenState {
  /// Der Nudge (einmal je Chat, sanft).
  Widget get stimmenNudge => StimmenNudge(
    matchId: widget.matchId,
    entfernungKm: _match?.partner.distanceKm ?? 0,
    onCall: _call,
  );
}
