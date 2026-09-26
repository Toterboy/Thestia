import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/utils/constants.dart';

/// Zaehlt Schreibvorgaenge, damit die Deduplizierung geprueft werden kann.
class _CountingStorage implements LocalStorage {
  final Map<String, String> _data = {};
  int writes = 0;

  @override
  Future<void> saveString(String key, String value) async {
    writes++;
    _data[key] = value;
  }

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async {
    writes++;
    _data[key] = value.toString();
  }

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async {
    writes++;
    _data.remove(key);
  }

  @override
  Future<void> saveInt(String key, int value) async {
    writes++;
    _data[key] = value.toString();
  }

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

void main() {
  late _CountingStorage storage;
  late ProviderContainer container;

  setUp(() {
    storage = _CountingStorage();
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
  });

  tearDown(() => container.dispose());

  group('setCustomChatBackground', () {
    test('setzt Pfad UND Auswahl in einem Schritt', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomChatBackground('/docs/chat_bg_custom.jpg');

      final state = container.read(settingsProvider);
      expect(state.chatBackgroundPath, '/docs/chat_bg_custom.jpg');
      expect(state.chatBackground, ChatBackgrounds.custom);
    });

    test('null entfernt das Bild und setzt auf "kein Hintergrund"', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomChatBackground('/docs/chat_bg_custom.jpg');
      await notifier.setCustomChatBackground(null);

      final state = container.read(settingsProvider);
      expect(state.chatBackgroundPath, isNull);
      expect(state.chatBackground, ChatBackgrounds.none);
    });

    test('erzeugt genau EINEN Storage-Write (nicht zwei)', () async {
      final notifier = container.read(settingsProvider.notifier);
      storage.writes = 0;
      await notifier.setCustomChatBackground('/docs/chat_bg_custom.jpg');
      // Vorher: setChatBackgroundPath + setChatBackground = zwei komplette
      // JSON-Encodes und zwei Keystore-Writes pro Tap.
      expect(storage.writes, 1);
    });
  });

  group('Persist-Deduplizierung', () {
    test('unveraenderter State schreibt nicht erneut', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.toggleBlindMode(false);
      final afterFirst = storage.writes;

      // Gleicher Wert nochmal: der State ist identisch, also kein I/O.
      await notifier.toggleBlindMode(false);
      expect(storage.writes, afterFirst);
    });

    test('echte Aenderung schreibt genau einmal', () async {
      final notifier = container.read(settingsProvider.notifier);
      storage.writes = 0;
      await notifier.toggleBlindMode(false);
      await notifier.toggleBlindMode(false);
      expect(storage.writes, 1);

      await notifier.toggleBlindMode(true);
      expect(storage.writes, 2);
    });
  });

  group('Persist-Fehler', () {
    test('ein Keystore-Fehler wirft nicht nach oben (kein unhandled)',
        () async {
      final broken = _BrokenStorage();
      final c = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(broken)],
      );
      // Der State wird optimistisch gesetzt; der Schreibfehler darf die UI
      // nicht mit einer unbehandelten Async-Exception zerstoeren.
      await c.read(settingsProvider.notifier).toggleBlindMode(false);
      expect(c.read(settingsProvider).blindModeEnabled, isFalse);
      expect(broken.attempts, greaterThan(0));
      c.dispose();
    });
  });

  group('Gespeicherter State ist round-trip-faehig', () {
    test('Chat-Hintergrund ueberlebt JSON-Encode/Decode', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomChatBackground('/docs/chat_bg_custom.jpg');
      await notifier.setChatBackground(ChatBackgrounds.waves);

      final raw = await storage.getString(AppConstants.prefsSettingsKey);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['chatBackground'], ChatBackgrounds.waves);
      expect(decoded['chatBackgroundPath'], '/docs/chat_bg_custom.jpg');
    });
  });
}

class _BrokenStorage implements LocalStorage {
  int attempts = 0;

  @override
  Future<void> saveString(String key, String value) async {
    attempts++;
    throw StateError('Keystore nicht verfuegbar');
  }

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> saveBool(String key, bool value) async {}

  @override
  Future<bool?> getBool(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> saveInt(String key, int value) async {}

  @override
  Future<int?> getInt(String key) async => null;
}
