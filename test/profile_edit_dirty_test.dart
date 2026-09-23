// Widget-Test: Dirty-Erkennung des Profil-Editors.
//
// Reproduziert den Nutzerbericht "Speichern-Nachfrage kommt nicht":
// Nach einer Text-Änderung muss der Dirty-Flag true sein und PopScope
// muss den Zurück-Weg blockieren (canPop == false). Ohne Änderungen muss
// canPop == true sein (verlässt den Screen ohne Nachfrage).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/screens/profile/profile_edit_screen.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/secure_storage.dart';

class _FakeLocalStorage implements LocalStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';

  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);

  @override
  Future<void> remove(String key) async => map.remove(key);
}

class _FakeSecurePrefs extends SecurePreferencesStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> remove(String key) async => map.remove(key);
}

class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String json) async {}
}

Future<ProviderContainer> _pumpEditor(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // IntroEditor erzeugt im initState einen AudioRecorder -> Kanal mocken.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );

  final container = ProviderContainer(overrides: [
    localStorageProvider.overrideWithValue(_FakeLocalStorage()),
    securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
    secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
    sharedPrefsProvider.overrideWithValue(prefs),
    profileProvider.overrideWith((ref) {
      final notifier = ProfileNotifier(
        _FakeLocalStorage(),
        _FakeSecureProfileStore(),
      );
      notifier.setProfile(const UserProfile(
        id: 'test-user',
        name: 'Lena',
        bio: 'Hallo',
      ));
      return notifier;
    }),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfileEditScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Text-Änderung setzt Dirty-Flag und blockiert Zurück',
      (tester) async {
    final container = await _pumpEditor(tester);

    // Ohne Änderung: nicht dirty, Pop erlaubt.
    expect(container.read(profileEditDirtyProvider), isFalse);
    // HINWEIS: byType(PopScope) matcht nicht - die App instanziert
    // PopScope<Object>, der Type-Literal vergleicht aber PopScope<dynamic>.
    final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
    final popScope = tester.widget<PopScope>(popScopeFinder);
    expect(popScope.canPop, isTrue,
        reason: 'Ohne Änderungen muss die Zurück-Geste ohne Nachfrage '
            'durchgelassen werden.');

    // Name ändern (das erste TextFormular im Formular ist das Name-Feld).
    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'Lena Bearbeitet');
    await tester.pumpAndSettle();

    expect(container.read(profileEditDirtyProvider), isTrue,
        reason: 'Nach einer Text-Änderung muss der Dirty-Flag true sein - '
            'sonst erscheint weder beim Tab-Wechsel noch beim Zurückgehen '
            'die Speichern-Nachfrage.');
    final popScopeAfter =
        tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
    expect(popScopeAfter.canPop, isFalse,
        reason: 'Mit Änderungen muss PopScope die Zurück-Geste blockieren.');
  });

  testWidgets('Slider-Änderung (Altersspanne) setzt Dirty-Flag',
      (tester) async {
    final container = await _pumpEditor(tester);

    // Zum Altersspannen-Bereich scrollen (Form ist lang) und den
    // Mindestalter-Slider antippen (Mitte des Tracks = neuer Wert).
    final minLabel = find.text('Mindestalter: 16 Jahre');
    await tester.scrollUntilVisible(minLabel, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    final sliders = find.byType(Slider);
    // Reihenfolge im Formular: Entfernung, Mindestalter, Höchstalter.
    final ageSlider = sliders.at(1);
    final box = tester.getRect(ageSlider);
    await tester.tapAt(Offset(box.left + box.width * 0.8, box.center.dy));
    await tester.pumpAndSettle();
    // Debounce-Timer (1,5 s) des Auto-Sync ablaufen lassen, damit am
    // Testende kein Timer mehr pendet.
    await tester.pump(const Duration(seconds: 2));

    expect(container.read(profileEditDirtyProvider), isTrue,
        reason: 'Regler-Änderungen müssen ebenfalls als "ungespeichert" '
            'gelten (Nachfrage beim Verlassen).');
  });
}
