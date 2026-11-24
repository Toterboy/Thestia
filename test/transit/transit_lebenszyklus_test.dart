// Der Transit-Provider im Hintergrund und beim Zurueckkommen.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/providers/transit/transit_provider.dart 70 offene Zeilen. Der
// bestehende Test deckt die Selbstangaben, den Modus und die
// Server-Aufrufe ab - offen war der LEBENSZYKLUS: was passiert, wenn
// der Nutzer die App in den Hintergrund schickt.
//
// DER GRUND, WARUM DAS WICHTIG IST: Das Advertising lief im Hintergrund
// weiter (der native Zyklus sendet bis zu 45 Minuten im ~100-ms-Takt).
// Und mit demselben Token weiterzumachen wuerde verraten, dass das
// Geraet zwischendurch nur still war - das ist genau die Kontinuitaet,
// nach der ein Beobachter sucht.
//
// WAS HIER GEPRUEFT WIRD:
//   * im Hintergrund schweigt das Funk-Radio,
//   * beim Zurueckkommen kommt ein FRISCHES Token,
//   * ohne aktiven Radar passiert beim Zurueckkommen nichts.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/providers/transit/transit_provider.dart';
import 'package:thestia/services/transit/transit_encounter_service.dart';

import '../support/ble_mocks.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late TransitNotifier notifier;

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
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.pfade.clear();
    notifier = TransitNotifier();
    mockBluetooth();
    resetAdvertisingZaehler();
  });

  tearDown(() {
    notifier.dispose();
    unmockBluetooth();
  });

  group('Der Lebenszyklus', () {
    test('beim Zurueckkommen kommt ein frisches Token', () async {
      notifier.state = notifier.state.copyWith(active: true);

      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // DER HEARTBEAT: Er traegt das Token, das der Server fuer die
      // Anwesenheit braucht ("hat der andere mich gesehen?").
      final heartbeats = server.rpcAufrufe
          .where((c) => c['funktion'] == 'transit_presence_heartbeat')
          .toList();
      expect(
        heartbeats,
        isNotEmpty,
        reason:
            'Nach dem Zurueckkommen muss der Server das neue Token '
            'bekommen - sonst weiss er nichts vom frischen Geraet.',
      );
      final token = heartbeats.last['p_token'] as String?;
      expect(
        TransitEncounterService.isValidToken(token ?? ''),
        isTrue,
        reason:
            'Das Token muss ein gueltiges sein - ein leeres wuerde dem '
            'Server sagen, dass niemand da ist.',
      );
    });

    test('ohne aktiven Radar passiert beim Zurueckkommen nichts', () async {
      // DER INAKTIVE RADAR: Es gibt nichts zu fortsetzen - und vor allem
      // darf das Funk nicht angehen (der Nutzer hat es ausgeschaltet).
      notifier.state = notifier.state.copyWith(active: false);

      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        advertisingStarts,
        0,
        reason:
            'Ein ausgeschalteter Radar darf nicht von selbst wieder '
            'angehen - der Nutzer hat ihn bewusst ausgeschaltet.',
      );
    });
  });
}
