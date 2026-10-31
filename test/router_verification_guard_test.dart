// Regressionstest fuer die Route-Seite der Verifikationssperre
// (v0.10.0, Security-Audit 31.10.2026).
//
// BEFUND: Die Verifikationspflicht fuer Find your Spark, Dating Hour
// und Transit Spark wurde nur im Modus-Auswahlbildschirm geprueft
// (swipe_mode_selection_screen.dart). Die ROUTEN selbst waren frei
// navigierbar: ein Deep-Link, ein gespeicherter Verlauf oder ein
// App-Link kam direkt auf den Bildschirm.
//
// Der Test prueft die Route-Liste, die der Redirect auswertet.
//
// WICHTIG: Der Server bleibt die maechtige Sperre (Migration 161:
// join_dating_hour, match_dating_hour_round, transit_spark_adult).
// Dieser Test sichert die ZUSAETZLICHE clientseitige Pruefung ab -
// damit ein Deep-Link nicht an der UI-Sperre vorbeikommt.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/routing/verification_required_routes.dart';

void main() {
  group('Routen, die ein verifiziertes Profil voraussetzen', () {
    test('Find your Spark, Transit Spark und Dating Hour sind gesperrt', () {
      expect(routeNeedsVerification(AppRoutes.findYourMatch), isTrue,
          reason: 'Find your Spark vermittelt an Fremde - dafuer ist die '
              'Verifikation da.');
      expect(routeNeedsVerification(AppRoutes.transitRadar), isTrue,
          reason: 'Transit Spark erzeugt Begegnungen im oeffentlichen '
              'Raum - dafuer ist die Verifikation da.');
      expect(routeNeedsVerification(AppRoutes.datingHourEvent), isTrue,
          reason: 'Dating Hour vermittelt an Fremde - dafuer ist die '
              'Verifikation da.');
    });

    test('Die Erklaerungsseiten bleiben frei', () {
      // Eine Sperre auf den Erklaerungsseiten wuerde die App
      // unbenutzbar machen, ohne etwas zu schuetzen: sie zeigen
      // Information, keine Begegnung.
      expect(routeNeedsVerification(AppRoutes.datingHourRules), isFalse);
      expect(routeNeedsVerification(AppRoutes.datingHourHowItWorks), isFalse);
      expect(routeNeedsVerification(AppRoutes.datingHourPreferences), isFalse);
      expect(routeNeedsVerification(AppRoutes.settings), isFalse);
    });

    test('Der Chat einer laufenden Dating-Hour-Runde bleibt frei', () {
      // Wer mitten in einer Runde rausfliegt, verliert das Gespraech.
      // Der Zutritt wurde beim Join geprueft - die Runde existiert
      // bereits.
      final chat = AppRoutes.datingHourChatPath('12345678-1234-1234-1234-'
          '123456789abc');
      expect(routeNeedsVerification(chat), isFalse,
          reason: 'Der Chat einer laufenden Runde ist keine neue '
              'Begegnung.');
    });

    test('Allgemeine Seiten sind nicht gesperrt', () {
      for (final route in [
        AppRoutes.home,
        AppRoutes.chatDetail,
        AppRoutes.profile,
        AppRoutes.swipeModeSelection,
        AppRoutes.admin,
      ]) {
        expect(routeNeedsVerification(route), isFalse,
            reason: '$route ist nicht verifikationspflichtig.');
      }
    });
  });
}
