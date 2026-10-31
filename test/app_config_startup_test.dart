// Regressionstest fuer den Start ohne Netz-Wartezeit
// (31.10.2026).
//
// BEFUND: Das Mindest-Build-Gate (app_config.min_app_version_build)
// stand auf dem kritischen Pfad des Starts. Der erste Frame der App
// wartete auf einen Server-Roundtrip (bis zu 6 s Timeout) - und die
// App war damit langsamer, obwohl der Wert in den allermeisten
// Faellen schon bekannt war.
//
// Jetzt:
//   * der Wert wird lokal gecacht (SharedPreferences),
//   * der Cache wird beim Start sofort ausgewertet (lokaler Zugriff),
//   * nur ohne Cache wird der Server mit kurzem Timeout gefragt,
//   * der frische Serverwert laeuft im Hintergrund nach.
//
// Der Cache darf aber nicht zum Umgehen des Gates werden: ein
// gecachter Wert, der den installierten Build sperrt, sperrt auch -
// und ein neuer, strengerer Serverwert wird im Hintergrund erkannt.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/app_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mindest-Build-Vergleich', () {
    test('ein Build unter dem Mindest-Build ist gesperrt', () {
      expect(AppConfigService.isBuildBelowMinBuild(30, 31), isTrue);
    });

    test('der Mindest-Build selbst ist nicht gesperrt', () {
      expect(AppConfigService.isBuildBelowMinBuild(31, 31), isFalse);
    });

    test('ein neuerer Build ist nicht gesperrt', () {
      expect(AppConfigService.isBuildBelowMinBuild(32, 31), isFalse);
    });

    test('unbekannte Werte sperren niemanden (fail-open)', () {
      // Build 0 = die Build-Nummer konnte nicht gelesen werden.
      expect(AppConfigService.isBuildBelowMinBuild(0, 31), isFalse);
      // Mindest-Build 0 = der Server hat keinen gesetzt.
      expect(AppConfigService.isBuildBelowMinBuild(30, 0), isFalse);
    });
  });

  group('Cache des Mindest-Builds', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SharedPreferences.getInstance();
    });

    test('ist am Anfang leer', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(AppConfigService.cachedMinAppVersionBuild(prefs), isNull);
    });

    test('ueberlebt das Schreiben und Lesen', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppConfigService.cacheMinAppVersionBuild(prefs, 31);
      expect(AppConfigService.cachedMinAppVersionBuild(prefs), 31);
    });

    test('ein strengerer Wert ersetzt den alten', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppConfigService.cacheMinAppVersionBuild(prefs, 30);
      await AppConfigService.cacheMinAppVersionBuild(prefs, 31);
      expect(AppConfigService.cachedMinAppVersionBuild(prefs), 31);
    });

    test('der Cache wird in einer neuen Instanz wieder gefunden', () async {
      // Das ist der Punkt des Caches: der Wert muss den Prozess
      // ueberleben - sonst waere der Startpfad wieder ein Netzruf.
      final prefs = await SharedPreferences.getInstance();
      await AppConfigService.cacheMinAppVersionBuild(prefs, 31);

      final neu = await SharedPreferences.getInstance();
      expect(AppConfigService.cachedMinAppVersionBuild(neu), 31);
    });
  });
}
