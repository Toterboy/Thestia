import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/app_settings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/utils/constants.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests
/// (Muster aus settings_provider_test.dart).
class _FakeStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async =>
      _data[key] = value;

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

/// Tests für den Bild-Blur-Schutz im Chat:
/// Default AN (Schutz zuerst), Persistenz und Reset-Verhalten.
void main() {
  test('blurChatImages ist standardmäßig AKTIV (Schutz zuerst)', () {
    expect(AppSettings.defaults().blurChatImages, isTrue);
  });

  test('Einstellung wird persistiert und beim Neustart geladen', () async {
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setBlurChatImages(false);
    expect(container.read(settingsProvider).blurChatImages, isFalse);

    // Persistenz: ein JSON-Blob unter prefsSettingsKey.
    final raw = storage._data[AppConstants.prefsSettingsKey];
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as Map<String, dynamic>)['blurChatImages'],
        isFalse);

    // Simulierter App-Neustart: gleicher Speicher, neuer Container.
    final restarted = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(restarted.dispose);
    // Ersten Zugriff starten lassen (initialisiert Notifier + _load),
    // dann dem asynchronen Laden Zeit geben.
    restarted.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(restarted.read(settingsProvider).blurChatImages, isFalse);
  });

  test('resetToDefaults stellt den Schutz wieder her', () async {
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setBlurChatImages(false);
    expect(container.read(settingsProvider).blurChatImages, isFalse);

    await container.read(settingsProvider.notifier).resetToDefaults();
    expect(container.read(settingsProvider).blurChatImages, isTrue);
  });
}
