// Die Helfer fuer die Tests des Bildschirms 'store_v091_shots'.
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Helfer
// (Ersatz-Speicher, Aufbau, Bildschirm-Helfer) liegen hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.

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
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './support/store_screenshot_insets.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/models/match.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/widgets/appearance_selector.dart';
import 'package:thestia/widgets/chat_background_picker.dart';
import 'package:thestia/widgets/theme_picker.dart';
import 'package:thestia/utils/best_effort.dart';

final bool enabled = Platform.environment.containsKey('STORE_SHOTS');
final String lang = (Platform.environment['STORE_SHOTS_LANG'] ?? 'de')
    .toLowerCase();
String storeV091ShotsT(String de, String en) => lang == 'en' ? en : de;
const String rootDe = 'store_v091';
const String rootEn = 'store_v091_en';
String get root => lang == 'en' ? rootEn : rootDe;
const sizes = <String, ({Size size, double dpr})>{
  'phone': (size: Size(1080, 2400), dpr: 3.0),
};
const Size storeV091ShotsPhone = Size(1080, 2400);
const double storeV091ShotsDpr = 3.0;
String get outTiles => '$root/tiles';
String get outCards => '$root/cards';
SharedPreferences? sharedPrefsOrNull;
SharedPreferences get _sharedPrefs {
  final p = sharedPrefsOrNull;
  if (p == null) {
    throw StateError(
      'SharedPreferences noch nicht initialisiert - '
      'sharedPrefsOrNull wird in pump() gesetzt',
    );
  }
  return p;
}

bool _fontsLoaded = false;
Future<void> loadFontsOnce() async {
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
  await bestEffort('FontLoader.load', () async {
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
  });
  // Emoji (31.10.2026): Die Startseite begruesst mit "Hallo, du! <Emoji>".
  // Ohne Emoji-Schrift zeichnet der Test ein leeres Kaestchen - im
  // Store-Listing sieht das nach einem Fehler aus. Die Schrift ist
  // optional: Fehlt sie (Linux ohne Noto-Color-Emoji), wird einfach
  // nichts nachgeladen - der Render laeuft dann eben mit dem
  // Kaestchen.
  for (final pfad in const [
    r'C:\Windows\Fonts\seguiemj.ttf', // Windows: Segoe UI Emoji
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf', // Linux
    '/System/Library/Fonts/Apple Color Emoji.ttc', // macOS
  ]) {
    final f = File(pfad);
    if (!f.existsSync()) continue;
    // Manche Systemschriften kann Flutter nicht laden - dann eben ohne.
    final geladen = await bestEffortOr('FontLoader.load', () async {
      final loader = FontLoader('Noto Color Emoji')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      return true;
    }, false);
    if (geladen) break;
  }
  _fontsLoaded = true;
}

class FakeLocalStorage implements LocalStorage {
  final map = <String, String>{};

  /// Der Chat-Hintergrund-Dialog darf im Store-Screenshot NICHT
  /// aufpoppen: er verdeckt den Chat, um den es geht ("Screenshot ist
  /// das Chat-Hintergrund Pop up vor dem Chat, was so nicht sein soll").
  ///
  /// Der Dialog erscheint, solange `chatBackgroundSeen` nicht gesetzt
  /// ist - der Store-Screenshot zeigt einen Geraet, auf dem der Nutzer
  /// die Auswahl schon getroffen hat.
  static const _settingsMitDialogGesehen =
      '{"chatBackgroundSeen":true,"blindModeEnabled":true}';
  @override
  Future<void> saveString(String key, String value) async => map[key] = value;
  @override
  Future<String?> getString(String key) async {
    if (key == AppConstants.prefsSettingsKey) return _settingsMitDialogGesehen;
    return map[key];
  }

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';
  @override
  Future<bool?> getBool(String key) async =>
      map[key] == null ? null : map[key] == 'true';
  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';
  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);
  @override
  Future<void> remove(String key) async => map.remove(key);
}

class FakeSecurePrefs extends SecurePreferencesStorage {
  final map = <String, String>{};
  @override
  Future<void> saveString(String key, String value) async => map[key] = value;
  @override
  Future<String?> getString(String key) async => map[key];
  @override
  Future<void> remove(String key) async => map.remove(key);
}

class FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String json) async {}
}

Widget harness(
  Widget child,
  SharedPreferences prefs, {
  List<Override> extra = const [],
  bool dark = false,
}) {
  // Card-SchattEN nur fuer den Store-Render abschalten: der Test-Rasterizer
  // zeichnet den Drop-Shadow als harte graue Kontur statt weich - im Play Store
  // sieht das nach einem Renderfehler aus ("grauer Rahmen"). Auf dem Geraet ist
  // der Schatten weich, die App selbst bleibt unveraendert.
  //
  // [dark] = true rendert den DUNKLEN Farbsatz. Das ist fuer die
  // Split-Kachel noetig (Hell und Dunkel auf einem Bild) - der
  // Store soll zeigen, dass die App in beiden Modi lesbar ist.
  final theme = dark
      ? AppTheme.dark(theme: ThestiaTheme.classic)
      : AppTheme.light(theme: ThestiaTheme.classic);
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(FakeSecureProfileStore()),
      sharedPrefsProvider.overrideWithValue(prefs),
      // Die Sprache. `L10n.t` liest localeProvider ueber den
      // L10nScope - dieser Override ist das, was den Screen wirklich
      // umschaltet. MaterialApp.locale allein aendert nur die
      // Material-Widgets (Datum, Zahlen), nicht die App-Texte.
      localeProvider.overrideWith((ref) => Locale(lang)),
      // Das Profil als VERIFIZIERT (NUTZERWUNSCH 31.10.2026: "Die Modi
      // sollen auf den Screenshots alle entsperrt sein (Nur im
      // Screenshot)").
      //
      // Derselbe Override erledigt zwei Aufgaben:
      //
      // 1. Die Modus-Kacheln (Find your Spark, Dating Hour, Transit
      //    Spark) sind gesperrt, solange das eigene Profil nicht
      //    verifiziert ist. Im Store-Bild sahen sie ausgegraut aus und
      //    trugen ein Schloss - das Bild zeigte damit einen Zustand,
      //    den ein Nutzer NICHT kennenlernen kann (der muss erst
      //    ein Video einreichen). Alle fuenf Modi sichtbar und
      //    bedienbar zu zeigen ist die ehrlichere Darstellung.
      //
      // 2. Die Startseite zeigte die Karte "Nicht verifiziert" mit dem
      //    Text "Fuer diesen Modus musst du dein Alter mit einem kurzen
      //    Video bestaetigen" - auf dem UEBERSCHRIFT des Bildes. Das
      //    war doppelt stoerend: die Karte nimmt die halbe Hoehe ein
      //    und erklaert etwas, das im Bild nicht gebraucht wird.
      //
      // Der Name bleibt leer - der Screenshot zeigt dadurch weiterhin
      // "Hallo, du!" statt eines erfundenen Namens.
      profileProvider.overrideWith((ref) {
        final notifier = ProfileNotifier(
          FakeLocalStorage(),
          FakeSecureProfileStore(),
        );
        notifier.setProfile(
          UserProfile(
            id: AppConstants.currentUserId,
            name: '',
            bio: '',
            // ERWACHSENEN-ALTER (03.11.2026).
            //
            // Ohne birthDate ist `profil.age` null, der Code rechnet dann
            // mit 0 - und 0 ist ein Minderjaehriger. Der Datenschutz-
            // Bildschirm zeigte deshalb die Jugendschutz-Variante
            // ("In deinem Alter bleibt die Entfernung aus"), waehrend
            // die Kachel-Ueberschrift das Verhalten von Erwachsenen
            // beschreibt ("erst, wenn du sie erlaubst: Stufen von
            // 10 km"). Zwei widersprechende Aussagen in EINEM Bild.
            //
            // Das Play-Listing richtet sich an Erwachsene (Zielgruppe
            // 18+, "Restrict Minor Access"). Das Bild zeigt darum einen
            // erwachsenen Nutzer - mit dem Text, den ER sieht.
            birthDate: DateTime(1994, 4, 12),
            isVerified: true,
            verificationState: VerificationState.verified,
          ),
        );
        return notifier;
      }),
      ...extra,
    ],
    // Der L10nScope steht UEBER dem MaterialApp: `L10n.t` sucht ihn
    // ueber den Kontext. Wer ihn weglässt, bekommt deutsche Texte in
    // einem englischen Listing.
    child: L10nScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          cardTheme: theme.cardTheme.copyWith(
            elevation: 0,
            shadowColor: const Color(0x00000000),
          ),
        ),
        locale: Locale(lang),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    ),
  );
}

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  required String outDir,
  required String name,
  required Size size,
  required double dpr,
  double textScale = 1.0,
  bool dark = false,
  Future<void> Function(WidgetTester)? after,
  List<Override> extra = const [],
}) async {
  await tester.runAsync(loadFontsOnce);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  // System-Insets eines echten Geraets setzen.
  //
  // Die Logik liegt in tool/store_screenshot_insets.dart, NICHT hier:
  // diese Datei ist gitignoriert, der Fix waere beim naechsten Checkout
  // verloren gegangen. Siehe dort, warum es ueberhaupt noetig ist -
  // ohne Insets setzt SafeArea im flutter_test nichts und der Render
  // zeigt die App ohne Statusleiste.
  applyStoreInsets(tester.view);
  addTearDown(() => resetStoreInsets(tester.view));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  sharedPrefsOrNull = prefs;
  // Ohne Mock zeigt die Fusszeile "Version ." - im Store wuerde das wie ein
  // Platzhalter aussehen.
  //
  // Version und Build werden aus pubspec.yaml GELESEN, nicht hier
  // festgeschrieben. Festgeschriebene Werte sind bei jedem Release
  // stillschweigend veraltet - so stand hier bis v0.9.2 "0.9.1" im
  // Store-Login-Screenshot, waehrend bereits 0.9.2 ausgeliefert wurde.
  final pub = readPubspecVersionSync();
  PackageInfo.setMockInitialValues(
    appName: 'Thestia',
    packageName: 'com.thestia.app',
    version: pub.version,
    buildNumber: pub.build,
    buildSignature: '',
  );
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );
  await tester.pumpWidget(
    MediaQuery(
      // Nur fuer Screens, die sonst ueber den unteren Rand hinauslaufen
      // (Entdecken-Liste): echtes UI, kompakter gesetzt.
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: harness(child, prefs, extra: extra, dark: dark),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
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

Future<void> wegtippeVerbindungshinweis(WidgetTester tester) async {
  // Der Text kommt aus der App: 'chat.relayBannerShort'.
  final hinweis = storeV091ShotsT('Kein P2P m\u{f6}glich', 'No P2P available');
  final text = find.text(hinweis);
  if (text.evaluate().isEmpty) return; // nichts zu tun
  // Der Knopf sitzt in derselben Karte wie der Text.
  final karte = find.ancestor(of: text, matching: find.byType(Card));
  final knopf = find.descendant(of: karte, matching: find.byIcon(Icons.close));
  if (knopf.evaluate().isEmpty) return;
  await tester.tap(knopf.first);
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  expect(
    find.text(hinweis),
    findsNothing,
    reason: 'Der Verbindungs-Hinweis muss im Store-Bild weg sein.',
  );
}

({String version, String build}) readPubspecVersionSync() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    throw StateError(
      'pubspec.yaml nicht gefunden - Screenshots nur aus dem '
      'Repository-Root erzeugen.',
    );
  }
  for (final line in file.readAsLinesSync()) {
    final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)\s*$').firstMatch(line);
    if (m != null) return (version: m.group(1)!, build: m.group(2)!);
  }
  throw StateError(
    'Kein "version: x.y.z+build" in pubspec.yaml gefunden - '
    'Screenshot-Renderer kann die Version nicht ermitteln.',
  );
}

