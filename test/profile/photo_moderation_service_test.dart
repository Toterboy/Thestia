// Der Dienst der Bild-Moderierung.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/services/profile/photo_moderation_service.dart nur 39 %
// Abdeckung.
//
// DER WEG: Der Server ist der [FakeSupabaseServer] (test/support/
// fake_supabase_server.dart).
//
// WAS HIER GEPRÜFT WIRD:
//   * die NSFW-Moderierung ist AUS (der Standard) - das Bild wird
//     freigegeben und es entsteht KEIN Eintrag in der Admin-Warteschlange
//     (der Kommentar des Feature-Flags verspricht genau das),
//   * der Gesichtsabgleich gibt NIEMALS "ja" zurück (fail-closed: eine
//     nicht vorhandene Prüfung darf nicht als bestanden gelten),
//   * der Admin sieht die wartenden Prüfungen,
//   * ein Serverfehler beim Admin-Abruf leert die Liste (kein Absturz).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/profile/photo_moderation_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late PhotoModerationService dienst;

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
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
    server.fehlerAntworten.clear();
    server.antwortetMitFehler = false;
    dienst = PhotoModerationService(supabase.Supabase.instance.client);
  });

  group('Die Bild-Pruefung', () {
    test('ohne die Moderierung wird das Bild freigegeben', () async {
      final ergebnis = await dienst.checkNudityContent(
        userId: 'ich',
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(
        ergebnis.approved,
        isTrue,
        reason:
            'Die Moderierung ist im Standard aus - das Bild muss '
            'durchgelassen werden.',
      );
      expect(
        server.schreibvorgaenge.where(
          (s) => s['tabelle'] == 'photo_moderation',
        ),
        isEmpty,
        reason:
            'Ohne Moderierung darf KEIN Eintrag in der Admin-Warteschlange '
            'entstehen - sonst sammelt die App Daten ohne Zweck.',
      );
    });

    test('der Gesichtsabgleich gibt niemals "ja" zurueck', () async {
      final passt = await dienst.checkFaceMatch(
        userId: 'ich',
        photoUrl: 'https://example.supabase.co/foto.jpg',
        verificationVideoPath: '/tmp/video.mp4',
      );

      expect(
        passt,
        isFalse,
        reason:
            'Es gibt noch keine echte Pruefung - "ja" wuerde eine '
            'nicht vorhandene Verifizierung vortaeuschen (fail-closed).',
      );
    });
  });

  group('Die Admin-Warteschlange', () {
    test('die wartenden Pruefungen kommen vom Server', () async {
      server.zeilen['photo_moderation'] = <String, dynamic>{
        'id': 1,
        'user_id': 'ich',
        'status': 'pending_review',
      };

      final wartende = await dienst.fetchPendingReviews();

      expect(wartende, isNotEmpty);
      expect(wartende.first['status'], 'pending_review');
    });

    test('ohne den Server ist die Liste leer', () async {
      server.antwortetMitFehler = true;

      final wartende = await dienst.fetchPendingReviews();

      expect(
        wartende,
        isEmpty,
        reason:
            'Ein Serverfehler darf den Admin-Bereich nicht sprengen - er '
            'sieht dann eben keine wartenden Pruefungen.',
      );
    });

    test('das Genehmigen geht an den Server', () async {
      await dienst.approvePhoto(1, 'admin-1');

      final schreibvorgaenge = server.schreibvorgaenge
          .where((s) => s['tabelle'] == 'photo_moderation')
          .toList();
      expect(schreibvorgaenge, isNotEmpty);
      expect(
        schreibvorgaenge.first['status'],
        'approved',
        reason:
            'Der Status muss "approved" sein - sonst bleibt der Eintrag in '
            'der Warteschlange.',
      );
    });

    test('das Ablehnen geht an den Server', () async {
      await dienst.rejectPhoto(1, 'admin-1');

      final schreibvorgaenge = server.schreibvorgaenge
          .where((s) => s['tabelle'] == 'photo_moderation')
          .toList();
      expect(schreibvorgaenge, isNotEmpty);
      expect(schreibvorgaenge.first['status'], 'rejected');
    });
  });
}
