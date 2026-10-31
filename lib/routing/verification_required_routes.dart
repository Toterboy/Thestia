/// Welche Routen setzen ein **verifiziertes Profil** voraus?
///
/// v0.10.0, Security-Audit 31.10.2026: Defense in Depth.
///
/// Die Verifikationspflicht fuer Find your Spark, Dating Hour und Transit
/// Spark wird im Modus-Auswahlbildschirm geprueft
/// (`swipe_mode_selection_screen.dart`). Das ist eine UI-Sperre - die
/// Routen selbst waren frei navigierbar: ein Deep-Link, ein
/// gespeicherter Verlauf oder ein App-Link kam direkt auf den
/// Bildschirm.
///
/// Diese Liste ist die Route-Seite derselben Sperre. Sie ist bewusst
/// KEIN Ersatz fuer den Server: Migration 161 erzwingt die Sperre
/// serverseitig (`join_dating_hour`, `match_dating_hour_round`,
/// `transit_spark_adult`). Ein gepatchter Client kommt an der
/// Servergrenze nicht vorbei - der Router hier faengt nur den Rest
/// ab.
///
/// Bewusst NICHT gesperrt:
///
///   * die Erklaerungsseiten (Dating-Hour-Regeln, "so funktioniert
///     es", Einstellungen) - sie sind Information, keine Begegnung.
///     Eine Sperre dort wuerde die App unbenutzbar machen, ohne
///     etwas zu schuetzen.
///   * der Chat einer laufenden Dating-Hour-Runde
///     (`/dating-hour/chat/:sessionId`) - die Runde existiert bereits,
///     der Zutritt wurde beim Join geprueft. Wer mitten in einer
///     Runde rausfliegt, verliert das Gespraech.
///   * die Quiz-Auswertung einer laufenden Runde - gleicher Grund.
library;

import 'package:thestia/routing/app_router.dart';

/// Braucht diese Route ein verifiziertes Profil?
///
/// Siehe die Library-Dokumentation fuer die Begruendung.
bool routeNeedsVerification(String route) {
  // Find your Spark
  if (route == AppRoutes.findYourMatch) return true;
  // Transit Spark (Radar)
  if (route == AppRoutes.transitRadar) return true;
  // Dating Hour: die Veranstaltung selbst, vor dem Beitritt. Die
  // Erklaerungsseiten bleiben frei.
  if (route == AppRoutes.datingHourEvent) return true;
  return false;
}
