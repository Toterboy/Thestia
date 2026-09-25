import 'package:thestia/models/app_settings.dart';
import 'package:thestia/models/match.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile', () {
    test('fromJson/toJson rundt korrekt', () {
      final birthDate = DateTime.now().subtract(const Duration(days: 25 * 365));
      final profile = UserProfile(
        id: '1',
        name: 'Lena',
        birthDate: birthDate,
        bio: 'Hallo',
        interests: ['Musik', 'Reisen'],
        photos: ['a.png'],
        city: 'Berlin',
        distanceKm: 5,
      );
      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);
      expect(restored, equals(profile));
      expect(restored.interests, contains('Musik'));
    });

    test('fromJson mit null-Werten nutzt Defaults', () {
      final json = <String, dynamic>{
        'id': '1',
        'name': 'Test',
        'bio': '',
        'distanceKm': 0.0,
      };
      final restored = UserProfile.fromJson(json);
      expect(restored.id, '1');
      expect(restored.name, 'Test');
      expect(restored.bio, '');
      expect(restored.interests, isEmpty);
      expect(restored.photos, isEmpty);
      expect(restored.city, '');
      expect(restored.distanceKm, 0.0);
      expect(restored.genderPreference, 'all');
      expect(restored.country, 'Deutschland');
    });

    test('copyWith aendert nur gewaehlte Felder', () {
      final birthDate = DateTime(2000, 1, 1);
      final p = UserProfile(
        id: '1',
        name: 'A',
        birthDate: birthDate,
        bio: '',
        interests: ['A', 'B'],
        photos: ['x.png'],
        city: 'Berlin',
        distanceKm: 5.0,
        gender: 'male',
        genderPreference: 'all',
      );
      final updated = p.copyWith(name: 'B');
      expect(updated.name, 'B');
      expect(updated.birthDate, birthDate);
      expect(updated.id, '1');
      expect(updated.bio, '');
      expect(updated.interests, equals(['A', 'B']));
      expect(updated.photos, equals(['x.png']));
      expect(updated.city, 'Berlin');
      expect(updated.distanceKm, 5.0);
      expect(updated.gender, 'male');
      expect(updated.genderPreference, 'all');
    });

    test('copyWith kann zusaetzliche Felder aendern', () {
      final p = UserProfile(
        id: '1',
        name: 'A',
        birthDate: DateTime(2000, 1, 1),
        bio: '',
      );
      final updated = p.copyWith(
        name: 'B',
        city: 'Muenchen',
        distanceKm: 10.0,
        country: 'Österreich',
      );
      expect(updated.name, 'B');
      expect(updated.city, 'Muenchen');
      expect(updated.distanceKm, 10.0);
      expect(updated.country, 'Österreich');
    });

    test('age ist null wenn kein birthDate gesetzt', () {
      const p = UserProfile(id: '1', name: 'A', birthDate: null, bio: '');
      expect(p.age, isNull);
    });

    test('toJson enthaelt alle relevanten Felder', () {
      final profile = UserProfile(
        id: '1',
        name: 'Lena',
        birthDate: DateTime(1995, 6, 15),
        bio: 'Hallo',
        interests: ['Musik'],
        photos: ['a.png'],
        city: 'Berlin',
        distanceKm: 5.0,
        gender: 'female',
        genderPreference: 'male',
        personalityResult: 'Abenteurer',
        personalityType: 'ENFP',
        country: 'Schweiz',
        videoUrl: 'video.mp4',
        audioUrl: 'audio.mp3',
        favoriteSong: 'Song X',
      );
      final json = profile.toJson();
      expect(json['id'], '1');
      expect(json['name'], 'Lena');
      expect(json['bio'], 'Hallo');
      expect(json['interests'], equals(['Musik']));
      expect(json['photos'], equals(['a.png']));
      expect(json['city'], 'Berlin');
      expect(json['distanceKm'], 5.0);
      expect(json['gender'], 'female');
      expect(json['genderPreference'], 'male');
      expect(json['birthDate'], '1995-06-15T00:00:00.000');
      expect(json['personalityResult'], 'Abenteurer');
      expect(json['personalityType'], 'ENFP');
      expect(json['country'], 'Schweiz');
      expect(json['videoUrl'], 'video.mp4');
      expect(json['audioUrl'], 'audio.mp3');
      expect(json['favoriteSong'], 'Song X');
    });

    test('Gleichheit basiert auf id, name, birthDate, bio, city', () {
      final p1 = UserProfile(
        id: '1',
        name: 'A',
        birthDate: DateTime(2000, 1, 1),
        bio: 'Bio',
        city: 'Berlin',
      );
      final p2 = UserProfile(
        id: '1',
        name: 'A',
        birthDate: DateTime(2000, 1, 1),
        bio: 'Bio',
        city: 'Berlin',
      );
      final p3 = UserProfile(
        id: '1',
        name: 'B',
        birthDate: DateTime(2000, 1, 1),
        bio: 'Bio',
        city: 'Berlin',
      );
      expect(p1, equals(p2));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('Match', () {
    test('copyWith aendert nur gewaehlte Felder', () {
      final partner = UserProfile(
        id: 'p1',
        name: 'Mira',
        birthDate: DateTime(1995, 1, 1),
        bio: '',
      );
      final match = Match(
        id: 'match_1',
        partner: partner,
        matchedAt: DateTime(2024, 1, 1),
        photosUnlocked: true,
        unreadCount: 3,
      );
      final updated = match.copyWith(unreadCount: 0);
      expect(updated.id, 'match_1');
      expect(updated.partner, equals(partner));
      expect(updated.matchedAt, DateTime(2024, 1, 1));
      expect(updated.photosUnlocked, isTrue);
      expect(updated.unreadCount, 0);
    });

    test('Gleichheit basiert auf id', () {
      final partner = UserProfile(
        id: 'p1',
        name: 'Mira',
        birthDate: DateTime(1995, 1, 1),
        bio: '',
      );
      final m1 = Match(id: 'm1', partner: partner, matchedAt: DateTime.now());
      final m2 = Match(id: 'm1', partner: partner, matchedAt: DateTime.now());
      final m3 = Match(id: 'm2', partner: partner, matchedAt: DateTime.now());
      expect(m1, equals(m2));
      expect(m1, isNot(equals(m3)));
    });

    test('Default-Werte', () {
      final partner = UserProfile(
        id: 'p1',
        name: 'Mira',
        birthDate: DateTime(1995, 1, 1),
        bio: '',
      );
      final match = Match(
        id: 'm1',
        partner: partner,
        matchedAt: DateTime.now(),
      );
      expect(match.photosUnlocked, isFalse);
      expect(match.unreadCount, 0);
    });
  });

  group('Message', () {
    test('fromJson/toJson rundt korrekt', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000000);
      final original = Message(
        id: '1',
        senderId: 'me',
        receiverId: 'you',
        text: 'Hallo',
        type: MessageType.text,
        timestamp: now,
      );
      final json = original.toJson();
      final restored = Message.fromJson(json);
      expect(restored.id, '1');
      expect(restored.senderId, 'me');
      expect(restored.receiverId, 'you');
      expect(restored.text, 'Hallo');
      expect(restored.type, MessageType.text);
      expect(restored.timestamp, now);
    });

    test('fromJson mit Bild-Nachricht', () {
      final json = <String, dynamic>{
        'id': '2',
        'senderId': 'me',
        'receiverId': 'you',
        'text': 'Schau mal',
        'type': 'image',
        'mediaUrl': 'image.png',
        'durationSeconds': 0,
        'timestamp': 1000000,
      };
      final msg = Message.fromJson(json);
      expect(msg.type, MessageType.image);
      expect(msg.mediaUrl, 'image.png');
      expect(msg.durationSeconds, 0);
    });

    test('fromJson mit Sprachnachricht', () {
      final json = <String, dynamic>{
        'id': '3',
        'senderId': 'me',
        'receiverId': 'you',
        'text': '',
        'type': 'voice',
        'mediaUrl': 'voice.mp3',
        'durationSeconds': 45,
        'timestamp': 1000000,
      };
      final msg = Message.fromJson(json);
      expect(msg.type, MessageType.voice);
      expect(msg.mediaUrl, 'voice.mp3');
      expect(msg.durationSeconds, 45);
    });

    test('fromJson mit unbekanntem Type faellt auf text zurueck', () {
      final json = <String, dynamic>{
        'id': '4',
        'senderId': 'me',
        'receiverId': 'you',
        'text': 'Hi',
        'type': 'unknown',
        'timestamp': 1000000,
      };
      final msg = Message.fromJson(json);
      expect(msg.type, MessageType.text);
    });

    test('fromJson mit fehlendem Type nutzt text', () {
      final json = <String, dynamic>{
        'id': '4',
        'senderId': 'me',
        'receiverId': 'you',
        'text': 'Hi',
        'timestamp': 1000000,
      };
      final msg = Message.fromJson(json);
      expect(msg.type, MessageType.text);
    });

    test('copyWith aendert nur gewaehlte Felder', () {
      final msg = Message(
        id: '1',
        senderId: 'me',
        receiverId: 'you',
        text: 'Hallo',
        type: MessageType.text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      final updated = msg.copyWith(text: 'Tschuess');
      expect(updated.id, '1');
      expect(updated.senderId, 'me');
      expect(updated.receiverId, 'you');
      expect(updated.text, 'Tschuess');
      expect(updated.type, MessageType.text);
    });

    test('isFrom erkennt Absender', () {
      final m = Message(
        id: '1',
        senderId: 'me',
        receiverId: 'other',
        text: 'hi',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(m.isFrom('me'), isTrue);
      expect(m.isFrom('other'), isFalse);
      expect(m.isFrom('nobody'), isFalse);
    });
  });

  group('AppSettings', () {
    test('defaults entsprechen "Persönlichkeit zuerst" (Blind Mode an)', () {
      final s = AppSettings.defaults();
      expect(s.blindModeEnabled, isTrue);
      expect(s.profileVisibility, ProfileVisibility.everyone);
      expect(s.revealPhotosAfterMatch, isTrue);
      expect(s.onboardingCompleted, isTrue);
      expect(s.maxDistanceKm, equals(50));
      expect(s.ageRangeMin, 16);
      expect(s.ageRangeMax, 99);
    });

    test('persistenz via json', () {
      final s = AppSettings.defaults().copyWith(
        blindModeEnabled: true,
        profileVisibility: ProfileVisibility.matchesOnly,
        useDarkMode: true,
        maxDistanceKm: 25,
        ageRangeMin: 20,
        ageRangeMax: 35,
      );
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.blindModeEnabled, isTrue);
      expect(restored.profileVisibility, ProfileVisibility.matchesOnly);
      expect(restored.useDarkMode, isTrue);
      expect(restored.maxDistanceKm, 25);
      expect(restored.ageRangeMin, 20);
      expect(restored.ageRangeMax, 35);
    });

    test('fromJson ignoriert unbekannte Felder (z. B. alter swipeMode)', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'blindModeEnabled': false,
        'swipeMode': 'invalid_mode',
      });
      expect(s.blindModeEnabled, isFalse);
      expect(s.profileVisibility, ProfileVisibility.everyone);
    });

    test('fromJson mit fehlendem ProfilVisibility nutzt everyone', () {
      final json = <String, dynamic>{'blindModeEnabled': false};
      final s = AppSettings.fromJson(json);
      expect(s.profileVisibility, ProfileVisibility.everyone);
    });

    test('copyWith aendert nur gewaehlte Felder', () {
      final s = AppSettings.defaults();
      final updated = s.copyWith(blindModeEnabled: true);
      expect(updated.blindModeEnabled, isTrue);
      expect(updated.profileVisibility, ProfileVisibility.everyone);
      expect(updated.maxDistanceKm, equals(50));
    });

    test('copyWith(useDarkMode: null) setzt System zurück (Sentinel)', () {
      // Regression: "System" war nach Hell/Dunkel nicht mehr wählbar,
      // weil copyWith null nicht von "nicht gesetzt" unterschied.
      final dark = AppSettings.defaults().copyWith(useDarkMode: true);
      expect(dark.useDarkMode, isTrue);
      final system = dark.copyWith(useDarkMode: null);
      expect(system.useDarkMode, isNull);
      // Ohne Angabe bleibt der alte Wert erhalten.
      final untouched = dark.copyWith();
      expect(untouched.useDarkMode, isTrue);
    });
  });

  group('ProfileVisibility', () {
    test('Alle Werte vorhanden', () {
      expect(ProfileVisibility.values.length, 3);
      expect(ProfileVisibility.everyone.value, 'everyone');
      expect(ProfileVisibility.matchesOnly.value, 'matches_only');
      expect(ProfileVisibility.hidden.value, 'hidden');
    });

    test('fromValue liefert default bei null', () {
      expect(ProfileVisibility.fromValue(null), ProfileVisibility.everyone);
    });

    test('fromValue liefert default bei ungueltigem Wert', () {
      expect(ProfileVisibility.fromValue('nope'), ProfileVisibility.everyone);
    });

    test('fromValue liefert hidden bei hidden', () {
      expect(ProfileVisibility.fromValue('hidden'), ProfileVisibility.hidden);
    });

    test('fromValue liefert matchesOnly bei matches_only', () {
      expect(
        ProfileVisibility.fromValue('matches_only'),
        ProfileVisibility.matchesOnly,
      );
    });
  });
}
