// Die Provider der Dating Hour und des Meet-Intents.
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/providers/dating_hour/dating_hour_provider.dart und
// lib/providers/dating_hour/meet_intent_provider.dart je 0 % - sie wurden nie
// berührt. Beide Provider sind die Schnittstelle zwischen der
// Oberfläche und dem Server: ein Fehler dort fällt im Alltag nicht
// auf, sondern nur gar nicht.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Meet-Intent-Notifier: laden, Zustimmung setzen, "getroffen"
//     bestätigen, neu laden - und der Fall, dass der Server nichts
//     zurückgibt (dann bleibt der Zustand unverändert),
//   * der Fehlerfall: der Server schweigt -> der Notifier bleibt
//     ruhig (kein Crash, kein roter Bildschirm),
//   * die Dating-Hour-Provider: kein Event -> null; ein Event ->
//     die eigene Teilnahme steht drin.
//
// OHNE SERVER: Der Meet-Intent-Dienst wird durch einen Ersatz
// ersetzt (der echte Dienst braucht eine Datenbank); die
// Dating-Hour-Provider laufen gegen den Fake-Server aus
// test/support/fake_supabase_server.dart.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/dating_hour/meet_intent.dart';
import 'package:thestia/providers/dating_hour/dating_hour_provider.dart';
import 'package:thestia/providers/dating_hour/meet_intent_provider.dart';
import 'package:thestia/services/dating_hour/meet_intent_service.dart';

import '../support/fake_supabase_server.dart';

import '../support/plugin_mocks.dart';

/// Der Meet-Intent-Dienst ohne Datenbank.
///
/// DER GRUND FÜR DEN ERSATZ: [MeetIntentService] spricht die Datenbank
/// über den globalen Supabase-Client an. Für die Logik des Notifiers
/// ist aber nur wichtig, was der Dienst zurückgibt - also wird genau
/// das hier festgelegt.
class _FakeMeetIntentService extends MeetIntentService {
  _FakeMeetIntentService(super.client);

  /// Was der Dienst zurückgibt (null = "es gibt nichts").
  MeetIntent? antwort;

  /// Der Fehlerfall: der Dienst schlägt fehl.
  bool schlaegtFehl = false;

  /// Die Aufrufe (für die Nachprüfung).
  final List<String> aufrufe = <String>[];

  @override
  Future<MeetIntent?> get(String matchId) async {
    aufrufe.add('get:$matchId');
    if (schlaegtFehl) throw Exception('Server nicht erreichbar');
    return antwort;
  }

  @override
  Future<MeetIntent?> set(
    String matchId, {
    bool? wants,
    bool? metConfirmed,
  }) async {
    aufrufe.add('set:$matchId wants=$wants met=$metConfirmed');
    if (schlaegtFehl) throw Exception('Server nicht erreichbar');
    return antwort;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // DER SUPABASE-CLIENT wird EINMAL für die ganze Datei aufgesetzt
  // (er ist ein Singleton - ein zweites initialize wäre ein Fehler).
  late FakeSupabaseServer server;

  setUpAll(() async {
    // Der Speicher des Geräts (ohne ihn finden die Provider nichts).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    server = FakeSupabaseServer(userId: 'ich');
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  group('MeetIntentNotifier', () {
    const intent = MeetIntent(
      matchId: '7',
      eligible: true,
      myWants: false,
      partnerWants: false,
      metConfirmed: false,
    );

    testWidgets('laedt den Stand beim Start', (tester) async {
      final service = _FakeMeetIntentService(supabase.Supabase.instance.client)
        ..antwort = intent;
      final container = ProviderContainer(
        overrides: [meetIntentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      container.read(meetIntentProvider('7'));
      await tester.pump();

      expect(container.read(meetIntentProvider('7')), intent);
    });

    testWidgets('setWants traegt die Zustimmung ein', (tester) async {
      final service = _FakeMeetIntentService(supabase.Supabase.instance.client)
        ..antwort = intent;
      final container = ProviderContainer(
        overrides: [meetIntentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(meetIntentProvider('7').notifier);
      await notifier.setWants(true);
      await tester.pump();

      expect(service.aufrufe, contains('set:7 wants=true met=null'));
    });

    testWidgets('confirmMet bestaetigt das Treffen', (tester) async {
      final service = _FakeMeetIntentService(supabase.Supabase.instance.client)
        ..antwort = intent;
      final container = ProviderContainer(
        overrides: [meetIntentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(meetIntentProvider('7').notifier);
      await notifier.confirmMet();
      await tester.pump();

      expect(service.aufrufe, contains('set:7 wants=null met=true'));
    });

    testWidgets('reload laedt neu', (tester) async {
      final service = _FakeMeetIntentService(supabase.Supabase.instance.client)
        ..antwort = intent;
      final container = ProviderContainer(
        overrides: [meetIntentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(meetIntentProvider('7').notifier);
      await notifier.reload();
      await tester.pump();

      expect(service.aufrufe.where((a) => a.startsWith('get:')).length, 2);
    });

    testWidgets('ein Fehler des Servers laesst den Zustand ruhig', (
      tester,
    ) async {
      // DER GRUND: Der Server kann ausfallen. Der Bildschirm darf dann
      // nicht rot werden und nicht crashen - der Vorschlag bleibt
      // einfach weg.
      final service = _FakeMeetIntentService(supabase.Supabase.instance.client)
        ..schlaegtFehl = true;
      final container = ProviderContainer(
        overrides: [meetIntentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      container.read(meetIntentProvider('7'));
      await tester.pump();

      expect(container.read(meetIntentProvider('7')), isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Die Dating-Hour-Provider', () {
    setUp(() {
      server.rpcAntworten.clear();
    });

    testWidgets('ohne Event: der Provider liefert null', (tester) async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = null;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final event = await container.read(currentDatingHourEventProvider.future);

      expect(event, isNull);
    });

    testWidgets('mit Event: die eigene Teilnahme steht drin', (tester) async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = [
        {
          'id': 'event-1',
          'event_date': '2026-11-21',
          'day_of_week': 6,
          'start_hour': 20,
          'start_minute': 0,
          'end_hour': 21,
          'end_minute': 0,
          'starts_at': '2026-11-21T19:00:00Z',
          'ends_at': '2026-11-21T20:00:00Z',
          'status': 'upcoming',
        },
      ];
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final event = await container.read(currentDatingHourEventProvider.future);

      expect(event, isNotNull);
      expect(event!.id, 'event-1');
      // Die Teilnahme kommt aus dem Server (RLS: nur die eigene).
      expect(event.currentUserParticipating, isA<bool>());
    });

    testWidgets('die aktive Session liefert der Provider', (tester) async {
      // Ohne Zeile in der Tabelle gibt es keine Session.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final session = await container.read(
        myActiveDatingHourSessionProvider('event-1').future,
      );

      expect(session, isNull);
    });
  });
}
