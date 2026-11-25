// Die Hive-Adapter der Bild-Moderierung.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/models/verification/photo_moderation_models.g.dart 59 offene
// Zeilen (44 %) - die erzeugten Adapter.
//
// WARUM DAS WICHTIG IST: Ein Bild, das gemeldet wurde, muss in der
// lokalen Ablage landen. Ohne die registrierten Adapter bricht das
// Speichern mit "unknown typeId" ab (das war ein gemeldeter Fehler -
// der Build 58 hat die Adapter registriert, der Weg selbst war
// ungetestet).
//
// DER WEG: Die Adapter werden registriert und ein Objekt wird in eine
// Box geschrieben und wieder gelesen - das ist der Weg, den die App
// geht.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine gemeldete Bild-Meldung kommt unveraendert wieder heraus,
//   * ein Vermerk (Sperre/Warnung) kommt unveraendert wieder heraus,
//   * die Aufzaehlungen (der Typ und der Status) kommen richtig heraus.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/verification/photo_moderation_models.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DIE ADAPTER: Ohne sie kennt Hive die Typen nicht.
    Hive.registerAdapter(PhotoModerationTypeAdapter());
    Hive.registerAdapter(PhotoModerationStatusAdapter());
    Hive.registerAdapter(PhotoModerationFlagAdapter());
    Hive.registerAdapter(UserModerationRecordAdapter());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_moderation');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  group('Die gemeldete Bild-Meldung', () {
    test('kommt unveraendert wieder heraus', () async {
      final box = await Hive.openBox<PhotoModerationFlag>('flags');
      final erstellt = DateTime(2026, 11, 25, 12);
      final gemeldet = PhotoModerationFlag(
        id: 'flag-1',
        userId: 'nutzer-1',
        photoUrl: 'https://example.supabase.co/storage/v1/object/public/1.jpg',
        type: PhotoModerationType.nudityContent,
        status: PhotoModerationStatus.pending,
        createdAt: erstellt,
        details: 'Der Konfidenzwert war 0,91',
      );

      await box.put('flag-1', gemeldet);
      // DIE BOX NEU OEFFNEN: Hive liefert den gespeicherten Wert aus dem
      // Speicher - erst beim Wiederoeffnen wird er gelesen (und der
      // Leseweg des Adapters benutzt).
      await box.close();
      final neu = await Hive.openBox<PhotoModerationFlag>('flags');
      final gelesen = neu.get('flag-1');

      expect(gelesen, isNotNull);
      expect(gelesen!.id, 'flag-1');
      expect(gelesen.userId, 'nutzer-1');
      expect(gelesen.photoUrl, contains('storage'));
      expect(gelesen.type, PhotoModerationType.nudityContent);
      expect(gelesen.status, PhotoModerationStatus.pending);
      expect(gelesen.createdAt, erstellt);
      expect(gelesen.details, contains('0,91'));
    });

    test('eine erledigte Meldung kommt erledigt heraus', () async {
      final box = await Hive.openBox<PhotoModerationFlag>('flags');
      await box.put(
        'flag-2',
        PhotoModerationFlag(
          id: 'flag-2',
          userId: 'nutzer-1',
          photoUrl: 'https://example.supabase.co/foto.jpg',
          type: PhotoModerationType.faceMismatch,
          status: PhotoModerationStatus.flagged,
          createdAt: DateTime(2026, 11, 25, 12),
          resolvedAt: DateTime(2026, 11, 25, 13),
          resolvedBy: 'admin',
        ),
      );
      await box.close();
      final neu = await Hive.openBox<PhotoModerationFlag>('flags');

      final gelesen = neu.get('flag-2');

      expect(gelesen!.status, PhotoModerationStatus.flagged);
      expect(gelesen.resolvedBy, 'admin');
      expect(gelesen.resolvedAt, isNotNull);
    });
  });

  group('Der Vermerk (Sperre und Warnungen)', () {
    test('kommt unveraendert wieder heraus', () async {
      final box = await Hive.openBox<UserModerationRecord>('vermerke');
      await box.put(
        'nutzer-1',
        UserModerationRecord(
          userId: 'nutzer-1',
          faceMismatchWarnings: 3,
          isBanned: true,
          bannedAt: DateTime(2026, 11, 25, 14),
          banReason: 'Wiederholte Verstoesse',
        ),
      );
      await box.close();
      final neu = await Hive.openBox<UserModerationRecord>('vermerke');

      final gelesen = neu.get('nutzer-1');

      expect(gelesen, isNotNull);
      expect(gelesen!.userId, 'nutzer-1');
      expect(gelesen.faceMismatchWarnings, 3);
      expect(gelesen.isBanned, isTrue);
      expect(gelesen.banReason, contains('Verstoesse'));
    });

    test('ein Vermerk ohne Sperre kommt ohne Sperre heraus', () async {
      final box = await Hive.openBox<UserModerationRecord>('vermerke');
      await box.put(
        'nutzer-2',
        UserModerationRecord(
          userId: 'nutzer-2',
          faceMismatchWarnings: 1,
          isBanned: false,
        ),
      );
      await box.close();
      final neu = await Hive.openBox<UserModerationRecord>('vermerke');

      final gelesen = neu.get('nutzer-2');

      expect(gelesen!.isBanned, isFalse);
      expect(gelesen.bannedAt, isNull);
    });
  });
}