void noop(String _) {}
Widget anpassenScreen(String erscheinung) {
  // Die Ueberschriften sind im echten Screen L10n-Keys
  // ('settings.colors' = Farbwelt/Color scheme,
  // 'settings.chatBg' = Chat-Hintergrund/Chat background). Hier steht
  // die kurzere Fassung, damit sie im Bild Platz haben.
  return Builder(
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(storeV091ShotsT('Erscheinungsbild', 'Appearance')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              storeV091ShotsT('Farbschema', 'Color scheme'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ThemePicker(selectedName: 'classic', onChanged: (_) {}),
            const SizedBox(height: 16),
            Text(
              storeV091ShotsT('Erscheinung', 'Light or dark'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            AppearanceSelector(value: erscheinung, onChanged: noop),
            const SizedBox(height: 16),
            Text(
              storeV091ShotsT('Chat-Hintergrund', 'Chat background'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const ChatBackgroundPicker(),
          ],
        ),
      ),
    ),
  );
}

void noopTheme(ThestiaTheme _) {}
void storeV091ShotsShot(
  String name,
  Widget Function() build, {
  double textScale = 1.0,
  Future<void> Function(WidgetTester)? after,
}) {
  for (final entry in sizes.entries) {
    testWidgets('$name [${entry.key}]', (tester) async {
      await pump(
        tester,
        build(),
        outDir: '$root/${entry.key}',
        name: name,
        size: entry.value.size,
        dpr: entry.value.dpr,
        textScale: textScale,
        after: after,
      );
    }, skip: !enabled);
  }
}

void shotDark(String name, Widget Function() build) {
  testWidgets('$name [dunkel]', (tester) async {
    await pump(
      tester,
      build(),
      outDir: '$root/phone',
      name: name,
      size: storeV091ShotsPhone,
      dpr: storeV091ShotsDpr,
      dark: true,
    );
  }, skip: !enabled);
}

const List<String> modeOrder = [
  'findMatch', // Find your Match
  'datingHour', // Dating Hour (Event)
  'randomChat', // Zufallschat
  'qrScan', // QR-Code scannen
  'transitSpark', // Transit Spark
];
Widget soleTileHost(Card card) {
  final theme = AppTheme.light(theme: ThestiaTheme.classic);
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(FakeSecureProfileStore()),
      sharedPrefsProvider.overrideWithValue(_sharedPrefs),
      localeProvider.overrideWith((ref) => Locale(lang)),
    ],
    child: L10nScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: Locale(lang),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          // Die Kachel darf die View NICHT fuellen. Im Listen-Kontext
          // bestimmt ihr Inhalt die Hoehe; hier wuerde sie sonst
          // gestreckt und das Icon landete unten. Column mit
          // mainAxisSize.min erzwingt die Inhaltshoehe.
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [card],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget cardHost(Widget child, {double maxWidth = 340}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

Directory outCardsDir() =>
    Directory('${Directory.current.path}/test/screenshots/$outCards');
String? tileName(Widget? title) {
  final data = title is Text ? title.data : null;
  if (data == null || data.trim().isEmpty) return null;
  return data
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

Future<void> writeCardList(
  WidgetTester tester,
  String screen,
  Map<String, Map<String, Object>> cards,
) async {
  final file = File('${outCardsDir().path}/rects_$screen.json');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cards), flush: true);
  });
}

