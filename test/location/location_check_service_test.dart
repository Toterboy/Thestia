// Die Standort-Prüfung des Servers (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/services/profile/location_check_service.dart 0 %.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Prüfung geht mit der Nutzer-ID und den neuen Koordinaten an
//     den Server,
//   * die Antwort des Servers wird zurückgegeben,
//   * ein Fehler fährt zu null (kein Absturz, kein falsches Ergebnis).
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart - er zeichnet die
// Edge-Function-Aufrufe auf.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/profile/location_check_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;

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
  });

  setUp(() {
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
    server.antwortetMitFehler = false;
  });

  group('Die Standort-Pruefung', () {
    test('die Pruefung geht an den Server', () async {
      server.funktionsAntworten['process-location-check'] = <String, dynamic>{
        'suspicious': false,
        'distanceKm': 3.2,
      };
      final service = LocationCheckService(supabase.Supabase.instance.client);

      final ergebnis = await service.processLocationCheck(
        userId: 'user-42',
        newLatitude: 53.08,
        newLongitude: 8.81,
      );

      // Der Aufruf ist angekommen - mit Nutzer und Koordinaten.
      expect(server.funktionsAufrufe, hasLength(1));
      final aufruf = server.funktionsAufrufe.first;
      expect(aufruf['funktion'], 'process-location-check');
      expect(aufruf['userId'], 'user-42');
      expect(aufruf['newLatitude'], 53.08);
      expect(aufruf['newLongitude'], 8.81);
      // Und die Antwort kommt zurück.
      expect(ergebnis, isNotNull);
      expect(ergebnis!['suspicious'], isFalse);
    });

    test('ein Fehler fuehrt zu null', () async {
      server.antwortetMitFehler = true;
      final service = LocationCheckService(supabase.Supabase.instance.client);

      // Kein Absturz, und KEIN erfundenes Ergebnis: der Aufrufer
      // entscheidet selbst, was ein Ausfall bedeutet.
      final ergebnis = await service.processLocationCheck(
        userId: 'user-42',
        newLatitude: 53.08,
        newLongitude: 8.81,
      );

      expect(ergebnis, isNull);
    });
  });
}
