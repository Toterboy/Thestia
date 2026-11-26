// Die Bild-Moderation: die Modelle und ihre Hive-Adapter.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/models/verification/photo_moderation_models.g.dart 68 offene
// Zeilen - die erzeugten Adapter wurden nie benutzt. Das sind die
// Modelle, in denen die gemeldeten Bilder und die Sperren liegen.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein gemeldetes Bild überlebt den Weg in die Box und zurück
//     (inklusive aller Felder - auch der leeren),
//   * die Sperre eines Kontos überlebt denselben Weg,
//   * die Aufzählungen (Typ und Status) kommen unverändert zurück.
//
// DER HINWEIS AUF DEN ENUM-ADAPTERN: In lib/main.dart werden die
// Adapter für die beiden Modelle registriert, die für die
// Aufzählungen (PhotoModerationType/Status) aber nicht. Ohne sie
// scheitert das Schreiben (der Writer kennt den Typ nicht). Der Test
// registriert sie deshalb mit - die nächste Fassung der App soll das
// auch tun (siehe die offenen Punkte).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/verification/photo_moderation_models.dart';

void main() {
  late Directory ordner;
  late Box<PhotoModerationFlag> box;
  late Box<UserModerationRecord> sperren;

  setUpAll(() async {
    Hive.registerAdapter(PhotoModerationFlagAdapter());
    Hive.registerAdapter(UserModerationRecordAdapter());
    Hive.registerAdapter(PhotoModerationTypeAdapter());
    Hive.registerAdapter(PhotoModerationStatusAdapter());
  });

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('thesia_moderation');
    Hive.init(ordner.path);
    box = await Hive.openBox<PhotoModerationFlag>('flags');
    sperren = await Hive.openBox<UserModerationRecord>('sperren');
  });

  tearDown(() async {
    await box.close();
    await sperren.close();
    await Hive.deleteBoxFromDisk('flags');
    await Hive.deleteBoxFromDisk('sperren');
    if (ordner.existsSync()) {
      ordner.deleteSync(recursive: true);
    }
  });

  group('Das gemeldete Bild', () {
    test('kommt unveraendert aus der Box zurueck', () async {
      final gemeldet = PhotoModerationFlag(
        id: 'flag-1',
        userId: 'nutzer-1',
        photoUrl: 'https://example.de/foto.jpg',
        type: PhotoModerationType.faceMismatch,
        status: PhotoModerationStatus.pending,
        createdAt: DateTime.utc(2026, 11, 20, 10, 30),
        resolvedAt: null,
        resolvedBy: null,
        details: null,
      );

      await box.put('flag-1', gemeldet);
      final gelesen = box.get('flag-1');

      expect(gelesen, isNotNull);
      expect(gelesen!.id, 'flag-1');
      expect(gelesen.userId, 'nutzer-1');
      expect(gelesen.photoUrl, 'https://example.de/foto.jpg');
      expect(gelesen.type, PhotoModerationType.faceMismatch);
      expect(gelesen.status, PhotoModerationStatus.pending);
      expect(gelesen.createdAt, DateTime.utc(2026, 11, 20, 10, 30));
      expect(gelesen.resolvedAt, isNull);
      expect(gelesen.resolvedBy, isNull);
      expect(gelesen.details, isNull);
    });

    test('behaelt auch die erledigten Angaben', () async {
      final gemeldet = PhotoModerationFlag(
        id: 'flag-2',
        userId: 'nutzer-2',
        photoUrl: 'https://example.de/foto2.jpg',
        type: PhotoModerationType.nudityContent,
        status: PhotoModerationStatus.approved,
        createdAt: DateTime.utc(2026, 11, 19, 8),
        resolvedAt: DateTime.utc(2026, 11, 19, 9),
        resolvedBy: 'admin-1',
        details: 'Alles in Ordnung',
      );

      await box.put('flag-2', gemeldet);
      final gelesen = box.get('flag-2')!;

      expect(gelesen.type, PhotoModerationType.nudityContent);
      expect(gelesen.status, PhotoModerationStatus.approved);
      expect(gelesen.resolvedAt, DateTime.utc(2026, 11, 19, 9));
      expect(gelesen.resolvedBy, 'admin-1');
      expect(gelesen.details, 'Alles in Ordnung');
    });

    test('jede Art von Meldung kommt zurueck', () async {
      for (final typ in PhotoModerationType.values) {
        await box.put(
          'typ-${typ.name}',
          PhotoModerationFlag(
            id: 'typ-${typ.name}',
            userId: 'nutzer-3',
            photoUrl: 'https://example.de/${typ.name}.jpg',
            type: typ,
            status: PhotoModerationStatus.pending,
            createdAt: DateTime.utc(2026, 11, 18),
          ),
        );
      }
      for (final typ in PhotoModerationType.values) {
        expect(box.get('typ-${typ.name}')!.type, typ);
      }
    });

    test('jeder Status kommt zurueck', () async {
      for (final status in PhotoModerationStatus.values) {
        await box.put(
          'status-${status.name}',
          PhotoModerationFlag(
            id: 'status-${status.name}',
            userId: 'nutzer-4',
            photoUrl: 'https://example.de/s.jpg',
            type: PhotoModerationType.otherViolation,
            status: status,
            createdAt: DateTime.utc(2026, 11, 17),
          ),
        );
      }
      for (final status in PhotoModerationStatus.values) {
        expect(box.get('status-${status.name}')!.status, status);
      }
    });
  });

  group('Die Kontosperre', () {
    test('kommt unveraendert aus der Box zurueck', () async {
      final sperre = UserModerationRecord(
        userId: 'nutzer-5',
        faceMismatchWarnings: 2,
        isBanned: true,
        bannedAt: DateTime.utc(2026, 11, 16, 13),
        banReason: 'Wiederholte Meldungen',
      );

      await sperren.put('nutzer-5', sperre);
      final gelesen = sperren.get('nutzer-5');

      expect(gelesen, isNotNull);
      expect(gelesen!.userId, 'nutzer-5');
      expect(gelesen.faceMismatchWarnings, 2);
      expect(gelesen.isBanned, isTrue);
      expect(gelesen.bannedAt, DateTime.utc(2026, 11, 16, 13));
      expect(gelesen.banReason, 'Wiederholte Meldungen');
    });

    test('eine Sperre laesst sich wieder aufheben', () async {
      await sperren.put(
        'nutzer-6',
        UserModerationRecord(
          userId: 'nutzer-6',
          isBanned: true,
          bannedAt: DateTime.utc(2026, 11, 15),
          banReason: 'Test',
        ),
      );

      // DIE AUFHEBUNG: Ohne Verbannung ist die Sperre unwirksam.
      final geaendert = UserModerationRecord(userId: 'nutzer-6');
      await sperren.put('nutzer-6', geaendert);

      final gelesen = sperren.get('nutzer-6')!;
      expect(gelesen.isBanned, isFalse);
      expect(gelesen.bannedAt, isNull);
      expect(gelesen.banReason, isNull);
      expect(gelesen.faceMismatchWarnings, 0);
    });

    test('copyWith aendert nur die genannten Felder', () async {
      // DIE SEMANTIK: "null" heißt "unverändert lassen" - die Sperre
      // bleibt also stehen, wenn man sie nicht ausdrücklich wegschickt.
      final original = UserModerationRecord(
        userId: 'nutzer-7',
        faceMismatchWarnings: 3,
        isBanned: true,
        bannedAt: DateTime.utc(2026, 11, 14),
        banReason: 'Test',
      );

      final kopie = original.copyWith(faceMismatchWarnings: 4);

      expect(kopie.faceMismatchWarnings, 4);
      expect(kopie.isBanned, isTrue);
      expect(kopie.bannedAt, DateTime.utc(2026, 11, 14));
      expect(kopie.banReason, 'Test');
      expect(kopie.userId, 'nutzer-7');
    });
  });
}
