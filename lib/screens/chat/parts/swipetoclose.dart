// Der Teil '_SwipeToClose'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Platzhalter-Box einer Bild-Bubble (wird erst durch das echte Bild
/// ersetzt). Eigene Klasse, damit der Unschärf-Filter nur im verpixelten
/// Zustand um das Bild gelegt wird und nicht um die Deko-Box.
/// Fängt eine waagerechte Wischgeste ab und schließt das Fenster.
///
/// BEFUND (09.11.2026, Betreiber): "Wenn Bild geöffnet und zurück
/// swipe, dann im Hintergrund zurück, aber Bild noch offen (Swipe soll
/// Bild schließen und nicht im Hintergrund weiter machen)."
///
/// DER GRUND: Der Bild-Dialog liegt auf dem Navigator der Shell - und
/// der Reiter-Wechsel sitzt DARÜBER (`HitTestBehavior.translucent`).
/// Die Sperrfläche eines Dialogs schluckt Tipps, aber KEINE
/// waagerechte Wischgeste: die landete im Reiter-Wechsel. Das Bild blieb
/// offen, der Hintergrund wechselte - genau umgekehrt zu gewünscht.
///
/// Deshalb fängt das Bild die Geste selbst ab. Weil der INNERSTE
/// Gesture-Recognizer den Wettbewarf gewinnt, wird der Reiter-Wechsel
/// dabei nicht ausgelöst: die Wischgeste schließt das Bild und sonst
/// nichts.
class _SwipeToClose extends StatefulWidget {
  const _SwipeToClose({required this.child});

  final Widget child;

  @override
  State<_SwipeToClose> createState() => _SwipeToCloseState();
}
