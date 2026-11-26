// Der Datenbank-Zugriff (Supabase) - bisher weitgehend ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/services/server/supabase_database_service.dart 239 offene Zeilen. Hier
// liegt die ganze Datenbank-Kommunikation der App: das eigene Profil,
// die Präferenzen, die Setup-Flags, die Geräte, die Transit-Spans,
// die Admin-Listen, die Likes. Ein Fehler hier fällt dem Nutzer nicht
// sofort auf - die Einrichtung verschwindet, die Präferenz geht
// verloren, der Like kommt nicht an.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart. Der Server merkt sich, was
// angekommen ist - so sieht der Test, was die App wirklich schickt.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/services/server/supabase_database_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Die ID der anderen Person (eine UUID - der Server akzeptiert nur
/// gültige Peer-IDs).
const String _peerId = '00000000-0000-0000-0000-000000000001';

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
    // Das eigene Profil (der Server liefert es bei jeder Profil-Abfrage).
    server.zeilen['profiles'] = <String, dynamic>{
      'user_id': 'ich',
      'name': 'Lena',
      'bio': 'Liest gern',
      'gender': 'female',
      'gender_preferences': <String>[...kAllGenderValues],
      'birth_date': '1995-06-01',
      'interests': <String>['wandern', 'klettern'],
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
      'intro_text': 'Hallo',
      'intro_audio_path': null,
      'favorite_song': 'Flieder',
      'favorite_band': 'Kraftwerk',
      'birthday_style': 'classic',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'music_liked': <String>[],
      'music_disliked': <String>[],
    };
  });

  /// Der Name der zuletzt aufgerufenen RPC.
  String? letzteRpc() => server.rpcAufrufe.isEmpty
      ? null
      : server.rpcAufrufe.last['funktion'] as String?;

  group('Das eigene Profil', () {
    test('wird vom Server gelesen und umgebaut', () async {
      final profil = await db.fetchOwnProfile();

      expect(profil, isNotNull);
      expect(profil!.name, 'Lena');
      expect(profil.bio, 'Liest gern');
      expect(profil.id, 'ich');
      expect(profil.interests, contains('wandern'));
      // Die Lieblings-Musik und der Geburtstagsstil wurden früher nicht
      // gelesen - dadurch waren sie nach dem ersten Start weg.
      expect(profil.favoriteSong, 'Flieder');
      expect(profil.favoriteBand, 'Kraftwerk');
      expect(profil.birthdayStyle, 'classic');
      expect(profil.introText, 'Hallo');
      expect(profil.isVerified, isTrue);
      expect(profil.country, 'Deutschland');
    });

    test('alle Geschlechter heissen "alle"', () async {
      final profil = await db.fetchOwnProfile();

      expect(
        profil!.genderPreference,
        'all',
        reason:
            'Sind alle Geschlechter ausgewaehlt, gilt der Filter "alle" - '
            'sonst wuerde nur das erste Geschlecht gelten.',
      );
    });

    test('ohne Anmeldung gibt es kein Profil', () async {
      await supabase.Supabase.instance.client.auth.signOut();

      expect(await db.fetchOwnProfile(), isNull);
      expect(await db.fetchOwnSwitches(), isNull);
      expect(await db.fetchOwnPreferences(), isNull);
      expect(await db.fetchSetupFlags(), isNull);

      await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    });

    test('das Profil laesst sich aendern', () async {
      await db.updateOwnProfile(<String, dynamic>{
        'name': 'Lena M.',
        'bio': 'Neu',
      });

      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'profiles'),
        isTrue,
        reason: 'Die Aenderung muss beim Server ankommen.',
      );
      expect(server.zeilen['profiles']?['name'], 'Lena M.');
    });

    test('der Standort wird gespeichert', () async {
      await db.saveOwnLocation(52.52, 13.405);

      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'profile_locations'),
        isTrue,
      );
      expect(server.zeilen['profile_locations']?['lat'], 52.52);
    });
  });

  group('Die Praeferenzen und die Schalter', () {
    test('die Schalter kommen vom Server', () async {
      server.zeilen['profiles'] = <String, dynamic>{
        ...server.zeilen['profiles']!,
        'show_distance': true,
        'notifications_enabled': false,
        'notify_matches': true,
        'notify_likes': false,
        'notify_messages': true,
        'notify_dating_hour': false,
      };

      final schalter = await db.fetchOwnSwitches();

      expect(schalter, isNotNull);
      expect(schalter!['show_distance'], isTrue);
      expect(schalter['notifications_enabled'], isFalse);
      expect(schalter['notify_matches'], isTrue);
    });

    test('die Praeferenzen kommen vom Server', () async {
      server.zeilen['profiles'] = <String, dynamic>{
        ...server.zeilen['profiles']!,
        'max_distance_km': 80,
        'age_range_min': 25,
        'age_range_max': 45,
        'relationship_type': 'serious',
        'preferred_state': 'Bayern',
        'distance_filter_mode': 'state',
        'theme_name': 'dunkel',
      };

      final prefs = await db.fetchOwnPreferences();

      expect(prefs, isNotNull);
      expect(prefs!['max_distance_km'], 80);
      expect(prefs['age_range_min'], 25);
      expect(prefs['distance_filter_mode'], 'state');
      expect(prefs['theme_name'], 'dunkel');
    });

    test('die Setup-Flags kommen vom Server', () async {
      server.zeilen['profiles'] = <String, dynamic>{
        ...server.zeilen['profiles']!,
        'one_time_settings_completed': true,
        'community_guidelines_accepted': true,
        'personality_test_completed': true,
        'onboarding_done': true,
        'dating_hour_intro_seen': true,
        'theme_name': 'hell',
        'paused': false,
      };

      final flags = await db.fetchSetupFlags();

      expect(flags, isNotNull);
      expect(flags!['one_time_settings_completed'], isTrue);
      expect(flags['onboarding_done'], isTrue);
      expect(flags['dating_hour_intro_seen'], isTrue);
    });
  });

  group('Transit Spark', () {
    test('der eigene Token ist Pflicht', () async {
      expect(
        () => SupabaseDatabaseService.buildTransitSparkParams(
          tokens: const <String>['a'],
          tags: const <String>['t'],
          mode: 'blicke',
        ),
        throwsStateError,
        reason:
            'Ohne den eigenen Token kann der Server nicht antworten, ob der '
            'andere einen gesehen hat - der Match waere unmoeglich.',
      );
    });

    test('die Parameter tragen den eigenen Token', () async {
      final params = SupabaseDatabaseService.buildTransitSparkParams(
        tokens: const <String>['a', 'b'],
        tags: const <String>['zug'],
        mode: 'blicke',
        selfToken: '  eigener  ',
        selfNote: '  Hallo  ',
        placeKind: ' Zug ',
        placeText: ' Wagen 3 ',
      );

      expect(params['p_self_token'], 'eigener');
      expect(params['p_self_note'], 'Hallo');
      expect(params['p_place_kind'], 'Zug');
      expect(params['p_place_text'], 'Wagen 3');
      expect(params['p_tokens'], <String>['a', 'b']);
    });

    test('das Heartbeat meldet den eigenen Token', () async {
      await db.transitPresenceHeartbeat('mein-token');

      expect(letzteRpc(), 'transit_presence_heartbeat');
      expect(
        server.rpcAufrufe.last['p_token'],
        'mein-token',
        reason:
            'Der eigene Token muss beim Server liegen - sonst findet der '
            'andere mich nie.',
      );
    });

    test('das Verlassen entfernt den Token wieder', () async {
      await db.transitPresenceLeave();

      expect(letzteRpc(), 'transit_presence_leave');
    });

    test('ein Soft-Ping traegt die Beschreibung', () async {
      await db.sendSoftPing(
        token: 'token-1',
        messageKey: 'transit.ping.hello',
        customLine: 'Steig ein!',
        recipientId: 'partner-1',
        placeKind: 'Zug',
        placeText: 'Wagen 3',
        tags: const <String>['zug'],
        selfTags: const <String>['lesen'],
      );

      expect(letzteRpc(), 'send_soft_ping');
      final aufruf = server.rpcAufrufe.last;
      expect(aufruf['p_token'], 'token-1');
      expect(aufruf['p_message_key'], 'transit.ping.hello');
      expect(aufruf['p_custom_line'], 'Steig ein!');
      expect(aufruf['p_recipient'], 'partner-1');
      expect(aufruf['p_place_kind'], 'Zug');
      expect(aufruf['p_tags'], <String>['zug']);
      expect(aufruf['p_self_tags'], <String>['lesen']);
    });

    test('die Kandidaten kommen von der RPC', () async {
      server.rpcAntworten['list_transit_candidates'] = <dynamic>[
        <String, dynamic>{'token': 'a', 'name': 'Mira'},
      ];

      final kandidaten = await db.listTransitCandidates(
        tags: const <String>['zug'],
      );

      expect(kandidaten, hasLength(1));
      expect(kandidaten.first['name'], 'Mira');
      expect(server.rpcAufrufe.last['p_tags'], <String>['zug']);
    });

    test('die eigenen offenen Pings kommen von der RPC', () async {
      server.rpcAntworten['list_my_soft_pings'] = <dynamic>[
        <String, dynamic>{'id': 'ping-1'},
      ];

      final pings = await db.listMySoftPings();

      expect(pings, hasLength(1));
      expect(pings.first['id'], 'ping-1');
    });

    test('ein Ping annehmen geht an die RPC', () async {
      server.rpcAntworten['accept_soft_ping'] = <String, dynamic>{
        'match_id': 7,
      };

      final ergebnis = await db.acceptSoftPing('ping-1');

      expect(ergebnis['match_id'], 7);
      expect(server.rpcAufrufe.last['p_id'], 'ping-1');
    });
  });

  group('Die Geraete', () {
    test('die Liste kommt vom Server', () async {
      server.zeilen['auth_devices'] = <String, dynamic>{
        'user_id': 'ich',
        'device_id': 'geraet-1',
        'device_name': 'Pixel',
        'platform': 'android',
        'last_seen_at': '2026-11-01T10:00:00Z',
      };

      final geraete = await db.fetchOwnDevices();

      expect(geraete, hasLength(1));
      expect(geraete.first['device_id'], 'geraet-1');
    });

    test('ein Geraet wird angemeldet', () async {
      await db.upsertOwnDevice(
        deviceId: 'geraet-2',
        deviceName: 'Pixel',
        platform: 'android',
        appVersion: '0.10.2',
        deviceModel: 'Pixel 8',
      );

      final schreib = server.schreibvorgaenge.firstWhere(
        (s) => s['tabelle'] == 'auth_devices',
      );
      expect(schreib['device_id'], 'geraet-2');
      expect(schreib['device_name'], 'Pixel');
      expect(schreib['user_id'], 'ich');
      expect(schreib['last_seen_at'], isNotNull);
    });

    test('ein Geraet wird abgeloescht', () async {
      await db.deleteOwnDevice('geraet-1');

      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'auth_devices'),
        isTrue,
      );
    });

    test('die anderen Geraete werden abgeloescht', () async {
      await db.deleteOtherOwnDevices('geraet-1');

      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'auth_devices'),
        isTrue,
      );
    });
  });

  group('Die anderen Nutzer', () {
    test('oeffentliche Profile kommen von der RPC', () async {
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'user_id': 'partner-1',
        'name': 'Mira',
      };

      final profil = await db.fetchPublicProfile('partner-1');

      expect(profil, isNotNull);
      expect(profil!['name'], 'Mira');
      expect(server.rpcAufrufe.last['p_user_id'], 'partner-1');
    });

    test('die Distanz kommt von der RPC', () async {
      server.rpcAntworten['profile_distance_km'] = 12.5;

      expect(await db.fetchDistanceKm('partner-1'), 12.5);
      expect(server.rpcAufrufe.last['p_other'], 'partner-1');
    });

    test('ohne Distanz gibt es keine Zahl', () async {
      server.rpcAntworten['profile_distance_km'] = null;

      expect(await db.fetchDistanceKm('partner-1'), isNull);
    });

    test('die blockierten Nutzer kommen vom Server', () async {
      server.zeilen['blocked_users'] = <String, dynamic>{
        'blocked': 'partner-2',
      };

      final ids = await db.fetchBlockedUserIds();

      expect(ids, <String>['partner-2']);
    });

    test('ein Nutzer wird blockiert', () async {
      await db.blockUser(_peerId);

      expect(letzteRpc(), 'block_user');
      expect(server.rpcAufrufe.last['p_blocked'], _peerId);
    });

    test('ein Nutzer wird entsperrt', () async {
      await db.unblockUser(_peerId);

      expect(letzteRpc(), 'unblock_user');
    });

    test('eine ungueltige Nutzer-ID wird abgewiesen', () async {
      expect(() => db.blockUser('keine-gueltige-id'), throwsA(isA<Object>()));
    });
  });

  group('Die Likes', () {
    test('ein Like geht an die RPC', () async {
      server.rpcAntworten['create_match_if_mutual'] = <String, dynamic>{
        'is_match': true,
        'match_id': 7,
      };

      final ergebnis = await db.insertLike('partner-1');

      expect(ergebnis, isNotNull);
      expect(ergebnis!['is_match'], isTrue);
      expect(ergebnis['match_id'], 7);
      expect(letzteRpc(), 'create_match_if_mutual');
      expect(server.rpcAufrufe.last['p_liked_user_id'], 'partner-1');
    });

    test('ein Like wird zurueckgezogen', () async {
      await db.deleteLike('partner-1');

      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'likes'),
        isTrue,
      );
    });

    test('meine Likes kommen vom Server', () async {
      server.zeilen['likes'] = <String, dynamic>{
        'user_id': 'ich',
        'liked_user_id': 'partner-1',
        'created_at': '2026-11-01T10:00:00Z',
      };
      server.rpcAntworten['get_public_profiles'] = <dynamic>[
        <String, dynamic>{'user_id': 'partner-1', 'name': 'Mira'},
      ];

      final likes = await db.fetchMyLikes();

      expect(likes, hasLength(1));
      expect(likes.first['name'], 'Mira');
      expect(likes.first['liked_at'], '2026-11-01T10:00:00Z');
    });

    test('die Likes fuer mich kommen vom Server', () async {
      server.zeilen['likes'] = <String, dynamic>{
        'user_id': 'partner-1',
        'liked_user_id': 'ich',
        'created_at': '2026-11-02T10:00:00Z',
      };
      server.rpcAntworten['get_public_profiles'] = <dynamic>[
        <String, dynamic>{'user_id': 'partner-1', 'name': 'Mira'},
      ];

      final likes = await db.fetchLikesForMe();

      expect(likes, hasLength(1));
      expect(likes.first['name'], 'Mira');
    });
  });

  group('Der Admin-Bereich', () {
    test('die Listen kommen von den RPCs', () async {
      server.rpcAntworten['admin_list_user_reports'] = <dynamic>[
        <String, dynamic>{'id': 'r1'},
      ];
      server.rpcAntworten['admin_list_bug_reports'] = <dynamic>[
        <String, dynamic>{'id': 'b1'},
      ];
      server.rpcAntworten['admin_list_pending_verifications'] = <dynamic>[
        <String, dynamic>{'id': 'v1'},
      ];
      server.rpcAntworten['admin_list_auto_verifications'] = <dynamic>[
        <String, dynamic>{'id': 'a1'},
      ];
      server.rpcAntworten['admin_list_banned_emails'] = <dynamic>[
        <String, dynamic>{'email': 'x@example.com'},
      ];
      server.rpcAntworten['admin_list_location_checks'] = <dynamic>[
        <String, dynamic>{'user_id': 'partner-1'},
      ];

      expect(await db.fetchUserReports(), hasLength(1));
      expect(await db.fetchBugReports(), hasLength(1));
      expect(await db.fetchPendingVerifications(), hasLength(1));
      expect(await db.fetchAutoVerifications(), hasLength(1));
      expect(await db.fetchBannedEmails(), hasLength(1));
      expect(await db.fetchLocationChecks(), hasLength(1));
    });

    test('der Posteingang wird gelesen, aber nicht beantwortet', () async {
      server.rpcAntworten['admin_list_mail_messages'] = <dynamic>[
        <String, dynamic>{'id': 'm1'},
      ];

      final mails = await db.fetchAdminMailMessages(category: 'support');

      expect(mails, hasLength(1));
      expect(server.rpcAufrufe.last['p_category'], 'support');
      expect(server.rpcAufrufe.last['p_limit'], 100);
    });

    test('eine Meldung wird abgeschlossen', () async {
      await db.resolveUserReport('r1');

      expect(letzteRpc(), 'admin_resolve_user_report');
      expect(server.rpcAufrufe.last['p_report_id'], 'r1');
    });
  });

  group('Die Spuren', () {
    test('die Meldung geht an die RPC', () async {
      await db.submitPhotoAppeal(
        path: 'ich/appeals/1.png',
        label: 'foto-1',
        score: 0.9,
      );

      expect(letzteRpc(), 'submit_photo_appeal');
      expect(server.rpcAufrufe.last['p_path'], 'ich/appeals/1.png');
      expect(server.rpcAufrufe.last['p_score'], 0.9);
    });

    test('der eigene Einspruch wird gelesen', () async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'a1',
        'status': 'pending',
      };

      final appeal = await db.getMyPhotoAppeal();

      expect(appeal, isNotNull);
      expect(appeal!['status'], 'pending');
    });

    test('ohne Einspruch gibt es null', () async {
      server.rpcAntworten['get_my_photo_appeal'] = null;

      expect(await db.getMyPhotoAppeal(), isNull);
    });

    test('der Einspruch wird quittiert', () async {
      await db.acknowledgePhotoAppeal('a1');

      expect(letzteRpc(), 'acknowledge_photo_appeal');
      expect(server.rpcAufrufe.last['p_id'], 'a1');
    });

    test('der Admin listet die Einsprueche', () async {
      server.rpcAntworten['admin_list_photo_appeals'] = <dynamic>[
        <String, dynamic>{'id': 'a1'},
      ];

      final appeals = await db.adminListPhotoAppeals();

      expect(appeals, hasLength(1));
    });

    test('der Admin entscheidet ueber einen Einspruch', () async {
      await db.adminDecidePhotoAppeal(id: 'a1', approve: true);

      expect(letzteRpc(), 'admin_decide_photo_appeal');
      expect(server.rpcAufrufe.last['p_approve'], isTrue);
    });

    test('eine gesperrte E-Mail wird erkannt', () async {
      server.rpcAntworten['check_email_ban_status'] = <String, dynamic>{
        'banned': true,
        'reason': 'Missbrauch',
      };

      final ergebnis = await db.checkEmailBanStatus('  LENA@Example.com ');

      expect(ergebnis.banned, isTrue);
      expect(ergebnis.reason, 'Missbrauch');
      expect(
        server.rpcAufrufe.last['p_email'],
        'lena@example.com',
        reason:
            'Die Adresse wird klein geschrieben - sonst wuerde die '
            'Sperre nicht greifen.',
      );
    });

    test('eine leere Adresse ist nie gesperrt', () async {
      final ergebnis = await db.checkEmailBanStatus('   ');

      expect(ergebnis.banned, isFalse);
    });
  });

  group('Die Funken', () {
    test('die Matches kommen vom Server', () async {
      server.zeilen['matches'] = <String, dynamic>{
        'user_one_id': 'ich',
        'user_two_id': 'partner-1',
      };

      final matches = await db.fetchMatches();

      expect(matches, hasLength(1));
      expect(matches.first['user_two_id'], 'partner-1');
    });

    test('ein Match wird angelegt', () async {
      await db.createMatch(_peerId);

      final schreib = server.schreibvorgaenge.firstWhere(
        (s) => s['tabelle'] == 'matches',
      );
      // Die beiden Nutzer stehen in fester Reihenfolge in der Zeile
      // (sonst würde jeder sie anders anlegen).
      expect(
        <String?>{schreib['user_one_id'], schreib['user_two_id']},
        <String?>{'ich', _peerId},
      );
      expect(schreib['created_at'], isNotNull);
    });

    test('eine ungueltige Peer-ID wird abgewiesen', () async {
      expect(() => db.createMatch('keine-gueltige-id'), throwsA(isA<Object>()));
    });
  });
}
