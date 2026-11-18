// Der Teil '_SwipeToClose'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Platzhalter-Box einer Bild-Bubble (wird erst durch das echte Bild
/// ersetzt). Eigene Klasse, damit der Unschärf-Filter nur im verpixelten
/// Zustand um das Bild gelegt wird und nicht um die Deko-Box.
/// Faengt eine waagerechte Wischgeste ab und schliesst das Fenster.
///
/// BEFUND (09.11.2026, Betreiber): "Wenn Bild geoeffnet und zurueck
/// swipe, dann im Hintergrund zurueck, aber Bild noch offen (Swipe soll
/// Bild schliessen und nicht im Hintergrund weiter machen)."
///
/// DER GRUND: Der Bild-Dialog liegt auf dem Navigator der Shell - und
/// der Reiter-Wechsel sitzt DARUEBER (`HitTestBehavior.translucent`).
/// Die Sperrflaeche eines Dialogs schluckt Tipps, aber KEINE
/// waagerechte Wischgeste: die landete im Reiter-Wechsel. Das Bild blieb
/// offen, der Hintergrund wechselte - genau umgekehrt zu gewuenscht.
///
/// Deshalb faengt das Bild die Geste selbst ab. Weil der INNERSTE
/// Gesture-Recognizer den Wettbewarf gewinnt, wird der Reiter-Wechsel
/// dabei nicht ausgeloest: die Wischgeste schliesst das Bild und sonst
/// nichts.
class _SwipeToClose extends StatefulWidget {
  const _SwipeToClose({required this.child});

  final Widget child;

  @override
  State<_SwipeToClose> createState() => _SwipeToCloseState();
}
