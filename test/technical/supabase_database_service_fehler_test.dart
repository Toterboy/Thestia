// Die Datenbank-Wege: die Fehlerfälle und die Rückwärts-Ketten.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/services/server/supabase_database_service.dart 62 offene Zeilen.
// Das sind fast alles die WEGE, die nur im Fehlerfall laufen: der
// Server, der eine Spalte noch nicht kennt, und der Server, der gar
// nicht antwortet.
//
// DER WEG: Der Ersatz-Server (test/support/fake_supabase_server.dart)
// kann die ersten Anfragen scheitern lassen (fehlerBeiDenErstenN) -
// so stellt der Test einen Server dar, der eine Spalte noch nicht
// kennt.
//
// WAS HIER GEPRÜFT WIRD:
//   * das eigene Profil kommt auch ohne die Foto-Spalte,
//   * die Schalter und die Präferenzen kommen auch ohne die neuen
//     Spalten (sonst verliert der Nutzer seinen ganzen Stand),
//   * ein Server, der gar nicht antwortet, wird gemeldet (nicht
//     verschwiegen),
//   * der Einspruch-Status und das Quittieren verschlucken den Fehler
//     (der Nutzer darf nicht an einer Meldung hängenbleiben),
//   * der Transit Spark sagt, wenn der Server zu alt ist.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/server/supabase_database_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server.
  late FakeSupabaseServer server;

  /// Der Dienst.
  late SupabaseDatabaseService db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    db = SupabaseDatabaseService(supabase.Supabase.instance.client);
  });

  setUp(() {
    server.zeilen.clear();
    server.rpcAufrufe.clear();
    server.schreibvorgaenge.clear();
    server.pfade.clear();
    server.fehlerAntworten.clear();
    server.rpcFehler.clear();
    server.antwortetMitFehler = false;
    server.fehlerBeiDenErstenN = 0;
    // Das eigene Profil (der Server liefert es bei jeder Profil-Abfrage).
    server.zeilen['profiles'] = <String, dynamic>{
      'user_id': 'ich',
      'name': 'Lena',
      'bio': 'Liest gern',
      'gender': 'female',
      'gender_preferences': <String>['female'],
      'birth_date': '1995-06-01',
      'interests': <String>['wandern'],
      'photos': <String>[],
      'personality_type': 'enthusiast',
      'max_distance_km': 50,
      'age_range_min': 20,
      'age_range_max': 40,
      'smoking': 'never',
      'alcohol': 'sometimes',
      'drugs': 'never',
      'is_verified': true,
      'is_location_suspicious': false,
      'state': 'Berlin',
      'country': 'Deutschland',
      'show_distance': true,
      'notifications_enabled': true,
      'notify_matches': true,
      'notify_likes': true,
      'notify_messages': true,
      'notify_dating_hour': true,
      'distance_filter_mode': 'km',
      'theme_name': 'classic',
    };
  });

  group('Das eigene Profil', () {
    test('kommt auch ohne die Foto-Spalte', () async {
      // DER SERVER: Die erste Abfrage (mit der Foto-Spalte) kippt - der
      // Server ist noch nicht auf dem Stand der Migration.
      server.fehlerBeiDenErstenN = 1;

      final profil = await db.fetchOwnProfile();

      expect(profil, isNotNull, reason: 'Das Profil muss trotzdem kommen.');
      expect(profil!.name, 'Lena');
      expect(
        server.pfade.where((p) => p.contains('profiles')).length,
        2,
        reason: 'Es muss ein zweiter Versuch mit weniger Spalten geben.',
      );
    });

    test('ohne den Server wird es gemeldet', () async {
      // DER SERVER: Er antwortet gar nicht.
      server.antwortetMitFehler = true;

      await expectLater(
        db.fetchOwnProfile(),
        throwsA(anything),
        reason:
            'Der Nutzer muss erfahren, dass sein Profil nicht geladen werden '
            'konnte - sonst glaubt er, die App haette sein Profil '
            'vergessen.',
      );
    });
  });

  group('Die Schalter und die Praeferenzen', () {
    test('die Schalter kommen auch ohne die neuen Spalten', () async {
      server.fehlerBeiDenErstenN = 1;

      final schalter = await db.fetchOwnSwitches();

      expect(schalter, isNotNull, reason: 'Die Schalter muessen kommen.');
      expect(schalter!['show_distance'], isTrue);
    });

    test('die Praeferenzen kommen auch ohne die neuen Spalten', () async {
      server.fehlerBeiDenErstenN = 1;

      final prefs = await db.fetchOwnPreferences();

      expect(prefs, isNotNull, reason: 'Die Praeferenzen muessen kommen.');
      expect(prefs!['max_distance_km'], 50);
    });
  });

  group('Der Einspruch zum Profilbild', () {
    test('der Status ist null, wenn der Server scheitert', () async {
      server.rpcFehler.add('get_my_photo_appeal');

      final appeal = await db.getMyPhotoAppeal();

      expect(
        appeal,
        isNull,
        reason:
            'Es gibt keinen Status - aber der Nutzer haengt auch nicht an '
            'einem Fehlerfenster.',
      );
    });

    test('das Quittieren verschluckt den Fehler', () async {
      server.rpcFehler.add('acknowledge_photo_appeal');

      await db.acknowledgePhotoAppeal('appeal-1');

      expect(
        server.rpcAufrufe.map((a) => a['funktion']),
        contains('acknowledge_photo_appeal'),
        reason: 'Der Aufruf muss den Server erreicht haben.',
      );
    });
  });

  group('Der Transit Spark', () {
    test('der Server meldet, dass er zu alt ist', () async {
      // DER SERVER: Er kennt die Funktion nicht (PGRST202).
      server.fehlerAntworten['/rest/v1/rpc/match_proximity_spark'] = (
        status: 404,
        body:
            '{"message":"Could not find the function '
            'public.match_proximity_spark"}',
      );

      await expectLater(
        db.matchProximitySpark(
          tokens: <String>['t1'],
          tags: <String>['musik'],
          mode: 'nearby',
          // DER EIGENE TOKEN: Er ist Pflicht - ohne ihn kann der Server
          // keinen Match finden (der Nutzer bliebe mit einem stillen
          // "kein Match" im Glauben, es sei niemand in der Nähe).
          selfToken: 'mein-token',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'transit_server_too_old',
          ),
        ),
        reason:
            'Der Nutzer muss erfahren, dass die App zu alt fuer den Server '
            'ist - ein stilles Scheitern waere wie ein Match ohne Partner.',
      );
    });

    test('ein echter Fachfehler wird nicht verschluckt', () async {
      server.rpcFehler.add('match_proximity_spark');

      await expectLater(
        db.matchProximitySpark(
          tokens: <String>['t1'],
          tags: <String>['musik'],
          mode: 'nearby',
          // DER EIGENE TOKEN: Er ist Pflicht - ohne ihn kann der Server
          // keinen Match finden (der Nutzer bliebe mit einem stillen
          // "kein Match" im Glauben, es sei niemand in der Nähe).
          selfToken: 'mein-token',
        ),
        throwsA(anything),
        reason:
            'Ein Rate-Limit oder ein Jugendschutz-Hinweis darf nicht als '
            '"Server zu alt" weggehen - der Nutzer muss ihn sehen.',
      );
    });
  });

  group('Die Setup-Flags', () {
    test('ohne den Server werden sie gemeldet', () async {
      server.antwortetMitFehler = true;

      await expectLater(
        db.fetchSetupFlags(),
        throwsA(anything),
        reason:
            'Ohne die Flags kennt die App den Einrichtungsstand nicht - das '
            'muss auffallen, nicht stillschweigend weitergehen.',
      );
    });
  });
}
