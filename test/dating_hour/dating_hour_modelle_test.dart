// Die Modelle der Dating Hour.
//
// ANLASS (19.11.2026): Bei der Coverage-Messung war
// `lib/models/dating_hour/dating_hour_models.dart` nur zu 54 % abgedeckt. Gerade
// die Zeitlogik (5-Minuten-Fenster, automatischer Funke) entscheidet,
// was der Nutzer im Chat sieht - sie gehoert geprueft.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Lesen einer Supabase-Zeile (inkl. der Migration-177-Felder),
//   * die Entscheidungen der beiden Seiten,
//   * der Timer rechnet mit der SERVERZEIT (eine verstellte Geräte-Uhr
//     darf das Fenster nicht verschieben),
//   * die Kopien (copyWith) aendern nur das, was man ihnen gibt.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/services/server/server_time_service.dart';

/// Die Session im frischen Zustand (5 Minuten offen, nichts entschieden).
DatingHourSession _session({
  DateTime? startedAt,
  DateTime? expiresAt,
  DateTime? autoMatchAt,
  DateTime? endedAt,
  String? userADecision,
  String? userBDecision,
  bool isMatch = false,
  bool autoMatched = false,
  String? endedBy,
}) {
  final start = startedAt ?? DateTime.now();
  return DatingHourSession(
    id: 'session-1',
    eventId: 'event-1',
    userA: 'a',
    userB: 'b',
    startedAt: start,
    expiresAt: expiresAt ?? start.add(const Duration(minutes: 5)),
    autoMatchAt: autoMatchAt,
    endedAt: endedAt,
    userADecision: userADecision,
    userBDecision: userBDecision,
    isMatch: isMatch,
    autoMatched: autoMatched,
    endedBy: endedBy,
  );
}

