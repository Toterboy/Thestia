// Tests fuer die Vorstellung (Text + Audio) im UserProfile.
//
// BEFUND (07.11.2026, Betreiber):
//   "Meine Vorstellung stimmt auch nicht, da beide Nutzer eine
//    Vorstellung gemacht haben aber hier steht, dass keine hinterlegt
//    wurde (also bei Profil und dann meine Vorstellung)."
//   "Vorstellung von anderen nicht abhoerbar. Sie laedt nicht oder
//    braucht seeeeeeehr lange."
//
// WARUM ueberhaupt ein Test:
//   Die Daten waren in der Datenbank nachweislich vorhanden (Text ja,
//   Audio-Datei ja) - nur kam der Client nicht an sie heran. Der Grund
//   war ein Schreib-/Lese-Unterschied: das Profil wird aus drei
//   Quellen gelesen, und die benutzten drei Schreibweisen
//   (Server: snake_case, handgebaute Maps und Cache: camelCase). Der
//   Parser kannte nur eine davon.
//
//   Solche Fehler sind beim Testen auf dem Geraet unsichtbar: Es gibt
//   keinen Fehler, nur ein leeres Feld. Deshalb wird hier jede
//   Schreibweise einzeln geprueft - und der Weg ueber den Cache
//   (Schreiben und wieder Lesen) ebenfalls.
//
// ZUSAETZLICH: tool/check_profile_cache_keys.py sucht im Quelltext
// nach weiteren solchen Mismatches. Dieser Test haelt die Reparatur
// fest.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/user_profile.dart';

/// Das Profil, wie der SERVER es liefert (snake_case).
Map<String, dynamic> serverMap() => <String, dynamic>{
  'user_id': '46f3f558-b134-4d25-946b-4e052a8ab3b5',
  'name': 'Thoralf',
  'bio': 'Hallo',
  'interests': <dynamic>['Wandern'],
  'photos': <dynamic>[],
  'gender': 'male',
  'age': 18,
  'intro_text': 'Hallo, ich bin neu hier.',
  'intro_audio_path': '46f3f558-b134-4d25-946b-4e052a8ab3b5/intro.m4a',
  'favorite_song': 'Some Song',
  'birthday_style': 'classic',
  'birthday_today': false,
  'is_verified': false,
};

/// Das Profil, wie der CACHE es liefert (camelCase, so wie toJson es
/// schreibt).
Map<String, dynamic> cacheMap() => <String, dynamic>{
  'id': '46f3f558-b134-4d25-946b-4e052a8ab3b5',
  'name': 'Thoralf',
  'bio': 'Hallo',
  'interests': <dynamic>['Wandern'],
  'photos': <dynamic>[],
  'gender': 'male',
  'introText': 'Hallo, ich bin neu hier.',
  'introAudioPath': '46f3f558-b134-4d25-946b-4e052a8ab3b5/intro.m4a',
  'favoriteSong': 'Some Song',
  'birthdayStyle': 'classic',
  'birthdayToday': false,
  'is_verified': false,
};

