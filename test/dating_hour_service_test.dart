// Tests für die reine Zeit-Logik des DatingHourService (Serverzeit-basiert,
// ohne Supabase). Die RPC-Pfade sind serverseitig getestet (Migrationen).
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/dating_hour_models.dart';
import 'package:thestia/services/dating_hour_service.dart';
import 'package:thestia/services/server_time_service.dart';

void main() {
  final serverTime = ServerTimeService.instance;
  final service = DatingHourService();

  setUp(serverTime.resetForTesting);
  tearDown(serverTime.resetForTesting);

  group('getServerTime', () {
    test('liefert die verifizierte Serverzeit (mit Offset)', () {
      serverTime.setOffsetForTesting(const Duration(hours: 1).inMilliseconds);
      final server = service.getServerTime();
      final local = DateTime.now();
      final diff = server.difference(local);
      // Toleranz: Ausführungszeit zwischen den beiden now()-Aufrufen.
      expect((diff - const Duration(hours: 1)).inSeconds.abs(), lessThan(5));
    });
  });

  group('Session-Zeitlogik', () {
    DatingHourSession session({int expiresInSeconds = 300}) {
      final base = DateTime.now();
      return DatingHourSession(
        id: 's1',
        eventId: 'e1',
        userA: 'user-a',
        userB: 'user-b',
        startedAt: base,
        expiresAt: base.add(Duration(seconds: expiresInSeconds)),
      );
    }

    test('isSessionExpired: false, solange Serverzeit vor expiresAt', () {
      expect(service.isSessionExpired(session()), isFalse);
    });

    test('isSessionExpired: true, wenn Serverzeit nach expiresAt liegt', () {
      serverTime.setOffsetForTesting(const Duration(minutes: 10).inMilliseconds);
      expect(service.isSessionExpired(session()), isTrue);
    });

    test('isSessionExpired ignoriert eine verstellte Geräte-Uhr', () {
      // Geräte-Uhr zeigt 10 Minuten NACH expiresAt, Serverzeit ist korrekt.
      serverTime.setOffsetForTesting(const Duration(minutes: -10).inMilliseconds);
      expect(service.isSessionExpired(session(expiresInSeconds: 300)), isFalse);
    });

    test('remainingSeconds: volles 5-Minuten-Fenster (clamp bei 300)', () {
      // Ablaufzeit 5 min + 10 s in der Zukunft → clamp auf 300.
      expect(service.remainingSeconds(session(expiresInSeconds: 310)), 300);
    });

    test('remainingSeconds: nie negativ (clamp 0..300)', () {
      serverTime.setOffsetForTesting(const Duration(minutes: 10).inMilliseconds);
      expect(service.remainingSeconds(session()), 0);
    });

    test('isMutualMatch/bothDecided-Logik', () {
      final s = session();
      expect(s.isMutualMatch, isFalse);
      expect(s.bothDecided, isFalse);

      final decided = s.copyWith(
        userADecision: 'accept',
        userBDecision: 'accept',
      );
      expect(decided.bothDecided, isTrue);
      expect(decided.isMutualMatch, isTrue);
    });
  });

  group('Event-Zeitlogik', () {
    DatingHourEvent event({DateTime? startsAt, DateTime? endsAt, String status = 'scheduled'}) {
      final now = DateTime.now();
      return DatingHourEvent(
        id: 'e1',
        eventDate: now,
        dayOfWeek: 6,
        startHour: 20,
        startMinute: 0,
        endHour: 21,
        endMinute: 0,
        startsAt: startsAt ?? now.subtract(const Duration(minutes: 5)),
        endsAt: endsAt ?? now.add(const Duration(minutes: 5)),
        status: status,
      );
    }

    test('isRunningNow: true im laufenden Fenster (Serverzeit)', () {
      expect(event().isRunningNow, isTrue);
      expect(event().canJoin, isTrue);
    });

    test('isEnded/canJoin: Serverzeit nach Ende → beendet, kein Beitritt', () {
      serverTime.setOffsetForTesting(const Duration(minutes: 10).inMilliseconds);
      final e = event(endsAt: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(e.isEnded, isTrue);
      expect(e.canJoin, isFalse);
    });

    test('canJoin berücksichtigt eine verstellte Geräte-Uhr nicht', () {
      // Geräte-Uhr ist 10 Minuten VOR (Serverzeit = Gerätezeit - 10 min).
      // Das Event endete vor 5 Minuten in ECHTER Zeit.
      serverTime.setOffsetForTesting(const Duration(minutes: -10).inMilliseconds);
      final realNow = DateTime.now().subtract(const Duration(minutes: 10));
      final e = event(endsAt: realNow.subtract(const Duration(minutes: 5)));
      expect(e.canJoin, isFalse);
    });
  });
}