// Fuzzing der Eingabeparser der App.
//
// WOFÜR (22.11.2026, Betreiber: "Mit fuzzing könntest du in der App
// nach Sicherheitslücken suchen"): Die App bekommt Daten von außen.
// Wer sie bessässigt, darf sie nicht zum Absturz bringen - das wäre
// ein Denial of Service über die Schnittstelle (und in einer Dating-App
// ein Angriff auf das Gerät des Opfers).
//
// DER ORACLE: Kein Parser darf werfen. Was er zurückgibt, ist zweitrangig -
// entscheidend ist, dass die App weiterläuft.
//
// DIE ZIELE:
//   * die öffentlichen Modelle (der Server liefert sie - und der Server
//     liefert sie für das Profil eines FREMDEN),
//   * die Chat-Nachricht (aus der lokalen Historie),
//   * die Dating-Hour-Modelle (aus dem Server),
//   * die Quiz-Modelle (aus dem Server).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/models/profile/user_profile.dart';

import 'fuzz_harness.dart';

/// Die Seeds der Läufe.
///
/// WARUM MEHRERE: Der Seed bestimmt, welche Mutationen vorkommen. Mit
/// einem einzigen Seed findet man oft nur eine der Fehlerklassen - mit
/// mehreren Seeds wird jede Klasse getroffen.
const _seeds = <int>[1, 7, 42, 1337, 20261122, 99991];

/// Die realistischen Seeds (der Korpus).
///
/// DAS SIND DIE NORMALEN FALLE: Sie kommen aus dem Server, also sieht
/// der Fuzzer zuerst, wie es normalerweise aussieht - und mutiert dann.
final _profilSeed = <String, Object?>{
  'user_id': 'partner-1',
  'name': 'Mira',
  'bio': 'Liest gern',
  'interests': <String>['Musik', 'Klettern'],
  'photos': <String>['a/b/c.jpg', 'd/e/f.jpg'],
  'gender': 'female',
  'personality_type': 'INTJ',
  'age': 28,
  'mood': 'happy',
  'music_liked': <String>['Rock'],
  'music_disliked': <String>['Jazz'],
  'favorite_song': 'Song',
  'favorite_band': 'Band',
  'smoking': 'never',
  'alcohol': 'occasionally',
  'drugs': 'never',
  'distance_km': 12.5,
  'intro_text': 'Hallo',
  'birthday_style': 'midnight',
  'birthday_today': false,
  'is_verified': true,
  'verification_state': 'verified',
  'created_at': '2026-01-01T10:00:00Z',
};

final _funkeSeed = <String, Object?>{
  'matchId': 77,
  'partnerId': 'partner-1',
  'profile': _profilSeed,
  'unlockLevel': 0,
  'failedAttempts': 0,
  'createdVia': 'swipe',
  'status': 'active',
  'createdAt': '2026-01-01T10:00:00Z',
  'resparkedAt': null,
  'passedAt': null,
  'lastAttemptAt': null,
  'kind': 'spark',
  'autoMatch': false,
  'messageCount': 3,
  'messageCountMine': 1,
  'distanceKm': 12.5,
};

final _nachrichtSeed = <String, Object?>{
  'id': 'm1',
  'senderId': 'partner-1',
  'receiverId': 'ich',
  'text': 'Hallo',
  'type': 'text',
  'mediaUrl': null,
  'durationSeconds': 0,
  'timestamp': 1767261600000,
  'viewOnce': false,
  'viewed': false,
};

final _sessionSeed = <String, Object?>{
  'id': 's1',
  'event_id': 'e1',
  'user_a': 'ich',
  'user_b': 'partner-1',
  'started_at': '2026-01-01T10:00:00Z',
  'expires_at': '2026-01-01T11:00:00Z',
  'ended_at': null,
  'user_a_decision': null,
  'user_b_decision': null,
  'is_match': false,
  'auto_match_at': null,
  'auto_matched': false,
  'ended_by': null,
};