void main() {
  group('Die Vorstellung kommt aus jeder Quelle an', () {
    test('aus der Server-Antwort (snake_case)', () {
      final profil = UserProfile.fromPublicView(serverMap());
      expect(profil.introText, 'Hallo, ich bin neu hier.');
      expect(
        profil.introAudioPath,
        '46f3f558-b134-4d25-946b-4e052a8ab3b5/intro.m4a',
      );
    });

    test('aus dem Cache (camelCase)', () {
      final profil = UserProfile.fromJson(cacheMap());
      expect(profil.introText, 'Hallo, ich bin neu hier.');
      expect(
        profil.introAudioPath,
        '46f3f558-b134-4d25-946b-4e052a8ab3b5/intro.m4a',
      );
    });

    test('aus der Server-Zuordnung des DB-Service (camelCase)', () {
      // Das ist die Zuordnung aus supabase_database_service.dart: sie
      // holt den Serverwert und schreibt ihn in camelCase um.
      final server = serverMap();
      final zugeordnet = <String, dynamic>{
        'id': server['user_id'],
        'name': server['name'],
        'bio': server['bio'],
        'introText': server['intro_text'],
        'introAudioPath': server['intro_audio_path'],
        'favoriteSong': server['favorite_song'],
        'birthdayStyle': server['birthday_style'],
        'is_verified': server['is_verified'],
      };
      final profil = UserProfile.fromJson(zugeordnet);
      expect(profil.introText, 'Hallo, ich bin neu hier.');
      expect(
        profil.introAudioPath,
        '46f3f558-b134-4d25-946b-4e052a8ab3b5/intro.m4a',
      );
    });

    test('auch wenn beide Schreibweisen dastehen', () {
      final gemischt = <String, dynamic>{...serverMap(), ...cacheMap()};
      final profil = UserProfile.fromJson(gemischt);
      expect(profil.introText, 'Hallo, ich bin neu hier.');
      expect(profil.introAudioPath, isNotNull);
    });
  });

  group('Die Vorstellung ueberlebt den App-Neustart', () {
    test('Schreiben und wieder Lesen liefert dieselbe Vorstellung', () {
      // DER WEG, DER IM AUFTRAG KAPUTT WAR: Der Cache enthaelt die
      // Vorstellung, aber der Parser las sie nicht - nach jedem
      // Neustart war sie weg.
      final original = UserProfile.fromPublicView(serverMap());
      final wieder = UserProfile.fromJson(original.toJson());

      expect(wieder.introText, original.introText);
      expect(wieder.introAudioPath, original.introAudioPath);
      expect(wieder.introText, isNotEmpty);
    });

    test('auch der Lieblingssong und der Geburtstagsstil bleiben', () {
      // Dieselbe Fehlerklasse: diese Felder waren schon einmal
      // betroffen (siehe Kommentar in supabase_database_service.dart).
      final original = UserProfile.fromPublicView(serverMap());
      final wieder = UserProfile.fromJson(original.toJson());

      expect(wieder.favoriteSong, original.favoriteSong);
      expect(wieder.birthdayStyle, original.birthdayStyle);
    });
  });

  group('Ohne Vorstellung bleibt es leer - aber ohne Absturz', () {
    test('fehlende Felder sind kein Fehler', () {
      final profil = UserProfile.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'Y',
        'bio': '',
        'interests': <dynamic>[],
        'photos': <dynamic>[],
      });
      expect(profil.introText, '');
      expect(profil.introAudioPath, isNull);
    });

    test('der Server gewinnt, wenn beide Schreibweisen dastehen', () {
      // WICHTIG (Befund 07.11.2026: "Die Profilvorschau soll dem
      // entsprechen, was auch andere wirklich sehen koennen"): Der
      // Server ist die Wahrheit fuer das, was andere sehen. Die
      // snake_case-Schreibweise kommt deshalb zuerst - ein leerer
      // Serverwert ("keine Vorstellung") schlaegt also einen
      // alten Cachewert. Sonst wuerde die Vorschau etwas zeigen, was
      // andere gar nicht sehen.
      final gemischt = <String, dynamic>{
        'id': 'x',
        'name': 'Y',
        'bio': '',
        'interests': <dynamic>[],
        'photos': <dynamic>[],
        'intro_text': '',
        'introText': 'Alter Cachewert',
      };
      final profil = UserProfile.fromJson(gemischt);
      expect(profil.introText, '');
    });

    test(
      'ein leerer Wert verdeckt einen echten Wert derselben Quelle nicht',
      () {
        // Innerhalb EINER Quelle ist der Wert eindeutig: der Server
        // liefert "" fuer "keine Vorstellung" - es gibt dann nichts zu
        // verbergen.
        final profil = UserProfile.fromJson(<String, dynamic>{
          'id': 'x',
          'name': 'Y',
          'bio': '',
          'interests': <dynamic>[],
          'photos': <dynamic>[],
          'introText': 'Der echte Text',
        });
        expect(profil.introText, 'Der echte Text');
      },
    );
  });
}