Future<void> writeCardRects(
  WidgetTester tester,
  String screen,
  Map<String, Rect> rects,
) async {
  final file = File('${outCardsDir().path}/rects_$screen.json');
  final payload = <String, List<double>>{};
  rects.forEach((name, r) {
    payload[name] = [r.left, r.top, r.width, r.height];
  });
  // Das Schreiben muss in runAsync. flutter_test laeuft in einer
  // FakeAsync-Zone: ein echtes Dateisystem-Versprechen wird dort nie
  // fertig, und der Test haengt bis zum 10-Minuten-Timeout. Genau das
  // war die Ursache der Timeouts beim ersten Versuch.
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  });
}

List<Finder> findModeCards(WidgetTester tester) {
  final out = <Finder>[];
  for (final name in modeOrder) {
    final f = find.byKey(ValueKey('mode-tile-$name'));
    expect(
      f,
      findsOneWidget,
      reason:
          "Modus '$name' nicht gefunden - der Key in _ModeCard "
          'passt nicht zum Enum-Namen',
    );
    out.add(f);
  }
  return out;
}

Future<void> vorbereiteChatSpeicher(WidgetTester tester) async {
  final hiveDir = Directory.systemTemp.createTempSync('thestia_store_chat');
  Hive.init(hiveDir.path);
  addTearDown(() {
    // Dateikoepfe bleiben unter Windows gern kurz offen - fuer
    // einen Temp-Ordner ist das kein Fehler.
    bestEffortSync('hiveDir.deleteSync', () {
      hiveDir.deleteSync(recursive: true);
    });
  });
  const secure = MethodChannel(
    'plugins.it_nomads.com/'
    'flutter_secure_storage',
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    secure,
    (call) async => switch (call.method) {
      'read' => null,
      'write' || 'delete' => true,
      'containsKey' => false,
      _ => null,
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secure,
      null,
    ),
  );
}

