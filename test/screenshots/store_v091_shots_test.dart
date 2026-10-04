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
import 'support/store_screenshot_insets.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/models/match.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/screens/spice/spice_questions_screen.dart';
import 'package:thestia/screens/swipe/swipe_mode_selection_screen.dart';
import 'package:thestia/screens/welcome/welcome_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/widgets/appearance_selector.dart';
import 'package:thestia/widgets/app_logo.dart';
import 'package:thestia/widgets/chat_background_picker.dart';
import 'package:thestia/widgets/theme_picker.dart';

/// Ohne STORE_SHOTS=1 werden diese Tests uebersprungen (kein Goldens-Vergleich
/// in der normalen Testsuite).
final bool _enabled = Platform.environment.containsKey('STORE_SHOTS');

// Zielaufloesung der App-Screens: echtes Smartphone-Seitenverhaeltnis
// (1080x2400 = 20:9). Die Komposition in
// tool/make_store_screenshots.py verwendet genau diese Quelle.
const _sizes = <String, ({Size size, double dpr})>{
  'phone': (size: Size(1080, 2400), dpr: 3.0),
};

/// Aufloesung fuer die einzeln exportierten Modus-Kacheln.
///
/// 1080 breit, damit eine Kachel in voller Geraetebreite liegt - sie
/// wird im Store nicht verkleinert dargestellt, sondern nur einzeln
/// auf dem Verlauf verteilt. dpr 3 wie beim Screen, damit Text und
/// Icons dieselbe Schriftgroesse haben.
const Size _phone = Size(1080, 2400);
const double _dpr = 3.0;

/// Zielordner der einzelnen Kacheln. make_store_screenshots.py liest
/// daraus und setzt sie auf dem Verlauf zusammen.
const String outTiles = 'store_v091/tiles';

/// Zielordner fuer die Kacheln der Screens 01, 02, 04 und 05.
///
/// Anders als [outTiles] sind das KEINE gerenderten Einzelkacheln,
/// sondern vollstaendige Screens plus rects.json. Der Aufbau ist fuer
/// diese Screens nicht "eine Kachel pro Widget", sondern "die echten
/// Widgets des Screens an Ort und Stelle". Deshalb wird nichts
/// umgebaut und nichts nachgeschnitten: rects.json sagt, welcher
/// Bildbereich zu welcher Karte gehoert.
const String outCards = 'store_v091/cards';

/// SharedPreferences-Instanz fuer die Einzel-Exporte.
///
/// Wird in _pump() gesetzt, sobald die Mocks eingerichtet sind - dort
/// wird SharedPreferences.getInstance() ohnehin schon aufgerufen.
SharedPreferences? _sharedPrefsOrNull;

/// Zugriff auf die gesetzte Instanz; [_soleTileHost] laeuft nach _pump().
SharedPreferences get _sharedPrefs {
  final p = _sharedPrefsOrNull;
  if (p == null) {
    throw StateError('SharedPreferences noch nicht initialisiert - '
        '_sharedPrefsOrNull wird in _pump() gesetzt');
  }
  return p;
}

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

Widget _harness(Widget child, SharedPreferences prefs,
    [List<Override> extra = const []]) {
  // Card-SchattEN nur fuer den Store-Render abschalten: der Test-Rasterizer
  // zeichnet den Drop-Shadow als harte graue Kontur statt weich - im Play Store
  // sieht das nach einem Renderfehler aus ("grauer Rahmen"). Auf dem Geraet ist
  // der Schatten weich, die App selbst bleibt unveraendert.
  final theme = AppTheme.light(theme: ThestiaTheme.classic);
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(_FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
      sharedPrefsProvider.overrideWithValue(prefs),
      ...extra,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        cardTheme: theme.cardTheme.copyWith(elevation: 0, shadowColor: const Color(0x00000000)),
      ),
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
  double textScale = 1.0,
  Future<void> Function(WidgetTester)? after,
  List<Override> extra = const [],
}) async {
  await tester.runAsync(_loadFontsOnce);
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
  _sharedPrefsOrNull = prefs;
  // Ohne Mock zeigt die Fusszeile "Version ." - im Store wuerde das wie ein
  // Platzhalter aussehen.
  //
  // Version und Build werden aus pubspec.yaml GELESEN, nicht hier
  // festgeschrieben. Festgeschriebene Werte sind bei jedem Release
  // stillschweigend veraltet - so stand hier bis v0.9.2 "0.9.1" im
  // Store-Login-Screenshot, waehrend bereits 0.9.2 ausgeliefert wurde.
  final pub = _readPubspecVersionSync();
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
      child: _harness(child, prefs, extra),
    ),
  );
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

