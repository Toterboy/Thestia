// Die Fehler- und Sicherheitswege des Bild-Speichers.
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/server/supabase_storage_service.dart 42 offene Zeilen.
// Getestet war der glückliche Weg (hochladen, laden, löschen) - die
// Fehlerwege und vor allem die PRÜFUNG der Download-Adresse waren
// ungetestet.
//
// WARUM DIE PRÜFUNG WICHTIG IST: Die Adresse für das Bild eines
// Match-Partners kommt aus der Edge Function "match-media". Ohne
// Prüfung könnte ein kompromittiertes Backend die App auf einen
// fremden Host schicken. Erlaubt sind deshalb nur HTTPS und die
// eigenen Supabase-Hosts.
//
// WAS HIER GEPRÜFT WIRD:
//   * eine fremde Adresse wird abgewiesen (kein Download),
//   * eine unverschlüsselte Adresse wird abgewiesen,
//   * ein Fehler der Edge Function liefert kein Bild,
//   * ein fehlgeschlagener Download liefert kein Bild,
//   * das Löschen verschluckt einen Serverfehler,
//   * die signierte URL kommt vom Server.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/server/supabase_storage_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late SupabaseStorageService storage;

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
    storage = SupabaseStorageService(supabase.Supabase.instance.client);
  });

  setUp(() async {
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    server.pfade.clear();
    server.funktionsAntworten.clear();
    server.funktionsAufrufe.clear();
    server.fehlerAntworten.clear();
  });

  group('Die signierte URL', () {
    test('kommt vom Server', () async {
      final url = await storage.getSignedAvatarUrl('ich/avatar.jpg');

      expect(url, isNotNull);
      expect(url, contains('avatars/ich/avatar.jpg'));
    });

    test('ein Serverfehler wird als Fehler gemeldet', () async {
      server.fehlerAntworten['/storage/v1/object/sign/'] = (
        status: 500,
        body: '{}',
      );

      // Der Aufrufer entscheidet, was er dem Nutzer zeigt - deshalb
      // wirft dieser Weg (anders als die Partner-Bilder).
      await expectLater(
        storage.getSignedAvatarUrl('ich/avatar.jpg'),
        throwsA(isA<Object>()),
      );
    });

    test('der Einspruchs-Weg liefert null statt zu werfen', () async {
      server.fehlerAntworten['/storage/v1/object/sign/'] = (
        status: 500,
        body: '{}',
      );

      expect(await storage.getSignedUrlFor('ich/appeals/1.jpg'), isNull);
    });
  });

  group('Der Download', () {
    test('ein fehlgeschlagener Download liefert kein Bild', () async {
      server.fehlerAntworten['/storage/v1/object/'] = (status: 500, body: '{}');

      expect(await storage.downloadAppealImage('ich/appeals/1.jpg'), isNull);
    });

    test('ein fehlgeschlagener Avatar liefert kein Bild', () async {
      server.fehlerAntworten['/storage/v1/object/'] = (status: 500, body: '{}');

      expect(
        await storage.loadAvatarBytes('ich/avatar-fehler-test.jpg'),
        isNull,
        reason: 'Ein kaputtes Bild darf keine Ausnahme nach oben geben.',
      );
    });
  });

  group('Das Löschen', () {
    test('ein Serverfehler bringt die App nicht um', () async {
      server.fehlerAntworten['/storage/v1/object/'] = (status: 500, body: '{}');

      // Der Aufruf darf NICHT werfen - das Löschen ist ein
      // Aufräum-Schritt, kein kritischer Schritt.
      await storage.deleteOwnObject('ich/appeals/1.jpg');
    });
  });

  group('Das Partner-Bild', () {
    test('eine fremde Adresse wird abgewiesen', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{
        'url': 'https://fremde-akte.example/bild.jpg',
      };

      expect(
        await storage.loadPartnerAvatarBytes(targetUserId: 'sie'),
        isNull,
        reason:
            'Die App darf nur auf die eigenen Supabase-Hosts folgen - '
            'ein fremder Host könnte die App ausspionieren.',
      );
    });

    test('eine unverschlüsselte Adresse wird abgewiesen', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{
        'url': 'http://example.supabase.co/storage/v1/object/bild.jpg',
      };

      expect(
        await storage.loadPartnerAvatarBytes(targetUserId: 'sie'),
        isNull,
        reason: 'Ohne HTTPS kann das Bild mitgelesen werden.',
      );
    });

    test('ohne Adresse kommt kein Bild', () async {
      server.funktionsAntworten['match-media'] = <String, dynamic>{};

      expect(await storage.loadPartnerAvatarBytes(targetUserId: 'sie'), isNull);
    });

    test('ein Fehler der Edge Function liefert kein Bild', () async {
      server.funktionsAntworten['match-media'] = null;
      server.fehlerAntworten['/functions/v1/match-media'] = (
        status: 500,
        body: '{}',
      );

      expect(await storage.loadPartnerAvatarBytes(targetUserId: 'sie'), isNull);
    });

    test('das Verwerfen des Bildes bringt die App nicht um', () async {
      storage.invalidatePartnerAvatar(targetUserId: 'sie');
      storage.invalidatePartnerAvatar(targetUserId: 'sie', path: 'bild.jpg');
    });
  });

  group('Die Bilder selbst', () {
    test('das heruntergeladene Bild hat Bytes', () async {
      final bytes = await storage.downloadAppealImage('ich/appeals/2.jpg');

      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotNull);
    });
  });
}