final _quizSeed = <String, Object?>{
  'questionId': 'q1',
  'options': <String>['a', 'b', 'c'],
};

void main() {
  group('Das oeffentliche Profil ueberlebt jede Eingabe', () {
    for (final seed in _seeds) {
      test('fromPublicView (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_profilSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => UserProfile.fromPublicView(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'UserProfile.fromPublicView',
          );
        }
      });

      test('fromJson (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_profilSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => UserProfile.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'UserProfile.fromJson',
          );
        }
      });

      test('fromJson mit voellig fremden Feldern (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.zufaelligesObjekt(felder: 8);
          expectRobust(
            (json) => UserProfile.fromJson(json),
            eingabe,
            seed: seed,
            name: 'UserProfile.fromJson (fremde Felder)',
          );
          expectRobust(
            (json) => UserProfile.fromPublicView(json),
            eingabe,
            seed: seed,
            name: 'UserProfile.fromPublicView (fremde Felder)',
          );
        }
      });
    }
  });

  group('Die Funkenliste ueberlebt jede Eingabe', () {
    for (final seed in _seeds) {
      test('MatchWithState (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_funkeSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => MatchWithState.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'MatchWithState.fromJson',
          );
        }
      });

      test('ReceivedLike (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(<String, Object?>{
            'likeId': 5,
            'profile': _profilSeed,
            'createdAt': '2026-01-01T10:00:00Z',
            'distanceKm': 5.0,
          }, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => ReceivedLike.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'ReceivedLike.fromJson',
          );
        }
      });
    }
  });

  group('Die Chat-Nachricht ueberlebt jede Eingabe', () {
    for (final seed in _seeds) {
      test('Message (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_nachrichtSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => Message.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'Message.fromJson',
          );
        }
      });
    }
  });

  group('Die Dating-Hour ueberlebt jede Eingabe', () {
    for (final seed in _seeds) {
      test('DatingHourSession (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_sessionSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => DatingHourSession.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'DatingHourSession.fromJson',
          );
        }
      });
    }
  });

  group('Die Quiz-Fragen ueberleben jede Eingabe', () {
    for (final seed in _seeds) {
      test('QuizQuestion (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_quizSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          expectRobust(
            (json) => QuizQuestion.fromJson(json),
            Map<String, dynamic>.from(eingabe),
            seed: seed,
            name: 'QuizQuestion.fromJson',
          );
        }
      });
    }
  });

  group('Das Fuzzing-Werkzeug selbst', () {
    test('es erzeugt ueberhaupt Verschiedenes', () {
      final fuzz = Fuzz(42);
      final ergebnisse = <String>{};
      for (var i = 0; i < 50; i++) {
        ergebnisse.add(fuzz.korpusVariante(_profilSeed, 3).toString());
      }
      expect(
        ergebnisse.length,
        greaterThan(10),
        reason: 'Wenn das Werkzeug immer dasselbe erzeugt, prueft es nichts.',
      );
    });

    test('die Zufallszahlen sind reproduzierbar', () {
      final a = Fuzz(7).random.nextInt(1000000);
      final b = Fuzz(7).random.nextInt(1000000);
      expect(a, b, reason: 'Ein Fund muss mit dem Seed wiederholbar sein.');
    });

    test('der Bericht nennt den Seed und die Eingabe', () {
      final text = fundBeschreibung(42, <String, Object?>{'a': 1});
      expect(text, contains('42'));
      expect(text, contains('a'));
    });

    test('die Laeufe sind nicht alle identisch', () {
      // Ohne das ist der Fuzzer blind (er prüft nur einen Fall).
      final seeds = <int>{};
      for (var s = 0; s < 20; s++) {
        seeds.add(Fuzz(s).korpusVariante(_profilSeed, 2).toString().hashCode);
      }
      expect(seeds.length, greaterThan(15));
      expect(max(0, min(0, 0)), 0); // min/max sind hier nur Importe
    });
  });
}
