// Store-Screenshot-Generator fuer v0.9.1 (KEIN regulaerer Test).
//
// Rendert 5 ausgewahlte Screens in ZWEI Aufloesungen:
//   9:16  -> 1080x1920  (Play-Store-Standard fuer Handys)
//   WQHD  -> 2560x1440  (16:9, Tablet-/Landscape-Variante)
//
// Aufruf (schreibt/aktualisiert):
//   $env:STORE_SHOTS="1"; flutter test --update-goldens test/screenshots/store_v091_shots_test.dart
//
// Ausgabe: test/screenshots/store_v091/{9x16,wqhd}/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/screens/dating_hour/dating_hour_how_it_works_screen.dart';
import 'package:thestia/screens/swipe/swipe_mode_selection_screen.dart';
import 'package:thestia/screens/welcome/welcome_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/widgets/chat_background_picker.dart';

/// Ohne STORE_SHOTS=1 werden diese Tests uebersprungen (kein Goldens-Vergleich
/// in der normalen Testsuite).
final bool _enabled = Platform.environment.containsKey('STORE_SHOTS');

/// Zielaufloesungen: (Ordner, physicalSize, devicePixelRatio)
const _sizes = <String, ({Size size, double dpr})>{
  '9x16': (size: Size(1080, 1920), dpr: 3.0),
  'wqhd': (size: Size(2560, 1440), dpr: 2.0),
};

bool _fontsLoaded = false;

/// Echte Systemschrift laden, damit kein Ahem-Blocktext erscheint.
Future<void> _loadFontsOnce() async {
  if (_fontsLoaded) return;
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      break;
    }
  }
  try {
    final dartExe = File(Platform.resolvedExecutable);
    final cacheDir = dartExe.parent.parent.parent.parent;
    final icons = File(
      '${cacheDir.path}${Platform.pathSeparator}'
      'artifacts${Platform.pathSeparator}material_fonts${Platform.pathSeparator}'
      'MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  } catch (_) {}
  _fontsLoaded = true;
}

// ---------------------------------------------------------------------------
// Fake-Storage (keine Plattform-Kanaele im Test)
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

Widget _harness(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(_FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme: ThestiaTheme.classic),
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

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required String outDir,
  required String name,
  required Size size,
  required double dpr,
  Future<void> Function(WidgetTester)? after,
}) async {
  await tester.runAsync(_loadFontsOnce);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );

  await tester.pumpWidget(_harness(child, prefs));
  for (var i = 0; i < 3; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
  }
  if (after != null) {
    await after(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$outDir/$name.png'),
  );
}

/// Registriert einen Screen in beiden Aufloesungen.
void _shot(
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester)? after,
}) {
  for (final entry in _sizes.entries) {
    testWidgets('$name [${entry.key}]', (tester) async {
      await _pump(
        tester,
        build(),
        outDir: 'store_v091/${entry.key}',
        name: name,
        size: entry.value.size,
        dpr: entry.value.dpr,
        after: after,
      );
    }, skip: !_enabled);
  }
}

void main() {
  // 1) Willkommen: das Versprechen der App (Persönlichkeit vor Aussehen).
  _shot('01_willkommen', () => const WelcomeScreen());

  // 2) Anmelden/Registrieren: mit beispielhaften Eingaben.
  _shot('02_anmelden', () => const LoginScreen(), after: (tester) async {
        final fields = find.byType(TextFormField);
        if (tester.widgetList(fields).length >= 2) {
          await tester.enterText(fields.at(0), 'lena@thestia.de');
          await tester.enterText(fields.at(1), 'geheim1234');
          await tester.pump(const Duration(milliseconds: 400));
        }
      });

  // 3) Entdecken: die Modi inkl. Transit Spark.
  _shot('03_entdecken', () => const SwipeModeSelectionScreen());

  // 4) Chat-Hintergrund (NEU in v0.9.1): Muster + eigenes Bild.
  _shot('04_chat_hintergrund', () => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Chat-Hintergrund')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Muster oder eigenes Bild',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Gilt für alle Chats und übersteht das Gerätewechsel-'
                  'Update.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const ChatBackgroundPicker(),
              ],
            ),
          ),
        ),
      ));

  // 5) Dating Hour: das Event-Feature.
  _shot('05_dating_hour', () => const DatingHourHowItWorksScreen());
}