class FakeChatService extends ChatService {
  FakeChatService(this.storeV091ShotsPartner, this.storeV091ShotsMessages);
  final UserProfile storeV091ShotsPartner;
  final List<Message> storeV091ShotsMessages;
  @override
  List<Match> getMatches() => [
    Match(
      id: 'store-shot-match',
      partner: storeV091ShotsPartner,
      matchedAt: DateTime(2026, 1, 1),
    ),
  ];
  @override
  Match? getMatchById(String matchId) =>
      matchId == 'store-shot-match' ? getMatches().first : null;
  @override
  List<Message> getMessages(String matchId) =>
      matchId == 'store-shot-match' ? storeV091ShotsMessages : const [];
}

UserProfile chatPartner() => UserProfile(
  id: 'store-shot-peer',
  name: 'Mara',
  bio: storeV091ShotsT('Bücher, Rad, Kaffee.', 'Books, bikes, coffee.'),
  state: 'Nordrhein-Westfalen',
  interests: lang == 'en'
      ? const ['Photography', 'Hiking', 'Cooking']
      : const ['Fotografieren', 'Wandern', 'Kochen'],
  isVerified: true,
  introText: storeV091ShotsT(
    'Erzähl mir etwas, das nicht auf deinem Profil steht.',
    'Tell me something that is not on your profile.',
  ),
);
List<Message> chatHistory() {
  final now = DateTime(2026, 1, 2, 20, 15);
  Message m(String id, String from, String text, int min) => Message(
    id: id,
    senderId: from,
    receiverId: from == 'me' ? 'store-shot-peer' : 'me',
    text: text,
    timestamp: now.add(Duration(minutes: min)),
  );
  // 'me' ist die Demo-ID, die AppConstants.currentUserId ohne
  // Supabase-Session zurueckgibt. Nachrichten mit dieser Absender-ID
  // landen auf der eigenen Seite, die anderen beim Partner.
  // Absurder und nicht/generischer Chat-Inhalt fuer den Store-Screenshot.
  //
  // "Hey, schreib mir" verkauft eine App nicht. Der Text soll zeigen,
  // dass hier Menschen miteinander reden und nicht miteinander
  // ausfuellen - und er soll auf den ersten Blick ungewoehnlich genug
  // sein, dass jemand innehaelt und weiterklickt.
  //
  // Bewusst ohne Schwaeren ("Kaffee am Wochenende?") - der Screenshot
  // soll Spass machen, nicht kraenkend sein.
  //
  // Die letzte Nachricht beantwortet die davor ("Gewinnst du meistens?")
  // und bleibt im selben Thema. Ein Themenwechsel auf eine Date-Einladung
  // an der letzten Zeile wirkt, als haette man den Faden verloren - und
  // genau so gelesen wird das Bild zuerst.
  return [
    m(
      '1',
      'store-shot-peer',
      storeV091ShotsT(
        'Ich muss dir was Beunruhigendes sagen.',
        'I have to tell you something unsettling.',
      ),
      0,
    ),
    m(
      '2',
      'me',
      storeV091ShotsT('Jetzt bin ich neugierig.', 'Now I am curious.'),
      2,
    ),
    m(
      '3',
      'store-shot-peer',
      storeV091ShotsT(
        'Ich verhandle nachts mit meinem Toaster.',
        'I negotiate with my toaster at night.',
      ),
      4,
    ),
    m(
      '4',
      'me',
      storeV091ShotsT('Gewinnst du meistens?', 'Do you usually win?'),
      6,
    ),
    m(
      '5',
      'store-shot-peer',
      storeV091ShotsT(
        'Selten. Er akzeptiert nur exakt zwei Scheiben.',
        'Rarely. It accepts exactly two slices.',
      ),
      8,
    ),
  ];
}
