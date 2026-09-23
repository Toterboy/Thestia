import 'dart:convert';

import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/screens/core/main_navigation.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> saveInt(String key, int value) async => _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);


}

ProviderContainer _createContainer() {
  final storage = _FakeStorage();
  return ProviderContainer(
    overrides: [localStorageProvider.overrideWithValue(storage)],
  );
}

void main() {
  group('Blind-Mode-Logik', () {
    test('toggleBlindMode schaltet den Status korrekt um', () async {
      final container = _createContainer();
      final notifier = container.read(settingsProvider.notifier);

      // Standard: Blind Mode AN ("Persönlichkeit zuerst").
      final initial = container.read(settingsProvider).blindModeEnabled;
      expect(initial, isTrue);

      await notifier.toggleBlindMode(true);
      expect(container.read(settingsProvider).blindModeEnabled, isTrue);

      await notifier.toggleBlindMode(false);
      expect(container.read(settingsProvider).blindModeEnabled, isFalse);
    });

    test('Standard-Einstellungen haben Blind Mode an', () {
      final container = _createContainer();
      expect(container.read(settingsProvider).blindModeEnabled, isTrue);
    });

    test('setMaxDistanceKm speichert die Distanz', () async {
      final container = _createContainer();
      await container.read(settingsProvider.notifier).setMaxDistanceKm(25);
      expect(container.read(settingsProvider).maxDistanceKm, 25);
    });

    test('setRevealPhotosAfterMatch aendert Einstellung', () async {
      final container = _createContainer();
      await container.read(settingsProvider.notifier).setRevealPhotosAfterMatch(true);
      expect(container.read(settingsProvider).revealPhotosAfterMatch, isTrue);

      await container.read(settingsProvider.notifier).setRevealPhotosAfterMatch(false);
      expect(container.read(settingsProvider).revealPhotosAfterMatch, isFalse);
    });

    test('setProfileVisibility aendert Sichtbarkeit', () async {
      final container = _createContainer();
      await container.read(settingsProvider.notifier)
          .setProfileVisibility(ProfileVisibility.matchesOnly);
      expect(container.read(settingsProvider).profileVisibility,
          ProfileVisibility.matchesOnly);

      await container.read(settingsProvider.notifier)
          .setProfileVisibility(ProfileVisibility.hidden);
      expect(container.read(settingsProvider).profileVisibility,
          ProfileVisibility.hidden);
    });

    test('setDarkMode aendert Theme-Einstellung', () async {
      final container = _createContainer();
      await container.read(settingsProvider.notifier).setDarkMode(true);
      expect(container.read(settingsProvider).useDarkMode, isTrue);

      await container.read(settingsProvider.notifier).setDarkMode(false);
      expect(container.read(settingsProvider).useDarkMode, isFalse);
    });

    test('setAgeRange aendert Altersspanne', () async {
      final container = _createContainer();
      await container.read(settingsProvider.notifier).setAgeRange(20, 35);
      final settings = container.read(settingsProvider);
      expect(settings.ageRangeMin, 20);
      expect(settings.ageRangeMax, 35);
    });

    test('completePersonalityTest markiert Test als abgeschlossen', () async {
      final container = _createContainer();
      expect(container.read(settingsProvider).personalityTestCompleted, isFalse);
      await container.read(settingsProvider.notifier).completePersonalityTest();
      expect(container.read(settingsProvider).personalityTestCompleted, isTrue);
    });

    test('completeOnboarding: Onboarding ist standardmäßig bereits abgeschlossen', () async {
      final container = _createContainer();
      expect(container.read(settingsProvider).onboardingCompleted, isTrue);
      await container.read(settingsProvider.notifier).completeOnboarding();
      expect(container.read(settingsProvider).onboardingCompleted, isTrue);
    });

    test('completeOneTimeSettings markiert Settings als abgeschlossen', () async {
      final container = _createContainer();
      expect(container.read(settingsProvider).oneTimeSettingsCompleted, isFalse);
      await container.read(settingsProvider.notifier).completeOneTimeSettings();
      expect(container.read(settingsProvider).oneTimeSettingsCompleted, isTrue);
    });

    test('markIntroSeen markiert Einfuehrung als gesehen', () async {
      final container = _createContainer();
      expect(container.read(settingsProvider).introSeen, isFalse);
      await container.read(settingsProvider.notifier).markIntroSeen();
      expect(container.read(settingsProvider).introSeen, isTrue);
    });
  });

  group('Einstellungen-Persistenz', () {
    test('Einstellungen werden im Storage persistiert', () async {
      final storage = _FakeStorage();
      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );

      await container.read(settingsProvider.notifier).setMaxDistanceKm(42);
      await container.read(settingsProvider.notifier).toggleBlindMode(true);
      await container.read(settingsProvider.notifier)
          .setProfileVisibility(ProfileVisibility.hidden);
      await container.read(settingsProvider.notifier).setDarkMode(true);

      // Direkt aus dem Storage lesen
      final raw = await storage.getString('app_settings');
      expect(raw, isNotNull);

      final map = jsonDecode(raw!) as Map<String, dynamic>;
      expect(map['maxDistanceKm'], 42);
      expect(map['blindModeEnabled'], isTrue);
      expect(map['profileVisibility'], 'hidden');
      expect(map['useDarkMode'], isTrue);
    });

    test('Corrupte Daten im Storage fuehren zu Defaults', () async {
      final storage = _FakeStorage();
      await storage.saveString('app_settings', 'not_valid_json{');

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );

      // Sollte nicht crashen, sondern Defaults liefern
      expect(container.read(settingsProvider).blindModeEnabled, isTrue);
      expect(container.read(settingsProvider).maxDistanceKm, equals(50));
    });

    test('Corrupte Daten im Storage fuehren zu Defaults', () async {
      final storage = _FakeStorage();
      await storage.saveString('app_settings', 'not_valid_json{');

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );

      // Sollte nicht crashen, sondern Defaults liefern
      expect(container.read(settingsProvider).blindModeEnabled, isTrue);
      expect(container.read(settingsProvider).maxDistanceKm, equals(50));
    });

    test('Corrupte Daten im Storage fuehren zu Defaults', () async {
      final storage = _FakeStorage();
      await storage.saveString('app_settings', 'not_valid_json{');

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );
      final settings = container.read(settingsProvider);

      // Sollte nicht crashen, sondern Defaults liefern
      expect(settings.blindModeEnabled, isTrue);
      expect(settings.maxDistanceKm, equals(50));
    });
  });

  group('Bottom-Navigation-State', () {
    test('currentNavIndexProvider startet bei 0', () {
      final container = ProviderContainer();
      expect(container.read(currentNavIndexProvider), 0);
    });

    test('Index kann zentral gesetzt werden', () {
      final container = ProviderContainer();
      container.read(currentNavIndexProvider.notifier).state = 2;
      expect(container.read(currentNavIndexProvider), 2);

      container.read(currentNavIndexProvider.notifier).state = 0;
      expect(container.read(currentNavIndexProvider), 0);
    });

    test('Index akzeptiert alle gueltigen Werte', () {
      final container = ProviderContainer();
      final notifier = container.read(currentNavIndexProvider.notifier);

      for (var i = 0; i < 5; i++) {
        notifier.state = i;
        expect(container.read(currentNavIndexProvider), i);
      }
    });
  });
}
