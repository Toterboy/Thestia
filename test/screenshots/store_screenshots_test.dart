// Store-Screenshot-Generator (KEIN regulärer Test).
//
// Rendert echte App-Screens in Phone-Auflösung (1080x1920, dpr 3) und
// schreibt sie als PNG-Goldens nach goldens/. Aufruf (schreibt/neu):
//   flutter test --update-goldens test/screenshots/store_screenshots_test.dart
// Anschließend nach fastlane/metadata/android/de-DE/images/phoneScreenshots/
// kopieren (siehe tool/copy_store_screenshots.ps1).
//
// Hinweise:
//  - flutter_test nutzt standardmäßig die Ahem-Font (Text = Blöcke). Hier
//    wird eine echte Systemschrift (Segoe UI) als "Roboto" geladen, damit
//    die Screens realistisch aussehen.
//  - Alle gerenderten Screens funktionieren OHNE Supabase/Backend.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/screens/auth/login_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_how_it_works_screen.dart';
import 'package:wisp/screens/profile/profile_edit_screen.dart';
import 'package:wisp/screens/welcome/welcome_screen.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/theme/app_theme.dart';
import 'package:wisp/widgets/theme_picker.dart';

bool _fontsLoaded = false;

/// Screenshots nur auf Anforderung generieren: Der normale `flutter test`
/// Lauf ueberspringt diese Tests (Golden-Vergleiche gehoeren nicht in die
/// Standardsuite). Generieren mit:
///   STORE_SHOTS=1 flutter test --update-goldens test/screenshots/
final bool _storeShotsEnabled =
    Platform.environment.containsKey('STORE_SHOTS');

/// Lädt echte Fonts, damit Goldens keinen Ahem-Blocktext zeigen.
Future<void> _loadFontsOnce() async {
  if (_fontsLoaded) return;
  // Systemschrift (Windows) als App-Standardfamilie.
  const candidates = [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      break;
    }
  }
  // Material Icons (liegen im Flutter-Cache).
  try {
    final dartExe = File(Platform.resolvedExecutable);
    // .../flutter/bin/cache/dart-sdk/bin/dart.exe -> .../flutter/bin/cache
    final cacheDir = dartExe.parent.parent.parent.parent;
    final icons = File(
      '${cacheDir.path}${Platform.pathSeparator}'
      'artifacts${Platform.pathSeparator}material_fonts${Platform.pathSeparator}'
      'MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  } catch (_) {
    // Ohne Icon-Font rendern Icons als Platzhalter - Screens bleiben nutzbar.
  }
  _fontsLoaded = true;
}

// ---------------------------------------------------------------------------
// Fake-Storage: keine Plattform-Kanäle im Test.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _harness(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(_FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(
        _FakeSecureProfileStore(),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme: WispTheme.classic),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

Future<void> _pumpShot(
  WidgetTester tester,
  Widget child,
  List<Override> overrides,
  String golden,
) async {
  await tester.runAsync(_loadFontsOnce);
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // Platform-Kanäle mocken, die Screens im initState erreichen:
  // SharedPreferences (Migration in UserPreferencesNotifier) und der
  // Audio-Recorder (IntroEditor).
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );

  await tester.pumpWidget(_harness(child, overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    ...overrides,
  ]));
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  // Echtes Async laufen lassen (Bild-Dekodierung): Runde 1 lässt z. B. den
  // Logo-PreCache des Welcome-Screens abschließen, wodurch der Inhalt
  // eingeblendet wird; Runde 2 gibt dem NACHGEBAUTEN Logo (eigenes
  // Resize-Decoding via cacheWidth) Zeit zu liefern.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$golden'),
  );
}

UserProfile _seedProfile() => const UserProfile(
      id: 'screenshot-user',
      name: 'Lena',
      birthDate: null,
      bio: '',
    );

/// Registriert einen Screenshot-Test; ohne STORE_SHOTS=1 uebersprungen.
void _shot(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, body, skip: !_storeShotsEnabled);
}

void main() {
  _shot('01 Willkommen', (tester) async {
    await _pumpShot(
      tester,
      const WelcomeScreen(),
      const [],
      '01_willkommen.png',
    );
  });

  _shot('02 Anmelden', (tester) async {
    await _pumpShot(
      tester,
      const LoginScreen(),
      const [],
      '02_anmelden.png',
    );
    // Beispielhafte Eingaben für den Store (after first frame).
    final fields = find.byType(TextFormField);
    if (tester.widgetList(fields).length >= 2) {
      await tester.enterText(fields.at(0), 'lena@wispdating.de');
      await tester.enterText(fields.at(1), 'geheim1234');
      // Floating-Label-Animation abschließen, sonst überlappt der Label-
      // Text den eingegebenen Wert im Screenshot.
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/02_anmelden.png'),
      );
    }
  });

  _shot('03 Profil bearbeiten', (tester) async {
    final profile = _seedProfile().copyWith(
      birthDate: DateTime(DateTime.now().year - 27, 4, 12),
    );
    final overrides = <Override>[
      profileProvider.overrideWith((ref) {
        final notifier = ProfileNotifier(
          _FakeLocalStorage(),
          _FakeSecureProfileStore(),
        );
        notifier.setProfile(profile);
        return notifier;
      }),
    ];
    await _pumpShot(
      tester,
      const ProfileEditScreen(),
      overrides,
      '03_profil_bearbeiten.png',
    );
  });

  _shot('04 Dating Hour', (tester) async {
    await _pumpShot(
      tester,
      const DatingHourHowItWorksScreen(),
      const [],
      '04_dating_hour.png',
    );
    // Einen Schritt aufklappen, damit der Ablauf im Screenshot sichtbar ist.
    final tiles = find.byType(ExpansionTile);
    if (tester.widgetList(tiles).length >= 3) {
      await tester.tap(tiles.at(2));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/04_dating_hour.png'),
      );
    }
  });

  _shot('05 Farbschemata', (tester) async {
    await _pumpShot(
      tester,
      Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Farbschemata')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deine Farben',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Wähle das Erscheinungsbild, das zu dir passt - und es '
                  'bleibt gespeichert, auch nach dem Wechsel des Geräts.',
                ),
                const SizedBox(height: 24),
                ThemePicker(
                  selectedName: 'classic',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
      const [],
      '05_farbschemata.png',
    );
  });

  _shot('06 Gewohnheiten', (tester) async {
    // Profil-Editor (unterer Bereich): Bio + Gewohnheiten als Flirt-relevantes
    // Feature-Bild. Wir pumpen denselben Screen und scrollen nach unten.
    final profile = _seedProfile().copyWith(
      bio: 'Kaffee, Wandern und gute Gespräche. '
          'Ich zeige erst nach dem Match, wie ich aussehe.',
      smoking: HabitudeLevel.never,
    );
    final overrides = <Override>[
      profileProvider.overrideWith((ref) {
        final notifier = ProfileNotifier(
          _FakeLocalStorage(),
          _FakeSecureProfileStore(),
        );
        notifier.setProfile(profile);
        return notifier;
      }),
    ];
    await _pumpShot(
      tester,
      const ProfileEditScreen(),
      overrides,
      '06_gewohnheiten.png',
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2600));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/06_gewohnheiten.png'),
    );
  });
}
