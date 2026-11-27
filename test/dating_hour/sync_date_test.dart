// Das Sync-Date: Modell, Dienst und Anbieter.
//
// ANLASS (27.11.2026): Der Plan für 0.11.0 ("Begegnung statt
// Bildschirm"): Zwei Menschen, die weit auseinander wohnen, treffen sich
// zur selben Zeit an verschiedenen Orten (Spaziergang + Anruf, derselbe
// Film ...). Der Termin liegt auf dem Server, damit beide Seiten
// denselben Startzeitpunkt sehen.
//
// WAS HIER GEPRÜFT WIRD:
//   * das Modell liest den Serverstand (und überlebt kaputte Werte),
//   * die Idee wird richtig übersetzt (Serverwert -> Katalog),
//   * "beide haben angenommen" wird richtig erkannt,
//   * der Dienst ruft die RPCs mit den richtigen Namen und Parametern,
//   * ein Fehler des Servers wird nicht zum Absturz.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/providers/dating_hour/sync_date_provider.dart';
import 'package:thestia/services/dating_hour/sync_date_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late SyncDateService service;

  setUpAll(() async {
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
    service = SyncDateService(supabase.Supabase.instance.client);
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
  });

  /// Der Serverstand (so liefert die RPC).
  Map<String, dynamic> stand({
    String idea = 'kochDuell',
    bool proposedByMe = true,
    bool acceptedByMe = false,
    bool acceptedByPartner = false,
  }) => <String, dynamic>{
    'matchId': 7,
    'idea': idea,
    'startAt': DateTime.now()
        .add(const Duration(hours: 2))
        .toUtc()
        .toIso8601String(),
    'proposedByMe': proposedByMe,
    'acceptedByMe': acceptedByMe,
    'acceptedByPartner': acceptedByPartner,
  };

  /// Die Namen der aufgerufenen RPCs.
  List<String> aufgerufeneRpcs() =>
      server.rpcAufrufe.map((z) => '${z['funktion']}').toList(growable: false);

  group('Das Modell', () {
    test('liest den Serverstand', () {
      final date = SyncDate.fromJson(stand());

      expect(date.matchId, '7');
      expect(date.idea, SyncDateIdee.kochDuell);
      expect(date.proposedByMe, isTrue);
      expect(date.acceptedByMe, isFalse);
      expect(date.acceptedByPartner, isFalse);
    });

    test('überlebt kaputte Werte', () {
      final date = SyncDate.fromJson(<String, dynamic>{
        'matchId': 42,
        'idea': 'gibtesnicht',
        'startAt': 'kein Datum',
        'proposedByMe': 'vielleicht',
      });

      expect(date.matchId, '42');
      expect(
        date.idea,
        SyncDateIdee.spaziergangAnruf,
        reason: 'Ein unbekannter Wert darf das Date nicht verschwinden lassen.',
      );
      expect(date.acceptedByMe, isFalse);
    });

    test('erkennt "beide haben angenommen"', () {
      final date = SyncDate.fromJson(
        stand(acceptedByMe: true, acceptedByPartner: true),
      );

      expect(date.bothAccepted, isTrue);
    });

    test('erkennt das laufende Date', () {
      final laeuft = SyncDate.fromJson(<String, dynamic>{
        'matchId': 7,
        'idea': 'kochDuell',
        'startAt': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
        'acceptedByMe': true,
        'acceptedByPartner': true,
      });

      expect(
        laeuft.laeuft,
        isTrue,
        reason:
            'Ein Date, das jetzt laeuft, sperrt die App (bis auf den '
            'Chat).',
      );

      // Und ein Date in der Zukunft läuft noch nicht.
      final spaeter = SyncDate.fromJson(stand());
      expect(spaeter.laeuft, isFalse);
    });

    test('die Ideen haben alle einen Text-Schlüssel', () {
      for (final idee in SyncDateIdee.values) {
        expect(idee.textKey, startsWith('sync.idea.'));
        expect(SyncDateIdee.ausWert(idee.wert), idee);
      }
    });
  });

  group('Der Dienst', () {
    test('holt den Stand', () async {
      server.rpcAntworten['get_sync_date'] = stand();

      final date = await service.get('7');

      expect(date, isNotNull);
      expect(date!.idea, SyncDateIdee.kochDuell);
      expect(aufgerufeneRpcs(), contains('get_sync_date'));
    });

    test('ohne Date kommt null', () async {
      server.rpcAntworten['get_sync_date'] = null;

      expect(await service.get('7'), isNull);
    });

    test('schlägt ein Date vor', () async {
      server.rpcAntworten['set_sync_date'] = stand();
      final start = DateTime.now().add(const Duration(hours: 3));

      await service.propose(
        '7',
        idee: SyncDateIdee.gleicherFilm,
        startAt: start,
      );

      final aufruf = server.rpcAufrufe.firstWhere(
        (z) => z['funktion'] == 'set_sync_date',
      );
      expect(aufruf['p_match_id'], 7);
      expect(aufruf['p_idea'], 'gleicherFilm');
      expect(
        aufruf['p_start_at'],
        isNotNull,
        reason: 'Der Zeitpunkt muss mit - er ist der gemeinsame Termin.',
      );
    });

    test('nimmt das Date an', () async {
      server.rpcAntworten['set_sync_date'] = stand(acceptedByMe: true);

      final date = await service.accept('7');

      expect(date?.acceptedByMe, isTrue);
      final aufruf = server.rpcAufrufe.firstWhere(
        (z) => z['funktion'] == 'set_sync_date',
      );
      expect(aufruf['p_accept'], isTrue);
    });

    test('sagt das Date ab', () async {
      await service.decline('7');

      final aufruf = server.rpcAufrufe.firstWhere(
        (z) => z['funktion'] == 'set_sync_date',
      );
      expect(aufruf['p_decline'], isTrue);
    });

    test('ein Serverfehler bringt die App nicht um', () async {
      server.rpcFehler.add('get_sync_date');
      server.rpcFehler.add('set_sync_date');

      expect(await service.get('7'), isNull);
      expect(await service.accept('7'), isNull);
      // Und das Absagen wirft auch nicht.
      await service.decline('7');
    });

    test('ein lokaler Kontakt (keine Match-ID) wird ignoriert', () async {
      expect(await service.get('lokal-1'), isNull);
      expect(
        aufgerufeneRpcs(),
        isEmpty,
        reason: 'Ohne Datenbank-Match darf nichts an den Server gehen.',
      );
    });
  });

  group('Der Anbieter', () {
    test('lädt den Stand beim Start', () async {
      server.rpcAntworten['get_sync_date'] = stand();

      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(syncDateProvider('7').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state, isNotNull);
      expect(notifier.state!.idea, SyncDateIdee.kochDuell);
    });

    test('schlägt vor und merkt sich den Stand', () async {
      server.rpcAntworten['get_sync_date'] = stand();
      server.rpcAntworten['set_sync_date'] = stand(
        idea: 'sterneGucken',
        proposedByMe: true,
      );

      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(syncDateProvider('7').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await notifier.propose(
        idee: SyncDateIdee.sterneGucken,
        startAt: DateTime.now().add(const Duration(hours: 2)),
      );

      expect(notifier.state?.idea, SyncDateIdee.sterneGucken);
    });

    test('das Absagen leert den Stand', () async {
      server.rpcAntworten['get_sync_date'] = stand();

      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(syncDateProvider('7').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await notifier.decline();

      expect(notifier.state, isNull);
    });
  });
}

/// Der Container für den Anbieter (mit dem Server-Client).
ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: <Override>[
      syncDateServiceProvider.overrideWithValue(
        SyncDateService(supabase.Supabase.instance.client),
      ),
    ],
  );
  return container;
}
