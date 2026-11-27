// Die Server-Wege des DatingHourService (die RPCs).
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/dating_hour/dating_hour_service.dart 43 offene Zeilen.
// Getestet war nur die reine Zeitlogik - der Weg zum Server (Beitritt,
// Austritt, Teilnehmerzahl, Präferenzen) lief ins Leere.
//
// WAS HIER GEPRÜFT WIRD:
//   * das Beitreten ruft die beiden RPCs (join_dating_hour und
//     match_dating_hour_round),
//   * ohne Event und bei einem beendeten Event wird nicht beigetreten,
//   * ein Serverfehler wird als DatingHourException gemeldet,
//   * die Teilnehmerzahl kommt vom Server - und ist bei einem Fehler 0
//     (die Anzeige darf nicht hängen),
//   * die Präferenzen werden gespeichert und zurückgelesen.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/services/dating_hour/dating_hour_service.dart';
import 'package:thestia/services/server/server_time_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  final service = DatingHourService();

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
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
    ServerTimeService.instance.resetForTesting();
  });

  /// Ein Event, in das man noch beitreten kann (endet in einer Stunde).
  Map<String, dynamic> aktivesEvent() {
    final jetzt = DateTime.now();
    return <String, dynamic>{
      'id': 'e1',
      'event_date': jetzt.toIso8601String(),
      'day_of_week': 6,
      'start_hour': 20,
      'start_minute': 0,
      'end_hour': 22,
      'end_minute': 0,
      'starts_at': jetzt.add(const Duration(minutes: 30)).toIso8601String(),
      'ends_at': jetzt.add(const Duration(hours: 1)).toIso8601String(),
      'status': 'active',
    };
  }

  /// Die Präferenzen (irgendwelche - der Server entscheidet danach).
  DatingHourPreferences prefFuerTest() => const DatingHourPreferences(
    ageMin: 18,
    ageMax: 35,
    genderPreference: 'all',
    preferredTrait: 'Humor',
    maxDistanceKm: 50,
  );

  /// Die Namen der aufgerufenen RPCs.
  List<String> aufgerufeneRpcs() =>
      server.rpcAufrufe.map((z) => '${z['funktion']}').toList(growable: false);

  group('Das Beitreten', () {
    test('ruft die RPCs für Beitritt und Paarung', () async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[
        aktivesEvent(),
      ];

      await service.joinEvent('ich', prefFuerTest());

      expect(
        aufgerufeneRpcs(),
        containsAll(<String>[
          'get_current_or_next_dating_hour',
          'join_dating_hour',
          'match_dating_hour_round',
        ]),
      );
      // Die Präferenzen gehen mit (der Server entscheidet danach).
      final beitritt = server.rpcAufrufe.firstWhere(
        (z) => '${z['funktion']}' == 'join_dating_hour',
      );
      expect(beitritt['p_event_id'], 'e1');
      expect(beitritt['p_preferences'], isNotNull);
    });

    test('ohne Event wird nicht beigetreten', () async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[];

      await expectLater(
        service.joinEvent('ich', prefFuerTest()),
        throwsA(isA<DatingHourException>()),
      );
      expect(aufgerufeneRpcs(), isNot(contains('join_dating_hour')));
    });

    test('ein beendetes Event wird nicht betreten', () async {
      final jetzt = DateTime.now();
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[
        <String, dynamic>{
          ...aktivesEvent(),
          'status': 'ended',
          'ends_at': jetzt.subtract(const Duration(hours: 1)).toIso8601String(),
        },
      ];

      await expectLater(
        service.joinEvent('ich', prefFuerTest()),
        throwsA(isA<DatingHourException>()),
      );
      expect(aufgerufeneRpcs(), isNot(contains('join_dating_hour')));
    });

    test('ein Serverfehler wird als Ausnahme gemeldet', () async {
      server.rpcFehler.add('get_current_or_next_dating_hour');

      await expectLater(
        service.getCurrentOrNextEvent(),
        throwsA(isA<DatingHourException>()),
      );
    });
  });

  group('Der Austritt', () {
    test('ruft die RPC für das Verlassen', () async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[
        aktivesEvent(),
      ];

      await service.leaveEvent('ich');

      expect(aufgerufeneRpcs(), contains('leave_dating_hour'));
    });

    test('ohne Event wird nichts verlassen', () async {
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[];

      await expectLater(
        service.leaveEvent('ich'),
        throwsA(isA<DatingHourException>()),
      );
    });
  });

  group('Die Teilnehmerzahl', () {
    test('kommt vom Server', () async {
      server.rpcAntworten['get_dating_hour_participant_count'] = 7;

      expect(await service.getParticipantCount('e1'), 7);
    });

    test(
      'ist bei einem Serverfehler 0 (die Anzeige darf nicht hängen)',
      () async {
        server.rpcFehler.add('get_dating_hour_participant_count');

        expect(await service.getParticipantCount('e1'), 0);
      },
    );

    test('ist 0, wenn der Server nichts liefert', () async {
      server.rpcAntworten['get_dating_hour_participant_count'] = null;

      expect(await service.getParticipantCount('e1'), 0);
    });
  });

  group('Die Präferenzen', () {
    test('werden gespeichert', () async {
      await service.savePreferences('e1', prefFuerTest());

      expect(aufgerufeneRpcs(), contains('save_dating_hour_preferences'));
    });

    test('werden zurückgelesen', () async {
      server.rpcAntworten['get_last_dating_hour_preferences'] =
          <String, dynamic>{'gender': 'men'};

      final prefs = await service.getMyLastPreferences();

      expect(prefs?['gender'], 'men');
    });

    test('ohne gespeicherte Präferenzen kommt null', () async {
      // Der Server liefert JSON null - das ist "keine Präferenzen".
      server.rpcAntworten['get_last_dating_hour_preferences'] = null;

      expect(await service.getMyLastPreferences(), isNull);
    });
  });

  group('Die Teilnahme', () {
    test('mit Zeile ohne Austrittszeit ist der Nutzer dabei', () async {
      server.zeilen['dating_hour_participant'] = <String, dynamic>{
        'event_id': 'e1',
        'user_id': 'ich',
        'left_at': null,
      };

      expect(await service.isUserParticipating('e1'), isTrue);
    });
  });
}