void main() {
  // Die Serverzeit ist ein Singleton - nach jedem Test zuruecksetzen.
  tearDown(() => ServerTimeService.instance.resetForTesting());

  group('Die Session aus der Serverzeile', () {
    test('liest alle Felder (inkl. Migration 177)', () {
      final session = DatingHourSession.fromJson(<String, dynamic>{
        'id': 'session-9',
        'event_id': 'event-3',
        'user_a': 'nutzer-a',
        'user_b': 'nutzer-b',
        'started_at': '2026-11-18T20:00:00.000Z',
        'expires_at': '2026-11-18T20:05:00.000Z',
        'ended_at': '2026-11-18T20:03:00.000Z',
        'user_a_decision': 'accept',
        'user_b_decision': 'reject',
        'is_match': true,
        'auto_match_at': '2026-11-18T20:06:00.000Z',
        'auto_matched': true,
        'ended_by': 'nutzer-b',
      });

      expect(session.id, 'session-9');
      expect(session.eventId, 'event-3');
      expect(session.userA, 'nutzer-a');
      expect(session.userB, 'nutzer-b');
      expect(session.startedAt.toUtc(), DateTime.utc(2026, 11, 18, 20));
      expect(session.expiresAt.toUtc(), DateTime.utc(2026, 11, 18, 20, 5));
      expect(session.endedAt, isNotNull);
      expect(session.userADecision, 'accept');
      expect(session.userBDecision, 'reject');
      expect(session.isMatch, isTrue);
      expect(session.autoMatchAt, isNotNull);
      expect(session.autoMatched, isTrue);
      expect(session.endedBy, 'nutzer-b');
    });

    test('fehlende optionale Felder bekommen die Vorgabe', () {
      final session = DatingHourSession.fromJson(<String, dynamic>{
        'id': 'session-9',
        'event_id': 'event-3',
        'user_a': 'a',
        'user_b': 'b',
        'started_at': '2026-11-18T20:00:00.000Z',
        'expires_at': '2026-11-18T20:05:00.000Z',
      });

      expect(session.endedAt, isNull);
      expect(session.autoMatchAt, isNull);
      expect(session.userADecision, isNull);
      expect(session.userBDecision, isNull);
      expect(session.isMatch, isFalse);
      expect(session.autoMatched, isFalse);
      expect(session.endedBy, isNull);
    });
  });

  group('Die Beteiligten und ihre Entscheidungen', () {
    test('jeder sieht den anderen als Partner', () {
      final session = _session();
      expect(session.isParticipantA('a'), isTrue);
      expect(session.isParticipantA('b'), isFalse);
      expect(session.getPeerId('a'), 'b');
      expect(session.getPeerId('b'), 'a');
    });

    test('jeder sieht seine eigene Entscheidung', () {
      final session = _session(
        userADecision: 'accept',
        userBDecision: 'reject',
      );
      expect(session.getDecisionFor('a'), 'accept');
      expect(session.getDecisionFor('b'), 'reject');
    });

    test('beide muessen annehmen, damit es ein Match ist', () {
      expect(
        _session(
          userADecision: 'accept',
          userBDecision: 'accept',
        ).isMutualMatch,
        isTrue,
      );
      expect(
        _session(
          userADecision: 'accept',
          userBDecision: 'reject',
        ).isMutualMatch,
        isFalse,
      );
      expect(_session(userADecision: 'accept').isMutualMatch, isFalse);
    });

    test('beide muessen entschieden haben', () {
      expect(_session(userADecision: 'accept').bothDecided, isFalse);
      expect(
        _session(userADecision: 'accept', userBDecision: 'reject').bothDecided,
        isTrue,
      );
    });

    test('eine beendete Sitzung ohne Match ist eine Ablehnung', () {
      final beendet = _session(endedAt: DateTime.now());
      expect(beendet.isCompleted, isTrue);
      expect(beendet.isRejected, isTrue);
      expect(beendet.copyWith(isMatch: true).isRejected, isFalse);
      // Eine laufende Sitzung ist keine Ablehnung.
      expect(_session().isCompleted, isFalse);
      expect(_session().isRejected, isFalse);
    });

    test('wer hat das Gespraech vorzeitig beendet', () {
      final session = _session(endedBy: 'b');
      expect(session.wasEndedEarly, isTrue);
      expect(session.wasEndedBy('b'), isTrue);
      expect(session.wasEndedBy('a'), isFalse);
      expect(_session().wasEndedEarly, isFalse);
      expect(_session().wasEndedBy('b'), isFalse);
    });
  });

  group('Der Timer rechnet mit der Serverzeit', () {
    test('die verbleibenden Sekunden sinken mit der Serverzeit', () {
      final start = DateTime.now();
      final session = _session(
        startedAt: start,
        expiresAt: start.add(const Duration(minutes: 5)),
      );
      expect(session.remainingSeconds, inInclusiveRange(295, 300));

      // Zwei Minuten spaeter (Offset) sind noch drei Minuten uebrig.
      ServerTimeService.instance.setOffsetForTesting(2 * 60 * 1000);
      expect(session.remainingSeconds, inInclusiveRange(175, 180));
    });

    test('nach dem Fenster sind 0 Sekunden (nicht negativ)', () {
      final start = DateTime.now();
      final session = _session(
        startedAt: start,
        expiresAt: start.add(const Duration(minutes: 5)),
      );
      ServerTimeService.instance.setOffsetForTesting(10 * 60 * 1000);
      expect(session.remainingSeconds, 0);
      expect(session.isExpired, isTrue);
    });

    test('vor dem Fenster ist die Sitzung nicht abgelaufen', () {
      final start = DateTime.now();
      final session = _session(
        startedAt: start,
        expiresAt: start.add(const Duration(minutes: 5)),
      );
      expect(session.isExpired, isFalse);
    });

    test('ohne zweiten Termin gibt es keinen automatischen Funken', () {
      expect(_session().autoMatchSecondsLeft, 0);
    });

    test('der automatische Funke zaehlt die Sekunden herunter', () {
      final start = DateTime.now();
      final session = _session(
        startedAt: start,
        expiresAt: start.add(const Duration(minutes: 5)),
        autoMatchAt: start.add(const Duration(minutes: 7)),
      );
      expect(session.autoMatchSecondsLeft, inInclusiveRange(415, 420));

      ServerTimeService.instance.setOffsetForTesting(60 * 1000);
      expect(session.autoMatchSecondsLeft, inInclusiveRange(355, 360));
    });

    test('die Entscheidungsphase: Zeit um, automatischer Funke noch nicht', () {
      final start = DateTime.now();
      final session = _session(
        startedAt: start,
        expiresAt: start.add(const Duration(minutes: 5)),
        autoMatchAt: start.add(const Duration(minutes: 8)),
      );
      // Noch in der ersten Phase.
      expect(session.isDecisionPhase, isFalse);

      // Sechs Minuten spaeter: das Fenster ist um, der Funke steht noch
      // aus - genau die Phase, in der der Chat zur Ruhe auffordert.
      ServerTimeService.instance.setOffsetForTesting(6 * 60 * 1000);
      expect(session.isDecisionPhase, isTrue);
      expect(session.autoMatchSecondsLeft, greaterThan(0));

      // Und wenn der Funke da ist, endet die Phase.
      ServerTimeService.instance.setOffsetForTesting(9 * 60 * 1000);
      expect(session.isDecisionPhase, isFalse);
    });
  });

  group('Die Kopien aendern nur, was man ihnen gibt', () {
    test('die Session', () {
      final session = _session(userADecision: 'accept');
      final kopie = session.copyWith(userBDecision: 'accept');
      expect(kopie.userBDecision, 'accept');
      expect(kopie.userADecision, 'accept');
      expect(kopie.id, session.id);
      expect(kopie.expiresAt, session.expiresAt);
    });

    test('die Praeferenzen', () {
      const prefs = DatingHourPreferences(
        ageMin: 18,
        ageMax: 30,
        genderPreference: 'all',
        preferredTrait: 'Humor',
        maxDistanceKm: 50,
      );
      final kopie = prefs.copyWith(ageMax: 40);
      expect(kopie.ageMax, 40);
      expect(kopie.ageMin, 18);
      expect(kopie.genderPreference, 'all');
      expect(kopie.preferredTrait, 'Humor');
      expect(kopie.maxDistanceKm, 50);
      expect(kopie.smoking, isNull);
    });
  });

  group('Die Praeferenzen auf dem Weg zum Server', () {
    test('der Freitext wird auf 50 Zeichen gekuerzt und getrimmt', () {
      const prefs = DatingHourPreferences(
        ageMin: 18,
        ageMax: 30,
        genderPreference: 'all',
        preferredTrait: '  Ein wirklich sehr langer Freitext  ',
        maxDistanceKm: 50,
      );
      final json = prefs.toJson();
      expect(json['preferredTrait'], startsWith('Ein wirklich'));
      expect((json['preferredTrait'] as String).length, lessThanOrEqualTo(50));
    });

    test('die Gewohnheiten gehen nur mit, wenn sie gesetzt sind', () {
      const ohne = DatingHourPreferences(
        ageMin: 18,
        ageMax: 30,
        genderPreference: 'all',
        preferredTrait: 'Humor',
        maxDistanceKm: 50,
      );
      expect(ohne.toJson().containsKey('smoking'), isFalse);
      expect(ohne.toJson().containsKey('alcohol'), isFalse);
      expect(ohne.toJson().containsKey('drugs'), isFalse);

      const mit = DatingHourPreferences(
        ageMin: 18,
        ageMax: 30,
        genderPreference: 'all',
        preferredTrait: 'Humor',
        maxDistanceKm: 50,
        smoking: 'no',
      );
      expect(mit.toJson()['smoking'], 'no');
    });

    test('die Runde haelt alle Werte', () {
      const prefs = DatingHourPreferences(
        ageMin: 18,
        ageMax: 30,
        genderPreference: 'all',
        preferredTrait: 'Humor',
        maxDistanceKm: 50,
        smoking: 'no',
        alcohol: 'yes',
        drugs: 'no',
      );
      final zurueck = DatingHourPreferences.fromJson(prefs.toJson());
      expect(zurueck.ageMin, 18);
      expect(zurueck.ageMax, 30);
      expect(zurueck.genderPreference, 'all');
      expect(zurueck.preferredTrait, 'Humor');
      expect(zurueck.maxDistanceKm, 50);
      expect(zurueck.smoking, 'no');
      expect(zurueck.alcohol, 'yes');
      expect(zurueck.drugs, 'no');
    });
  });

  group('Das Event', () {
    test('Start- und Endzeit kommen aus dem Datum und der Uhrzeit', () {
      final event = DatingHourEvent(
        id: 'event-1',
        eventDate: DateTime(2026, 11, 21),
        dayOfWeek: 6,
        startHour: 20,
        startMinute: 0,
        endHour: 21,
        endMinute: 30,
        startsAt: DateTime(2026, 11, 21, 20),
        endsAt: DateTime(2026, 11, 21, 21, 30),
        status: 'scheduled',
      );
      expect(event.startTime, DateTime(2026, 11, 21, 20));
      expect(event.endTime, DateTime(2026, 11, 21, 21, 30));
      // Der Beitritt ist 10 Minuten vor dem Start moeglich.
      expect(event.joinStartTime, DateTime(2026, 11, 21, 19, 50));
    });

    test('es liest eine Supabase-Zeile', () {
      final event = DatingHourEvent.fromJson(<String, dynamic>{
        'id': 'event-2',
        'event_date': '2026-11-21T00:00:00.000Z',
        'day_of_week': 6,
        'start_hour': 20,
        'start_minute': 0,
        'end_hour': 21,
        'end_minute': 0,
        'starts_at': '2026-11-21T20:00:00.000Z',
        'ends_at': '2026-11-21T21:00:00.000Z',
        'status': 'active',
      });
      expect(event.id, 'event-2');
      expect(event.dayOfWeek, 6);
      expect(event.status, 'active');
      expect(event.startTime.hour, 20);
      expect(event.endTime.hour, 21);
    });

    test('vor dem Start laeuft es nicht, danach schon', () {
      final start = DateTime.now();
      final event = DatingHourEvent(
        id: 'event-1',
        eventDate: start,
        dayOfWeek: 6,
        startHour: 20,
        startMinute: 0,
        endHour: 21,
        endMinute: 0,
        startsAt: start.add(const Duration(minutes: 10)),
        endsAt: start.add(const Duration(minutes: 70)),
        status: 'scheduled',
      );
      expect(event.isRunningNow, isFalse);
      expect(event.canJoin, isTrue);
      expect(event.minutesUntilStart, inInclusiveRange(9, 10));
      expect(event.minutesUntilEnd, inInclusiveRange(69, 70));

      // 20 Minuten spaeter laeuft das Event.
      ServerTimeService.instance.setOffsetForTesting(20 * 60 * 1000);
      expect(event.isRunningNow, isTrue);
      expect(event.minutesUntilStart, 0);

      // Nach dem Ende ist es beendet und man kommt nicht mehr rein.
      ServerTimeService.instance.setOffsetForTesting(80 * 60 * 1000);
      expect(event.isRunningNow, isFalse);
      expect(event.isEnded, isTrue);
      expect(event.canJoin, isFalse);
      expect(event.minutesUntilEnd, 0);
    });

    test(
      'ein beendetes Event ist auch dann beendet, wenn die Zeit noch laeuft',
      () {
        final start = DateTime.now();
        final event = DatingHourEvent(
          id: 'event-1',
          eventDate: start,
          dayOfWeek: 6,
          startHour: 20,
          startMinute: 0,
          endHour: 21,
          endMinute: 0,
          startsAt: start.add(const Duration(minutes: 10)),
          endsAt: start.add(const Duration(minutes: 70)),
          status: 'ended',
        );
        expect(event.isEnded, isTrue);
        expect(event.canJoin, isFalse);
      },
    );
  });
}
