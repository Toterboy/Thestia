// Die Server-Wege von "Find your Match".
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/dating_hour/find_your_match_service.dart 50 offene Zeilen.
// Getestet war nur der Bildschirm mit dem Fake-Server - die Dienste
// selbst (die RPC-Aufrufe, das Ausblenden eines Likes, die
// Erinnerungsliste, die Lösch-Hinweise) liefen ins Leere.
//
// WAS HIER GEPRÜFT WIRD:
//   * jede Aktion ruft die RPC mit dem richtigen Namen und den
//     richtigen Parametern (der Server entscheidet danach),
//   * "Ausblenden" ruft eine eigene RPC auf - die andere Person darf
//     nichts davon sehen,
//   * der Nachrichtenzähler ist best-effort (ein Fehler darf das
//     Senden nie stören),
//   * die Erinnerungsliste liest, schreibt, hakt ab und löscht - und
//     übersteht einen Serverfehler,
//   * die Lösch-Hinweise ("für alle gelöscht") kommen vom Server.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/dating_hour/find_your_match_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late FindYourMatchService service;

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
    service = FindYourMatchService(supabase.Supabase.instance.client);
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
    server.funktionsAntworten.clear();
  });

  /// Die Namen der aufgerufenen RPCs.
  List<String> aufgerufeneRpcs() =>
      server.rpcAufrufe.map((z) => '${z['funktion']}').toList(growable: false);

  /// Der Aufruf einer bestimmten RPC (oder null).
  Map<String, dynamic>? aufruf(String name) {
    for (final z in server.rpcAufrufe) {
      if ('${z['funktion']}' == name) return z;
    }
    return null;
  }

  /// Ein öffentliches Profil (so kommt es von der Sicht).
  Map<String, dynamic> profil([String id = 'sie']) => <String, dynamic>{
    'user_id': id,
    'name': 'Mara',
    'age': 28,
    'bio': 'Liest gern',
    'interests': <String>['Musik'],
  };

  group('Die Kandidaten', () {
    test('kommen von der RPC mit dem Limit', () async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[profil()];

      final kandidaten = await service.getCandidates(limit: 5);

      expect(kandidaten, hasLength(1));
      expect(kandidaten.first.id, 'sie');
      expect(kandidaten.first.name, 'Mara');
      expect(aufgerufeneRpcs(), contains('get_find_match_candidates'));
      expect(aufruf('get_find_match_candidates')?['p_limit'], 5);
    });

    test('ohne Antwort ist die Liste leer', () async {
      server.rpcAntworten['get_find_match_candidates'] = null;

      expect(await service.getCandidates(), isEmpty);
    });

    test('die einer Kategorie tragen die Grenzen mit', () async {
      server.rpcAntworten['get_find_match_by_category'] = <dynamic>[profil()];

      final kandidaten = await service.getCandidatesByCategory(
        'Musik',
        ageMin: 18,
        ageMax: 30,
      );

      expect(kandidaten, hasLength(1));
      final aufrufDaten = aufruf('get_find_match_by_category');
      expect(aufrufDaten?['p_category'], 'Musik');
      expect(aufrufDaten?['p_age_min'], 18);
      expect(aufrufDaten?['p_age_max'], 30);
    });

    test('die Kategorien kommen mit ihrer Zahl', () async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 4},
        <String, dynamic>{'category': 'Sport', 'cnt': 0},
      ];

      final zahlen = await service.getCategoryCounts(ageMin: 18, ageMax: 35);

      expect(zahlen, hasLength(2));
      expect(zahlen.first.category, 'Musik');
      expect(zahlen.first.count, 4);
    });
  });

  group('Der Like', () {
    test('meldet dem Server das Ergebnis', () async {
      server.rpcAntworten['like_user'] = <String, dynamic>{
        'is_match': true,
        'already_matched': false,
      };

      final ergebnis = await service.likeUser('sie');

      expect(ergebnis?['is_match'], isTrue);
      expect(aufruf('like_user')?['p_target'], 'sie');
    });

    test('ohne Antwort kommt null', () async {
      server.rpcAntworten['like_user'] = null;

      expect(await service.likeUser('sie'), isNull);
    });

    test('das Ausblenden ruft die eigene RPC', () async {
      await service.ignoreLike(42);

      final aufrufDaten = aufruf('ignore_like');
      expect(aufrufDaten, isNotNull);
      expect(aufrufDaten?['p_like_id'], 42);
      // Der Ausblende-Weg darf NICHT die Ablehnung sein - die andere
      // Person würde die Ablehnung sehen.
      expect(aufgerufeneRpcs(), isNot(contains('respond_to_like')));
    });

    test('das Annehmen und das Ablehnen unterscheiden sich', () async {
      await service.respondToLike(7, accept: true);
      expect(aufruf('respond_to_like')?['p_accept'], isTrue);

      await service.respondToLike(8, accept: false);
      expect(
        server.rpcAufrufe.last['p_accept'],
        isFalse,
        reason: 'Beim Ablehnen muss der Server "nein" sehen.',
      );
    });
  });

  group('Die Like-Listen', () {
    test('die eigenen Likes werden gelesen', () async {
      server.rpcAntworten['list_my_likes_pending'] = <dynamic>[
        <String, dynamic>{
          'likeId': 3,
          'profile': profil(),
          'createdAt': '2026-11-20T10:00:00Z',
        },
      ];

      final likes = await service.listMyLikes();

      expect(likes, hasLength(1));
      expect(likes.first.likeId, 3);
      expect(likes.first.profile.name, 'Mara');
      expect(aufgerufeneRpcs(), contains('list_my_likes_pending'));
    });

    test('die erhaltenen Likes werden gelesen', () async {
      server.rpcAntworten['list_received_likes_pending'] = <dynamic>[
        <String, dynamic>{'likeId': 9, 'profile': profil()},
      ];

      final likes = await service.listReceivedLikes();

      expect(likes.first.likeId, 9);
      expect(aufgerufeneRpcs(), contains('list_received_likes_pending'));
    });

    test('ohne Antwort ist die Liste leer', () async {
      server.rpcAntworten['list_my_likes_pending'] = null;

      expect(await service.listMyLikes(), isEmpty);
    });
  });

  group('Der Nachrichtenzähler', () {
    test('geht mit der Nachrichten-ID zum Server', () async {
      await service.bumpMessageCount(matchId: 12, messageId: 'm-1');

      final aufrufDaten = aufruf('bump_match_message_count');
      expect(aufrufDaten?['p_match_id'], 12);
      expect(aufrufDaten?['p_message_id'], 'm-1');
    });

    test('ein Fehler stört das Senden nicht', () async {
      server.rpcFehler.add('bump_match_message_count');

      // Der Aufruf darf NICHT werfen - das Senden würde sonst scheitern.
      await service.bumpMessageCount(matchId: 12, messageId: 'm-1');
    });
  });

  group('Das Löschen für alle', () {
    test('geht an den Server', () async {
      await service.deleteMessageForAll(matchId: 12, messageId: 'm-1');

      final aufrufDaten = aufruf('delete_message_for_all');
      expect(aufrufDaten?['p_match_id'], 12);
      expect(aufrufDaten?['p_message_id'], 'm-1');
    });

    test('die Hinweise kommen vom Server', () async {
      server.rpcAntworten['list_message_deletions'] = <dynamic>[
        <String, dynamic>{
          'messageId': 'm-1',
          'deletedAt': '2026-11-20T10:00:00Z',
        },
      ];

      final hinweise = await service.listMessageDeletions(12);

      expect(hinweise, hasLength(1));
      expect(hinweise.first.messageId, 'm-1');
      expect(hinweise.first.deletedAt, isNotNull);
    });
  });

  group('Die Funken-Liste', () {
    test('kommt mit dem Freischaltungsstand', () async {
      server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[
        <String, dynamic>{
          'matchId': 5,
          'profile': profil(),
          'unlockLevel': 2,
          'failedAttempts': 1,
          'status': 'active',
          'messageCount': 4,
        },
      ];

      final funken = await service.listMatchesWithState();

      expect(funken, hasLength(1));
      expect(funken.first.matchId, 5);
      expect(funken.first.unlockLevel, 2);
      expect(funken.first.messageCount, 4);
      expect(funken.first.partner.name, 'Mara');
    });

    test('ohne Antwort ist die Liste leer', () async {
      server.rpcAntworten['list_my_matches_with_state'] = null;

      expect(await service.listMatchesWithState(), isEmpty);
    });
  });

  group('Der Funken-Status', () {
    test('das Kühlen, Reaktivieren und Beenden', () async {
      await service.coolMatch(1);
      await service.resparkMatch(2);
      await service.endMatch(3);
      await service.hideMatch(4);

      expect(aufgerufeneRpcs(), contains('cool_match'));
      expect(aufgerufeneRpcs(), contains('respark_match'));
      expect(aufgerufeneRpcs(), contains('end_match'));
      expect(aufgerufeneRpcs(), contains('hide_match'));
      expect(aufruf('cool_match')?['p_match_id'], 1);
      expect(aufruf('respark_match')?['p_match_id'], 2);
    });

    test('die Art des Funkens wird umgeschaltet', () async {
      await service.setMatchKind(5, friends: true);
      expect(aufruf('set_match_kind')?['p_kind'], 'friends');

      await service.setMatchKind(5, friends: false);
      expect(server.rpcAufrufe.last['p_kind'], 'spark');
    });
  });

  group('Die Erinnerungsliste', () {
    test('wird gelesen', () async {
      server.rpcAntworten['match_bucket_items'] = <dynamic>[
        <String, dynamic>{
          'id': 1,
          'text': 'Tandem fahren',
          'createdBy': 'ich',
          'done': false,
        },
      ];

      final eintraege = await service.bucketItems(5);

      expect(eintraege, hasLength(1));
      expect(eintraege.first.text, 'Tandem fahren');
      expect(eintraege.first.done, isFalse);
    });

    test('ein Eintrag wird hinzugefügt', () async {
      server.rpcAntworten['match_bucket_add'] = 17;

      expect(await service.bucketAdd(5, 'Tandem fahren'), 17);
      expect(aufruf('match_bucket_add')?['p_text'], 'Tandem fahren');
    });

    test('ein Eintrag wird abgehakt', () async {
      server.rpcAntworten['match_bucket_toggle'] = <String, dynamic>{
        'done': true,
      };

      expect(await service.bucketToggle(1), isTrue);
      expect(aufruf('match_bucket_toggle')?['p_item_id'], 1);
    });

    test('ein eigener Eintrag wird gelöscht', () async {
      await service.bucketDelete(1);

      expect(aufruf('match_bucket_delete')?['p_item_id'], 1);
    });

    test('ein Serverfehler bringt die Liste nicht um', () async {
      server.rpcFehler.add('match_bucket_items');
      server.rpcFehler.add('match_bucket_add');
      server.rpcFehler.add('match_bucket_toggle');
      server.rpcFehler.add('match_bucket_delete');

      expect(await service.bucketItems(5), isEmpty);
      expect(await service.bucketAdd(5, 'Tandem'), isNull);
      expect(await service.bucketToggle(1), isFalse);
      await service.bucketDelete(1);
    });
  });

  group('Die Medien-URLs', () {
    test('das Intro-Audio kommt von der Edge Function', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{
        'url': 'https://example.supabase.co/storage/v1/object/sign/x',
      };

      final url = await service.getIntroAudioUrl('sie');

      expect(url, isNotNull);
      expect(server.funktionsAufrufe.last['funktion'], 'match-media');
      expect(server.funktionsAufrufe.last['kind'], 'intro');
    });

    test('das Avatar kommt von der Edge Function', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{
        'url': 'https://example.supabase.co/storage/v1/object/sign/y',
      };

      final url = await service.getAvatarUrl('sie');

      expect(url, isNotNull);
      expect(server.funktionsAufrufe.last['kind'], 'avatar');
    });

    test('ohne URL kommt null', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{};

      expect(await service.getIntroAudioUrl('sie'), isNull);
      expect(await service.getAvatarUrl('sie'), isNull);
    });
  });
}
