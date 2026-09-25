import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';

UserProfile _partner() => UserProfile(
      id: 'u1',
      name: 'Alex',
      birthDate: DateTime(2000, 1, 1),
      bio: '',
    );

/// Server-Form für UserProfile.fromPublicView (user_id + age statt
/// id + birthDate).
Map<String, dynamic> _profileJson() => {
      'profile': {
        'user_id': 'u1',
        'name': 'Alex',
        'age': 26,
      },
    };

void main() {
  group('MatchWithState', () {
    test('quizPassed ab Level 2', () {
      MatchWithState m({required int level, String via = 'find_match'}) =>
          MatchWithState(
            matchId: 1,
            partner: _partner(),
            unlockLevel: level,
            failedAttempts: 0,
            createdVia: via,
          );
      expect(m(level: 0).quizPassed, isFalse);
      expect(m(level: 1).quizPassed, isFalse);
      expect(m(level: 2).quizPassed, isTrue);
      expect(m(level: 3).quizPassed, isTrue);
    });

    test('quizGated nur für find_match ohne bestandene Prüfung', () {
      MatchWithState m({required int level, required String via}) =>
          MatchWithState(
            matchId: 1,
            partner: _partner(),
            unlockLevel: level,
            failedAttempts: 0,
            createdVia: via,
          );
      expect(m(level: 0, via: 'find_match').quizGated, isTrue);
      expect(m(level: 2, via: 'find_match').quizGated, isFalse);
      expect(m(level: 0, via: 'swipe').quizGated, isFalse);
      expect(m(level: 0, via: 'transit').quizGated, isFalse);
    });

    test('cooled nur bei Status cooled', () {
      MatchWithState m(String status) => MatchWithState(
            matchId: 1,
            partner: _partner(),
            unlockLevel: 0,
            failedAttempts: 0,
            status: status,
          );
      expect(m('cooled').cooled, isTrue);
      expect(m('active').cooled, isFalse);
      expect(m('ended').cooled, isFalse);
    });

    test('fromJson: Defaults + Distanz als Geschwister-Feld', () {
      final json = _profileJson()
        ..addAll({'matchId': 9, 'distanceKm': 12});
      final m = MatchWithState.fromJson(json);
      expect(m.matchId, 9);
      expect(m.unlockLevel, 0);
      expect(m.failedAttempts, 0);
      expect(m.createdVia, 'swipe');
      expect(m.status, 'active');
      expect(m.partner.distanceKm, 12);
      expect(m.quizGated, isFalse);
    });

    test('fromJson: ungültige Datums-Strings werfen nicht', () {
      final json = _profileJson()
        ..addAll({
          'matchId': 9,
          'createdAt': 'kein-datum',
          'passedAt': null,
          // Hinweis: DateTime.tryParse normalisiert Überläufe
          // ('2026-13-45' -> 2027-02-14), nur echte Non-Dates geben null.
          'lastAttemptAt': '',
        });
      final m = MatchWithState.fromJson(json);
      expect(m.createdAt, isNull);
      expect(m.passedAt, isNull);
      expect(m.lastAttemptAt, isNull);
    });
  });

  group('ReceivedLike', () {
    test('fromJson übernimmt likeId und Distanz', () {
      final json = _profileJson()
        ..addAll({
          'likeId': 5,
          'distanceKm': 7,
          'createdAt': '2026-01-02T03:04:05.000Z',
        });
      final like = ReceivedLike.fromJson(json);
      expect(like.likeId, 5);
      expect(like.profile.distanceKm, 7);
      expect(like.createdAt, isNotNull);
    });
  });

  group('QuizState', () {
    test('passed/roundInProgress/quizGated', () {
      const base = QuizState(
        matchId: 1,
        partnerId: 'p',
        unlockLevel: 0,
        failedAttempts: 0,
      );
      expect(base.passed, isFalse);
      expect(base.roundInProgress, isFalse);
      expect(base.quizGated, isFalse); // swipe-Default

      const gated = QuizState(
        matchId: 1,
        partnerId: 'p',
        unlockLevel: 1,
        failedAttempts: 1,
        createdVia: 'find_match',
        currentQuestionId: 'q1',
      );
      expect(gated.passed, isFalse);
      expect(gated.roundInProgress, isTrue);
      expect(gated.quizGated, isTrue);

      const done = QuizState(
        matchId: 1,
        partnerId: 'p',
        unlockLevel: 2,
        failedAttempts: 0,
        createdVia: 'find_match',
      );
      expect(done.passed, isTrue);
      expect(done.quizGated, isFalse);
    });

    test('fromJson: Defaults und Cooldown', () {
      final s = QuizState.fromJson({'matchId': 3});
      expect(s.partnerId, '');
      expect(s.createdVia, 'swipe');
      expect(s.unlockLevel, 0);
      expect(s.cooldownRemainingSeconds, 0);
      expect(s.answeredCurrent, isFalse);
      expect(s.roundInProgress, isFalse);
    });
  });

  group('QuizQuestion', () {
    test('fromJson parst Frage und Optionen', () {
      final q = QuizQuestion.fromJson({
        'questionId': 'q7',
        'prompt': 'Lieblingsfarbe?',
        'options': ['Rot', 'Blau'],
      });
      expect(q.id, 'q7');
      expect(q.prompt, 'Lieblingsfarbe?');
      expect(q.options, ['Rot', 'Blau']);
    });

    test('Cooldown-Sentinel bleibt erkennbar', () {
      const q = QuizQuestion(
        id: '',
        prompt: '__cooldown__',
        options: ['300', ''],
      );
      expect(q.prompt, '__cooldown__');
      expect(int.tryParse(q.options.first), isNotNull);
    });
  });

  group('QuizAnswerResult', () {
    test('round_closed setzt nur roundClosed', () {
      final r = QuizAnswerResult.fromJson({'error': 'round_closed'});
      expect(r.roundClosed, isTrue);
      expect(r.correct, isFalse);
      expect(r.waitingForPartner, isFalse);
      expect(r.cooldownActive, isFalse);
    });

    test('already_answered bedeutet Warten auf Partner', () {
      final r = QuizAnswerResult.fromJson({'error': 'already_answered'});
      expect(r.waitingForPartner, isTrue);
      expect(r.correct, isTrue);
      expect(r.passed, isFalse);
    });

    test('cooldown übernimmt Restsekunden', () {
      final r = QuizAnswerResult.fromJson({
        'error': 'cooldown',
        'cooldownRemainingSeconds': 120,
        'nextAttemptAt': '2026-01-01T00:02:00.000Z',
      });
      expect(r.cooldownActive, isTrue);
      expect(r.cooldownRemainingSeconds, 120);
      expect(r.nextAttemptAt, isNotNull);
    });

    test('normales Ergebnis übernimmt alle Felder', () {
      final r = QuizAnswerResult.fromJson({
        'correct': true,
        'passed': true,
        'waitingForPartner': false,
        'unlockLevel': 2,
        'failedAttempts': 1,
      });
      expect(r.correct, isTrue);
      expect(r.passed, isTrue);
      expect(r.unlockLevel, 2);
      expect(r.failedAttempts, 1);
      expect(r.cooldownActive, isFalse);
    });
  });
}