/// Liest `version: x.y.z+build` aus pubspec.yaml.
///
/// Bewusst aus der Datei statt aus PackageInfo: im Test laeuft kein
/// gebautes Artefakt, PackageInfo wuerde hier nichts liefern. So
/// stimmen die Store-Screenshots per Konstruktion mit der Version
/// ueberein, die tatsaechlich ausgeliefert wird.
({String version, String build}) _readPubspecVersionSync() {
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


/// No-op-Callback fuer gerenderte Auswahl-Widgets.
void _noop(String _) {}

/// No-op-Callback fuer [ThemePicker], der ein [ThestiaTheme] liefert.
void _noopTheme(ThestiaTheme _) {}

/// Registriert einen Screen in beiden Aufloesungen.
void _shot(
  String name,
  Widget Function() build, {
  double textScale = 1.0,
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
        textScale: textScale,
        after: after,
      );
    }, skip: !_enabled);
  }
}

/// Die Reihenfolge der Modi im Screen, wie in
/// `swipe_mode_selection_screen.dart` deklariert.
///
/// `DiscoveryMode` ist ein privates Enum in der Screen-Datei und von hier
/// aus nicht importierbar. Die Reihenfolge wird deshalb als Konstante
/// gespiegelt und jeder Eintrag einzeln geprueft - kommt in der App ein
/// Modus dazu, schlaegt der Test fehl statt die Kachel stillschweigend
/// wegzulassen. In einem Zwischenstand stand hier
/// 'mode-tile-findYourMatch' statt 'mode-tile-findMatch', wodurch die
/// erste Kachel im Screenshot fehlte.
const List<String> _modeOrder = [
  'findMatch', // Find your Match
  'datingHour', // Dating Hour (Event)
  'randomChat', // Zufallschat
  'qrScan', // QR-Code scannen
  'transitSpark', // Transit Spark
];

/// Rendert eine einzelne Modus-Kachel als einziges Widget.
///
/// Noetig, weil matchesGoldenFile den VORAHEN-Frame erfasst: auf dem
/// vollstaendigen Screen umfasst das die ganze Gruppe (Ueberschrift
/// plus alle Kacheln darunter). Allein in einem Scaffold ist die
/// Karte das einzige Kind und der Export ist damit wirklich die
/// Kachel.
///
/// Die Kachel wird NICHT nachgebaut - das Widget kommt unveraendert
/// aus dem gerenderten Screen.
Widget _soleTileHost(Card card) {
  final theme = AppTheme.light(theme: ThestiaTheme.classic);
  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(_FakeLocalStorage()),
      securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
      secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
      sharedPrefsProvider.overrideWithValue(_sharedPrefs),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('de'),
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
  );
}

/// Karte fuer den Kachel-Aufbau der Store-Screens: echter Inhalt auf
/// leuchtendem Grund, ohne Geraeterahmen.
///
/// KEIN eigenes MaterialApp: _pump() haengt den Kindbaum in _harness(),
/// und das bringt schon eines mit. Ein zweites wuerde den Capture
/// unmoeglich machen ("matched too many widgets").
///
/// Anders als [_soleTileHost] wird hier nichts gestreckt: der Inhalt
/// behaelt seine natuerliche Hoehe und steht auf dem Hintergrund. Das
/// ist die Form, in der die Kachel spaeter erscheint.
Widget _cardHost(Widget child, {double maxWidth = 340}) {
  return Builder(builder: (context) {
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
  });
}

/// Zielverzeichnis fuer die Rechteck-Dateien, ABSOLUT aufgeloest.
///
/// `matchesGoldenFile` loest seinen Pfad relativ zur Testdatei auf, ein
/// `File('store_v091/...')` dagegen relativ zum Prozessordner - das ist
/// die Package-Wurzel. Die Rechtecke landeten dadurch in
/// `<wurzel>/store_v091/cards/` statt neben den Bildern in
/// `test/screenshots/store_v091/cards/`, und make_store_screenshots.py
/// fand sie nicht.
///
/// Darum wird derselbe Zielordner wie bei den Bildern hier ausdruecklich
/// gebildet: Package-Wurzel plus test/screenshots/.
Directory _outCardsDir() =>
    Directory('${Directory.current.path}/test/screenshots/$outCards');

