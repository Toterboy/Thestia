// Die neueren Schalter der Einstellungen.
//
// ANLASS (19.11.2026): `lib/providers/settings/settings_provider.dart` war nur zu
// 78 % abgedeckt - die neueren Schalter (Eisbrecher im Kontext, Dating
// Hour, Chat-Hintergrund, Benachrichtigungen) waren ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Schalter ändern den Zustand und werden gespeichert,
//   * ein UNGÜLTIGER Chat-Hintergrund wird nicht übernommen (der
//     Bildschirm würde sonst einen kaputten Hintergrund zeigen),
//   * "Einrichtung erledigt" bleibt erledigt (zweimal setzen schadet
//     nicht).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/utils/chat/chat_backgrounds.dart';

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
  group('Die einzelnen Schalter', () {
    test('der Eisbrecher im Kontext laesst sich schalten', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      // DER STANDARD: Der Kontext-Eisbrecher ist AN (der Nutzer
      // muss ihn erst ausschalten).
      expect(notifier.state.contextIcebreakerEnabled, isTrue);
      await notifier.setContextIcebreaker(false);
      expect(notifier.state.contextIcebreakerEnabled, isFalse);
      await notifier.setContextIcebreaker(true);
      expect(notifier.state.contextIcebreakerEnabled, isTrue);
    });

    test(
      'das automatische Beitreten zur Dating Hour laesst sich schalten',
      () async {
        final container = _container();
        final notifier = container.read(settingsProvider.notifier);

        await notifier.setDatingHourAutoJoin(true);
        expect(notifier.state.datingHourAutoJoin, isTrue);
        await notifier.setDatingHourAutoJoin(false);
        expect(notifier.state.datingHourAutoJoin, isFalse);
      },
    );

    test(
      'die Einfuehrung der Dating Hour laesst sich als gesehen markieren',
      () async {
        final container = _container();
        final notifier = container.read(settingsProvider.notifier);

        await notifier.markDatingHourIntroSeen();
        expect(notifier.state.datingHourIntroSeen, isTrue);
      },
    );

    test('die unscharfen Bilder im Chat lassen sich schalten', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setBlurChatImages(true);
      expect(notifier.state.blurChatImages, isTrue);
      await notifier.setBlurChatImages(false);
      expect(notifier.state.blurChatImages, isFalse);
    });

    test('die Benachrichtigungen lassen sich einzeln schalten', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setNotifyMatches(false);
      expect(notifier.state.notifyMatches, isFalse);
      await notifier.setNotifyMessages(false);
      expect(notifier.state.notifyMessages, isFalse);
      await notifier.setNotifyDatingHour(false);
      expect(notifier.state.notifyDatingHour, isFalse);
    });

    test('das Thema laesst sich setzen', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setThemeName('dunkel');
      expect(notifier.state.themeName, 'dunkel');
    });
  });

  group('Der Chat-Hintergrund', () {
    test('ein gueltiger Hintergrund wird uebernommen', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setChatBackground(ChatBackgrounds.hearts);
      expect(notifier.state.chatBackground, ChatBackgrounds.hearts);
    });

    test('ein ungueltiger Hintergrund faellt auf "kein" zurueck', () async {
      // DER GRUND: Ein kaputter Hintergrund würde den Chat unlesbar
      // machen - der Schalter darf nur GELTIGE Werte annehmen und
      // fällt sonst auf "kein Hintergrund" zurück.
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setChatBackground(ChatBackgrounds.dots);
      expect(notifier.state.chatBackground, ChatBackgrounds.dots);

      await notifier.setChatBackground('gibtesnicht');
      expect(
        notifier.state.chatBackground,
        ChatBackgrounds.none,
        reason: 'Ein ungueltiger Hintergrund darf nicht im Bildschirm stehen.',
      );
    });

    test('"kein Hintergrund" ist auch gueltig', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setChatBackground(ChatBackgrounds.none);
      expect(notifier.state.chatBackground, ChatBackgrounds.none);
    });
  });

  group('Die Einrichtung', () {
    test('"erledigt" bleibt erledigt', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.markOnboardingDone();
      expect(notifier.state.onboardingDone, isTrue);
      // Ein zweites Mal schadet nicht (der Bildschirm fragt das öfter).
      await notifier.markOnboardingDone();
      expect(notifier.state.onboardingDone, isTrue);
    });

    test('die Einstellung einmalig wird gemerkt', () async {
      final container = _container();
      final notifier = container.read(settingsProvider.notifier);

      expect(notifier.state.oneTimeSettingsCompleted, isFalse);
      await notifier.completeOneTimeSettings();
      expect(notifier.state.oneTimeSettingsCompleted, isTrue);
    });
  });

  group('Die Persistenz', () {
    test('die Schalter werden gespeichert', () async {
      final speicher = _FakeLocalStorage();
      final container = _container(speicher);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setContextIcebreaker(false);
      await notifier.setDatingHourAutoJoin(true);

      // DER ROHSTAND: So sieht man, was wirklich in der Ablage liegt -
      // der Anbieter lädt im Konstruktor (asynchron), das wäre
      // unzuverlässig.
      final raw = await speicher.getString('app_settings');
      expect(raw, isNotNull);
      final map = jsonDecode(raw!) as Map<String, dynamic>;
      expect(map['contextIcebreakerEnabled'], isFalse);
      expect(map['datingHourAutoJoin'], isTrue);
    });
  });
}
