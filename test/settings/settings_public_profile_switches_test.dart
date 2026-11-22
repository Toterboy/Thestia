// Die Schalter fuer das oeffentliche Profil (NUTZERWUNSCH 22.11.2026:
// "Man soll diese Punkte und die Gewohnheiten einzeln fuer's oeffentliche
// Profil an und aus machen koennen").
//
// WAS HIER GEPRUEFT WIRD:
//   * die Schalter aendern den Zustand und werden gespeichert,
//   * der Server bekommt die Spalte geschrieben (er entscheidet, was
//     andere sehen - Migration 222),
//   * der Serverstand gewinnt beim Zuruecklesen (zweites Geraet),
//   * das Modell verliert die Schalter nicht (Cache!).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/storage/local_storage.dart';

/// Der Speicher im RAM (die Einstellungen werden dort abgelegt).
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Container mit dem Speicher im RAM.
ProviderContainer _container([_FakeLocalStorage? speicher]) {
  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(speicher ?? _FakeLocalStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('Die oeffentlichen Schalter', () {
    test('der Standard ist an - die Angaben stehen oeffentlich', () {
      final settings = AppSettings.defaults();
      expect(settings.showMusicLiked, isTrue);
      expect(settings.showMusicDisliked, isTrue);
      expect(settings.showFavoriteSong, isTrue);
      expect(settings.showFavoriteBand, isTrue);
      expect(settings.showHabitsSmoking, isTrue);
      expect(settings.showHabitsAlcohol, isTrue);
      expect(settings.showHabitsDrugs, isTrue);
    });

    test('das Modell verliert die Schalter nicht', () {
      const settings = AppSettings(
        showMusicLiked: false,
        showMusicDisliked: false,
        showFavoriteSong: false,
        showFavoriteBand: false,
        showHabitsSmoking: false,
        showHabitsAlcohol: false,
        showHabitsDrugs: false,
      );
      // Der Cache (JSON) muss sie behalten - sonst waeren sie nach
      // einem Neustart wieder "an".
      final json =
          jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
      final zurueck = AppSettings.fromJson(json);
      expect(zurueck.showMusicLiked, isFalse);
      expect(zurueck.showMusicDisliked, isFalse);
      expect(zurueck.showFavoriteSong, isFalse);
      expect(zurueck.showFavoriteBand, isFalse);
      expect(zurueck.showHabitsSmoking, isFalse);
      expect(zurueck.showHabitsAlcohol, isFalse);
      expect(zurueck.showHabitsDrugs, isFalse);
    });

    test('jeder Schalter laesst sich einzeln schalten', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setShowMusicLiked(false);
      expect(notifier.state.showMusicLiked, isFalse);
      expect(notifier.state.showMusicDisliked, isTrue);

      await notifier.setShowMusicDisliked(false);
      expect(notifier.state.showMusicDisliked, isFalse);

      await notifier.setShowFavoriteSong(false);
      expect(notifier.state.showFavoriteSong, isFalse);

      await notifier.setShowFavoriteBand(false);
      expect(notifier.state.showFavoriteBand, isFalse);

      await notifier.setShowHabitsSmoking(false);
      expect(notifier.state.showHabitsSmoking, isFalse);

      await notifier.setShowHabitsAlcohol(false);
      expect(notifier.state.showHabitsAlcohol, isFalse);

      await notifier.setShowHabitsDrugs(false);
      expect(notifier.state.showHabitsDrugs, isFalse);
    });

    test('der Serverstand gewinnt (zweites Geraet)', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.applyServerSwitches(<String, dynamic>{
        'show_music_liked': false,
        'show_favorite_band': false,
        'show_habits_drugs': false,
      });

      expect(notifier.state.showMusicLiked, isFalse);
      expect(notifier.state.showFavoriteBand, isFalse);
      expect(notifier.state.showHabitsDrugs, isFalse);
      // Die nicht genannten bleiben unberuehrt.
      expect(notifier.state.showFavoriteSong, isTrue);
      expect(notifier.state.showHabitsSmoking, isTrue);
    });

    test('ein alter Serverstand laesst den lokalen Stand stehen', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setShowMusicLiked(false);

      // Der Server kennt die Spalte nicht (alte Version).
      await notifier.applyServerSwitches(<String, dynamic>{
        'show_distance': true,
      });

      expect(
        notifier.state.showMusicLiked,
        isFalse,
        reason: 'Fehlende Spalten duerfen den lokalen Stand nicht loeschen.',
      );
    });
  });
}