/// Stabiler Name einer Kachel aus deren Text.
///
/// Aus dem ExpansionTile-Titel, nicht aus der Position. Siehe die
/// Begruendung beim Export von 05.
String? _tileName(Widget? title) {
  final data = title is Text ? title.data : null;
  if (data == null || data.trim().isEmpty) return null;
  return data
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Schreibt eine Liste von Kacheln als JSON.
///
/// Anders als [_writeCardRects] traegt jede Kachel ihren Screenshot mit
/// sich: bei 05 wird ueber die Liste gescrollt, und eine Kachel kann nur
/// aus dem Bild geschnitten werden, in dem sie vollstaendig stand.
Future<void> _writeCardList(
  WidgetTester tester,
  String screen,
  Map<String, Map<String, Object>> cards,
) async {
  final file = File('${_outCardsDir().path}/rects_$screen.json');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cards), flush: true);
  });
}

/// Schreibt die Rechtecke der Kacheln eines Screens als JSON.
///
/// EINE Datei je Screen (`rects_<name>.json`). Eine gemeinsame Datei
/// wuerde beim zweiten Screen ueberschrieben - die Kacheln von 04
/// entstuenden dann aus dem Rechteck-Bild von 01.
///
/// `rects` in LOGISCHEN Pixeln; make_store_screenshots.py rechnet mit
/// 3.0 auf physische Pixel um, weil der Screenshot in physischen
/// Pixeln aufgenommen wird.
Future<void> _writeCardRects(
  WidgetTester tester,
  String screen,
  Map<String, Rect> rects,
) async {
  final file = File('${_outCardsDir().path}/rects_$screen.json');
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


/// Findet die Modus-Kacheln im gerenderten Screen, in Bildschirmreihenfolge.
///
/// Die Kacheln tragen in der App den Key `mode-tile-<name>`.
///
/// Bewusst KEIN Nachbau des Kachel-Layouts: exportiert wird die echte
/// Card aus dem tatsächlich gerenderten Baum. Genau das war beim
/// SegmentedButton-Fall der Fehler - im Screenshot stand ein Widget,
/// das es in der App nicht gab.
List<Finder> _findModeCards(WidgetTester tester) {
  final out = <Finder>[];
  for (final name in _modeOrder) {
    final f = find.byKey(ValueKey('mode-tile-$name'));
    expect(f, findsOneWidget,
        reason: "Modus '$name' nicht gefunden - der Key in _ModeCard "
            'passt nicht zum Enum-Namen');
    out.add(f);
  }
  return out;
}

/// ChatService mit erfundenem Match und erfundenem Verlauf.
///
/// Der Chat-Screen liest aus dem echten [ChatService], der aus Supabase
/// fuellt. Im Test gibt es keine Verbindung, also waere der Screen leer -
/// und ein leerer Chat ist als Store-Bild wertlos.
///
/// Ueberschrieben werden nur [getMatches] und [getMessages].
class _FakeChatService extends ChatService {
  _FakeChatService(this._partner, this._messages);

  final UserProfile _partner;
  final List<Message> _messages;

  @override
  List<Match> getMatches() => [
        Match(
          id: 'store-shot-match',
          partner: _partner,
          matchedAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  Match? getMatchById(String matchId) =>
      matchId == 'store-shot-match' ? getMatches().first : null;

  @override
  List<Message> getMessages(String matchId) =>
      matchId == 'store-shot-match' ? _messages : const [];
}

UserProfile _chatPartner() => const UserProfile(
      id: 'store-shot-peer',
      name: 'Mara',
      bio: 'Bücher, Rad, Kaffee.',
      city: 'Köln',
      interests: ['Fotografieren', 'Wandern', 'Kochen'],
      isVerified: true,
      introText: 'Erzähl mir etwas, das nicht auf deinem Profil steht.',
    );

List<Message> _chatHistory() {
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
  return [
    m('1', 'store-shot-peer', 'Hey! Dein Profil hat mich neugierig gemacht.', 0),
    m('2', 'me', 'Gern. Was hat dich neugierig gemacht?', 2),
    m('3', 'store-shot-peer',
        'Dass du offen schreibst, was du wirklich suchst.', 4),
    m('4', 'me', 'Das ist der Punkt. Andernfalls verabredet man sich aus '
        'Höflichkeit und merkt erst beim Treffen, dass es nicht passt.', 6),
    m('5', 'store-shot-peer', 'Das kenne ich. Also: Kaffee am Wochenende?', 8),
  ];
}

void main() {
  // 0) Kachel-Export fuer den Aufbau OHNE Geraet.
  //
  //    Die Screens 01, 02, 04 und 05 sollen im Store nicht als
  //    Screenshot eines Screens erscheinen, sondern als KACHELN auf dem
  //    Markenverlauf - so wie 03_entdecken seine fuenf Moduskacheln hat.
  //
  //    Dafuer wird nicht das Layout nachgebaut, sondern jeder echte
  //    Widget-Bereich vermessen und als Rechteck notiert. Nachgebautes
  //    Layout driftet von der App; das war beim SegmentedButton-Fall die
  //    Ursache fuer ein Bild mit einem Widget, das es in der App nicht
  //    gab.
  //
  //    Gespeichert wird der vollstaendige Screen (physische Pixel) plus
  //    rects.json. make_store_screenshots.py schneidet daraus die
  //    Kacheln heraus - es braucht also keine Farberkennung, weil die
  //    Rechtecke exakt sind.
  if (_enabled) {
    testWidgets('export Kacheln 01 (Logo und Text)', (tester) async {
      await _pump(tester, const WelcomeScreen(),
          outDir: outCards, name: '01_willkommen', size: _phone, dpr: _dpr);
      final content = find.byKey(const Key('welcome-page-content'));
      expect(content, findsOneWidget,
          reason: 'der Key welcome-page-content fehlt in WelcomeScreen');
      // Das Rechteck ist die VEREINIGUNG von Logo, Titel und Text, nicht
      // die Column. Die Column fuellt den ganzen Seitenbereich
      // (mainAxisAlignment.center in einem Expanded), ihr Rechteck ist
      // deshalb 574 dp hoch und die Kachel wurde ein grosses weisses
      // Rechteck mit einem Fleck darin. Der weisse Rand kommt in
      // make_store_screenshots.py dazu (CARD_MARGIN_LOGICAL).
      final logo =
          find.descendant(of: content, matching: find.byType(AppLogo));
      expect(logo, findsOneWidget, reason: 'AppLogo nicht gefunden');
      final texts = find.descendant(of: content, matching: find.byType(Text));
      final boxes = <Rect>[
        tester.getRect(logo),
        for (final t in tester.widgetList(texts))
          tester.getRect(find.byWidget(t)),
      ];
      var box = boxes.first;
      for (final r in boxes.skip(1)) {
        box = box.expandToInclude(r);
      }
      await _writeCardRects(tester, '01_willkommen', {'willkommen_logo': box});
      // Kein eigener Capture: _pump() hat den Screenshot unter
      // $outCards/01_willkommen.png bereits geschrieben. Ein zweiter
      // Capture erzeugte nur eine doppelte PNG.
    });

    testWidgets('export Kacheln 04 (drei Auswahlkacheln)',
        (tester) async {
      // Die drei Widgets werden einzeln in einen Host gehaengt und
      // vermessen. Sie sind ausgelagerte Widgets und in der App noch
      // nicht in einen Screen eingebaut - siehe die Anmerkung in
      // compose_cards() dazu.
      //
      // Adressiert wird ueber den WIDGET-Typ, nicht ueber `Card`: keines
      // der drei baut eine Card. ThemePicker ist ein Wrap, die beiden
      // anderen Column bzw. GridView. Ein `find.byType(Card)` lieferte
      // "No element".
      final cards = <String, Map<String, Object>>{};
      for (final entry in <String, Widget>{
        'anpassen_farbschema': const ThemePicker(
            selectedName: 'classic', onChanged: _noopTheme),
        'anpassen_erscheinung':
            const AppearanceSelector(value: 'light', onChanged: _noop),
        'anpassen_chat': const ChatBackgroundPicker(),
      }.entries) {
        await _pump(tester, _cardHost(entry.value),
            outDir: outCards, name: entry.key, size: _phone, dpr: _dpr);
        final finder = find.byWidget(entry.value);
        expect(finder, findsOneWidget,
            reason: '${entry.key}: Widget nicht gefunden, Rect waere falsch');
        final r = tester.getRect(finder);
        cards[entry.key] = {
          'file': '${entry.key}.png',
          'rect': [r.left, r.top, r.width, r.height],
        };
      }
      // Einmal am Ende: _writeCardRects pro Durchlauf wuerde die Datei
      // bei jedem Widget ueberschreiben und am Ende nur noch das
      // Chat-Hintergrund-Rechteck enthalten.
      await _writeCardList(tester, '04_anpassen', cards);
    });

    testWidgets('export Kacheln 05 (alle Kategorien)', (tester) async {
      await _pump(tester, const SpiceQuestionsScreen(matchId: 1),
          outDir: outCards, name: '05_eisbrecher', size: _phone, dpr: _dpr);
      // Die Kategorien stehen in einem ListView.builder: gerendert wird
      // nur, was im Viewport liegt. Also wird durch die Liste gelaufen
      // und jede Kachel dann aufgenommen, wenn sie vollstaendig sichtbar
      // ist.
      //
      // Der Name kommt aus dem KACHELTEXT, nicht aus ihrer Position. Mit
      // einem Index als Namen war jede Kategorie nach dem Scrollen eine
      // andere: Index 0 war die erste sichtbare, nicht die erste
      // Kategorie. Die Liste enthielt am Ende acht Kacheln mit den
      // Namen kat_0 bis kat_7 statt der elf Kategorien.
      final list = find.byType(Scrollable).last;
      final cards = <String, Map<String, Object>>{};
      await tester.dragUntilVisible(
          find.byType(ExpansionTile).first, list, const Offset(0, 200));
      await tester.pumpAndSettle();

      for (var step = 0; step < 40; step++) {
        final tiles = find.byType(ExpansionTile);
        final found = tester.widgetList(tiles).length;
        var added = 0;
        for (var i = 0; i < found; i++) {
          final tile = tester.widget<ExpansionTile>(tiles.at(i));
          final name = _tileName(tile.title);
          if (name == null || cards.containsKey(name)) continue;
          final r = tester.getRect(tiles.at(i));
          final view = tester.view.physicalSize / tester.view.devicePixelRatio;
          if (r.top < 1 || r.bottom > view.height - 1) continue;
          cards[name] = {
            'file': '05_$step.png',
            'rect': [r.left, r.top, r.width, r.height],
          };
          added++;
        }
        if (added == 0) break; // nichts Neues mehr im Viewport

        await expectLater(find.byType(MaterialApp).last,
            matchesGoldenFile('$outCards/05_$step.png'));
        await _writeCardList(tester, '05_eisbrecher', cards);

        await tester.drag(list, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
    });
  }

  // 0b) Chat: ersetzt das Anmelde-Bild. Der Chat traegt das staerkste
  //      Versprechen der App und zeigt den Alltag, den die uebrigen
  //      Bilder nicht zeigen - 01 Willkommen, 03 Modi, 04 Personalisierung,
  //      05 Eisbrecher.
  if (_enabled) {
    testWidgets('export Kacheln 02 (Chat)', (tester) async {
      // Der Chat startet ueber EncryptionService die Signal-Boxen, und
      // SecureHive holt seinen Schluessel direkt aus dem
      // flutter_secure_storage-Plugin - nicht ueber die Provider-
      // Attrappe des Harness. Im Test gibt es dafuer keine
      // Implementierung, also bricht initialize() mit
      // MissingPluginException ab.
      //
      // Der Kanal wird deshalb hier als leerer Speicher beantwortet:
      // read -> null (kein Schluessel hinterlegt), write/delete -> true.
      // Das entspricht einem frisch installierten Geraet.
      // Hive braucht einen Pfad fuer die verschluesselten Boxen
      // (Identity-Key, PreKeys, Session-Ratchet). Im Test geht das in
      // ein temporaeres Verzeichnis.
      final hiveDir =
          Directory.systemTemp.createTempSync('thestia_store_chat');
      Hive.init(hiveDir.path);
      addTearDown(() {
        try {
          hiveDir.deleteSync(recursive: true);
        } catch (_) {
          // Dateienkoepfe bleiben unter Windows gern kurz offen - fuer
          // einen Temp-Ordner ist das kein Fehler.
        }
      });

      const secure = MethodChannel('plugins.it_nomads.com/'
          'flutter_secure_storage');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secure,
        (call) async => switch (call.method) {
          'read' => null,
          'write' || 'delete' => true,
          'containsKey' => false,
          _ => null,
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, null));

      // Auch in den Phone-Ordner: make_store_screenshots.py liest den
      // Store-Screen 02 von dort, nicht aus cards/. Beide Aufrufe
      // nutzen denselben Provider-Override - ohne ihn waere der Screen
      // in einem der beiden Ordner leer.
      await _pump(
        tester,
        const ChatDetailScreen(matchId: 'store-shot-match'),
        outDir: 'store_v091/phone',
        name: '02_chat',
        size: _phone,
        dpr: _dpr,
        extra: [
          chatServiceProvider.overrideWithValue(
              _FakeChatService(_chatPartner(), _chatHistory())),
        ],
      );
      await _pump(
        tester,
        const ChatDetailScreen(matchId: 'store-shot-match'),
        outDir: outCards,
        name: '02_chat',
        size: _phone,
        dpr: _dpr,
        extra: [
          chatServiceProvider.overrideWithValue(
              _FakeChatService(_chatPartner(), _chatHistory())),
        ],
      );
      expect(find.byType(ChatDetailScreen), findsOneWidget);
      expect(find.text('Mara'), findsWidgets,
          reason: 'der Partner-Name fehlt - die Attrappe greift nicht');
    });
  }

  // 1) Willkommen: das Versprechen der App (Persönlichkeit vor Aussehen).
  _shot('01_willkommen', () => const WelcomeScreen());

  // 2) Anmelden/Registrieren: KEIN Store-Screenshot mehr.
  //
  //    Bis v0.9.2 war das Bild 02 ("Erst prüfen, dann freischalten").
  //    Es zeigt ein Formular - etwas, das man genau einmal macht, und
  //    damit den schwächsten der fuenf Bilder. Ersetzt durch 02_chat.
  //
  //    Der Screen wird hier NICHT mehr gerendert. Das ist Absicht: ein
  //    Export, den niemand im Store braucht, wird auch nicht gepflegt,
  //    und make_store_screenshots.py laesst nichts mehr von ihm
  //    unerwartet im Fastlane-Ordner auftauchen.

  // 3) Entdecken: die fuenf Modus-Kacheln, einzeln exportiert.
  //
  //    v0.9.2, zweiter Durchgang: der Screenshot zeigte den kompletten
  //    Screen in einem Geraet, wodurch die fuenf Modi nur durch
  //    Verkleinern der Schrift (textScale 0.64) alle sichtbar wurden -
  //    und die Schrift dadurch kleiner war als in den anderen Bildern.
  //
  //    Jetzt: KEIN Screen, KEIN Geraet. Jede echte Modus-Kachel wird
  //    einzeln in ein eigenes PNG geschrieben und in
  //    compose_modes() einzeln auf den Markenverlauf verteilt. Jede
  //    Kachel behält Originalgroesse und Originaltext, nichts wird
  //    skaliert, alles ist in voller Schriftgroesse sichtbar.
  //
  //    Der Modus-Screen wird dazu einmal gerendert und die echten
  //    _ModeCard-Widgets werden herausgeloest. Das Layout NICHT
  //    nachbauen - ein nachgebautes Layout driftet von der App. Genau
  //    das war der Fehler beim SegmentedButton-Fall.
  if (_enabled) {
    testWidgets('export 03_entdecken Kacheln', (tester) async {
      // Die View bleibt 1080x2400 bei dpr 3, also logisch 360x800 - die
      // Groesse, in der die App die Kachel auf einem Telefon zeigt.
      // Aufloesung kommt nicht ueber eine groessere logische View: dann
      // bricht der Text nicht mehr um, die Kachel wird flacher (88 statt
      // 92 px hoch) und zeigt etwas anderes als die App. Sie kommt
      // ueber den Capture-Finder, siehe unten.
      await _pump(tester, const SwipeModeSelectionScreen(),
          outDir: outTiles, name: 'screen', size: _phone, dpr: _dpr);
      final cards = _findModeCards(tester);
      expect(cards.length, _modeOrder.length,
          reason: 'jeder Entdeckungs-Modus muss exportiert werden');

      // WICHTIG: alle Kacheln VOR dem Umbau als Widgets materialisieren.
      // Sobald einmal ein neues Widget gerendert wird, ist der alte
      // Screen weg und die restlichen Finder liefern kein Element mehr
      // ("Bad state: No element").
      final widgets = <Card>[];
      for (final f in cards) {
        widgets.add(tester.element(f).widget as Card);
      }

      for (var i = 0; i < widgets.length; i++) {
        // Jede Kachel einzeln in ein eigenes Scaffold heben und dort als
        // einziges Widget rendern - nur so ist der Export wirklich EINE
        // Kachel. Ein Capture auf find.byKey(card.key!) erfasst auf dem
        // vollstaendigen Screen die ganze Gruppe mit Ueberschrift und
        // Nachbarkacheln.
        //
        // Der Capture laeuft bewusst ueber find.byType(MaterialApp).last und
        // NICHT ueber die Kachel selbst: ein Finder-Capture auf ein
        // einzelnes Widget schreibt LOGISCHE Pixel (312 px breite
        // Kachel in einer 360x800-PNG), der Capture der ganzen View
        // schreibt physische (1080x2400). Genau diese 312 px wurden
        // in compose_modes() auf 830 px hochskaliert - Faktor 2,66,
        // das war die Pixeligkeit in 03_entdecken.
        //
        // Die Datei enthaelt also die ganze View mit Scaffold-Rand um
        // die Kachel. make_store_screenshots.py schneidet sie ueber
        // exaktes Weiss heraus (_crop_tile) und ist damit
        // aufloesungsunabhaengig.
        final card = widgets[i];
        await tester.pumpWidget(_soleTileHost(card));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp).last,
          matchesGoldenFile('$outTiles/tile_$i.png'),
        );
      }
    });
  }

  _shot('03_entdecken', () => const Placeholder());

  // 4) Anpassen: Farbschemata, Erscheinungsmodus UND Chat-Hintergrund
  //    auf einer Seite - zeigt die generelle Personalisierbarkeit.
  //
  //    v0.9.2: Hier stand vorher ein handgebautes SegmentedButton, das es
  //    in der App NICHT gab - die Einstellungen nutzten drei
  //    SelectableTile-Radiozeilen. Der Screenshot zeigte damit eine
  //    Oberflaeche, die kein Nutzer je gesehen hat.
  //
  //    Jetzt werden ausschliesslich die echten, in der App verwendeten
  //    Widgets gerendert. Wer das Layout hier nachbaut, erzeugt wieder
  //    ein Mockup - das ist genau der Fehler, den dieser Block behalten
  //    hat. Die Ueberschriften stehen als Text darueber, weil sie in der
  //    App aus dem umgebenden Screen kommen.
  //
  //    v0.9.2: textScale war 0.72. Damit war die Schrift kleiner als in
  //    den anderen Screens - auf dem Store fiel der Unterschied sofort
  //    auf. Jetzt 1.0 fuer alle Screens. Der Preis: bei 1.0 passt nicht
  //    alles auf eine Seite. Statt zu verkleinern wird die Liste so
  //    gesetzt, dass die beiden wichtigsten Abschnitte sichtbar sind -
  //    Farbschema oben, Erscheinungsmodus darunter, Chat-Hintergrund
  //    angetippt am unteren Rand (so sieht es beim Scrollen aus).
  _shot('04_anpassen', () => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erscheinungsbild')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Farbschema',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ThemePicker(selectedName: 'classic', onChanged: (_) {}),
                const SizedBox(height: 16),
                Text('Erscheinung',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const AppearanceSelector(value: 'light', onChanged: _noop),
                const SizedBox(height: 16),
                Text('Chat-Hintergrund',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const ChatBackgroundPicker(),
              ],
            ),
          ),
        ),
      ));

  // 5) Eisbrecher-Fragen (Spice Questions): das Herzstueck im Chat.
  //    Erste Kategorie aufgeklappt, damit echte Fragen sichtbar sind.
  _shot('05_eisbrecher', () => const SpiceQuestionsScreen(matchId: 1),
      after: (tester) async {
        final tiles = find.byType(ExpansionTile);
        if (tester.widgetList(tiles).isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(milliseconds: 400));
        }
      });
}
