// Der Teil '_BusyIcon'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Reiter ├╝ber einer aufklappbaren Blase.
///
/// Der Reiter bleibt beim ├ûffnen an seinem Platz, der Inhalt w├ñchst
/// darunter nach unten. Deshalb gibt es hier keinen TabController und
/// keine TabBarView - nur einen Zustand.
///
/// FORM (NUTZERWUNSCH 31.10.2026): "die beiden Buttons oben sollen
/// auch unten abgerundet bleiben und nicht unten eckig oben rund
/// sein". Vorher war der Reiter oben eine runde Kapuze und unten fast
/// eckig (Radius 14) - er sollte sich an die Blase anschliessen. Mit
/// der runden Blase darunter sah das aber nach zwei getrennten
/// Teilen aus, und der Reiter wirkte wie eine Haube.
///
/// Jetzt ist der Reiter eine Pille: oben UND unten gleich gerundet.
/// Die Blase darunter ist ebenfalls oben gerundet - die beiden Teile
/// lesen sich als ein Paar, nicht als Kappe plus Kasten.
/// Symbol, das bei einem laufenden Vorgang leise atmet.
///
/// Kein Ladekreis im Knopf (NUTZERWUNSCH 31.10.2026): der Ring war
/// 16 px breit statt 24 px - die Breite des Knopfes sprang damit
/// hin und her, und bei einem kurzen Vorgang (das Antworten auf einen
/// Like ist genau das) war der Ring nur ein Blitzer.
///
/// Das Symbol bleibt an seiner Stelle und wird nur etwas leiser. Die
/// Knopfbreite bleibt dadurch stabil, und die Bewegung ist ruhig.
class _BusyIcon extends StatefulWidget {
  const _BusyIcon({required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  State<_BusyIcon> createState() => _BusyIconState();
}
