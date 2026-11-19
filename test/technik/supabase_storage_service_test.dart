// Der Bild-/Audio-Speicher (Supabase Storage) - weitgehend ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/supabase_storage_service.dart 114 offene Zeilen bei 142
// Zeilen gesamt. Hier liegen die Profilbilder, die Vorstellungs-Audios
// und das Verifizierungs-Video - und die Zusage, dass der Server die
// Bilder NICHT im Klartext sieht.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Avatar wird verschluesselt hochgeladen (der Ref traegt den
//     Schluessel),
//   * die weiteren Bilder, das Audio und das Video landen an ihrem Ort,
//   * das Video landet verschluesselt (.enc),
//   * ohne Anmeldung geht gar nichts,
//   * ein Bild laesst sich wieder laden.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/supabase_storage_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  /// Der Ersatz-Server (der Storage liegt dort).
  late FakeSupabaseServer server;

  /// Der Dienst.
  late SupabaseStorageService storage;

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
    storage = SupabaseStorageService(supabase.Supabase.instance.client);
  });

  setUp(() async {
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    server.pfade.clear();
  });

  /// Ein winziges Bild.
  final bild = <int>[0x89, 0x50, 0x4E, 0x47];

  group('Der Speicher', () {
    test('das Avatar wird verschluesselt hochgeladen', () async {
      final ref = await storage.uploadAvatar(bild);

      // Der Ref besteht aus Pfad, Schluessel und IV.
      final teile = ref.split('|');
      expect(
        teile,
        hasLength(3),
        reason: 'Der Ref muss den Schluessel tragen.',
      );
      expect(teile[0], 'ich/avatar.jpg');
      expect(
        teile[1],
        isNotEmpty,
        reason: 'Ohne Schluessel kein Entschlüsseln.',
      );
      expect(teile[2], isNotEmpty);
      // Und der Pfad ging an den Server.
      expect(
        server.pfade.any((p) => p.contains('ich/avatar.jpg')),
        isTrue,
        reason: 'Der Upload muss beim Server ankommen.',
      );
    });

    test('die weiteren Bilder landen an ihrem Platz', () async {
      final ref = await storage.uploadPhoto(bild, index: 0);

      expect(ref.split('|').first, 'ich/photos/1.jpg');
      final ref2 = await storage.uploadPhoto(bild, index: 2);
      expect(ref2.split('|').first, 'ich/photos/3.jpg');
    });

    test('das Einspruchsbild landet im Pruef-Ordner', () async {
      final pfad = await storage.uploadAppealImage(bild);

      expect(
        pfad,
        matches(RegExp(r'^ich/appeals/\d+\.jpg$')),
        reason:
            'Ein abgelehntes Bild gehoert in den geschuetzten Pruef-Ordner '
            '- es darf NICHT als Avatar hochgeladen werden.',
      );
    });

    test('das Vorstellungs-Audio landet an seinem Platz', () async {
      final pfad = await storage.uploadIntroAudio(<int>[1, 2, 3]);

      expect(pfad, 'ich/intro.m4a');
      expect(server.pfade.any((p) => p.contains('intro.m4a')), isTrue);
    });

    test('das Verifizierungs-Video landet verschluesselt', () async {
      final pfad = await storage.uploadVerificationVideo(<int>[1, 2, 3]);

      expect(
        pfad,
        'ich/video.mp4.enc',
        reason:
            'Das Video liegt verschluesselt - ein unverschluesselter '
            'Altbestand darf nicht als vollstaendig gelten.',
      );
    });

    test('ein leeres Video wird abgewiesen', () async {
      expect(
        () => storage.uploadVerificationVideo(const <int>[]),
        throwsA(isA<Object>()),
        reason: 'Ein leeres Video ist ein Fehler - nicht "erfolgreich".',
      );
    });

    test('ohne Anmeldung geht gar nichts', () async {
      await supabase.Supabase.instance.client.auth.signOut();

      expect(() => storage.uploadAvatar(bild), throwsA(isA<Object>()));
      expect(() => storage.uploadPhoto(bild, index: 0), throwsA(isA<Object>()));
      expect(
        () => storage.uploadVerificationVideo(<int>[1]),
        throwsA(isA<Object>()),
      );
      expect(() => storage.deleteAvatar(), throwsA(isA<Object>()));
    });

    test('ein Bild laesst sich wieder laden', () async {
      final bytes = await storage.downloadAppealImage('ich/appeals/1.jpg');

      expect(bytes, isNotNull, reason: 'Das Bild muss wieder da sein.');
      expect(bytes, isA<Uint8List>());
      expect(bytes!.isNotEmpty, isTrue);
    });

    test('ein geladetes Bild wird zwischengespeichert', () async {
      // Der Avatar-Cache ist statisch - der zweite Aufruf darf den
      // Server nicht mehr fragen.
      final pfad = 'ich/avatar-cache-test.jpg';
      final erste = await storage.loadAvatarBytes(pfad);
      expect(erste, isNotNull);

      final pfadeVorher = server.pfade.length;
      final zweite = await storage.loadAvatarBytes(pfad);

      expect(zweite, isNotNull);
      expect(
        server.pfade.length,
        pfadeVorher,
        reason:
            'Der zweite Aufruf muss aus dem Speicher kommen - sonst laedt '
            'der Bildschirm das Bild bei jedem Frame neu.',
      );
    });

    test('das Loeschen geht ohne Absturz', () async {
      await storage.deleteOwnObject('ich/appeals/1.jpg');
      await storage.deleteAvatar();
      await storage.deleteIntroAudio();
      await storage.deleteVerificationVideo();

      expect(
        server.pfade.any((p) => p.contains('/storage/v1/')),
        isTrue,
        reason: 'Das Loeschen muss an den Storage gehen.',
      );
    });
  });
}
