// Der Schalter aus der Server-Konfiguration (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/app_config_service.dart 0 %.
//
// WARUM DAS WICHTIG IST: Der Server kann Transit Spark per
// `app_config` abschalten - ohne Deploy und ohne App-Update. Das ist
// die NOTBREMSE fuer den Fall, dass der BLE-Geraetetest nicht besteht.
// Und: Schlaegt das Lesen fehl, muss das Feature AN bleiben (fail-open)
// - ein Lesefehler darf Transit Spark nicht ungefragt stilllegen.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/app_config_service.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

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
    server.zeilen.clear();
    server.antwortetMitFehler = false;
  });

  group('Der Schalter aus der Server-Konfiguration', () {
    test('"false" schaltet Transit Spark ab', () async {
      server.zeilen['app_config'] = <String, dynamic>{'value': 'false'};

      expect(await AppConfigService.fetchTransitSparkEnabled(), isFalse);
    });

    test('"true" laesst Transit Spark an', () async {
      server.zeilen['app_config'] = <String, dynamic>{'value': 'true'};

      expect(await AppConfigService.fetchTransitSparkEnabled(), isTrue);
    });

    test('ohne Eintrag bleibt Transit Spark an', () async {
      // Kein Eintrag = der Schalter wurde nie gesetzt = das Feature
      // laeuft (so war es immer).
      server.zeilen.clear();

      expect(await AppConfigService.fetchTransitSparkEnabled(), isTrue);
    });

    test('ein Lesefehler laesst Transit Spark an', () async {
      // FAIL-OPEN: Ein Fehler beim Lesen darf das Feature nicht
      // ungefragt stilllegen - der Server entscheidet ohnehin.
      server.antwortetMitFehler = true;

      expect(await AppConfigService.fetchTransitSparkEnabled(), isTrue);
    });

    test('die Mindest-Build-Nummer wird gelesen', () async {
      server.zeilen['app_config'] = <String, dynamic>{'value': '57'};

      expect(await AppConfigService.fetchMinAppVersionBuild(), 57);
    });

    test('ohne Eintrag gibt es keine Mindest-Build-Nummer', () async {
      server.zeilen.clear();

      // null heisst: keine Vorgabe - die App laesst den Nutzer
      // ungefragt auf die alte Version.
      expect(await AppConfigService.fetchMinAppVersionBuild(), isNull);
    });
  });
}
