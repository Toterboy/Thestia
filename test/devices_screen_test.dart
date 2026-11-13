// Render-Tests fuer den Screen "Wo bin ich eingeloggt?".
//
// ANLASS: Der Screen zeigt alle Geraete, auf denen das Konto angemeldet
// ist, und kann alle anderen Sitzungen beenden. Er ist die Antwort auf
// die Frage "wer ist noch drin?" - und genau deshalb darf er keine
// Liste erfinden und keine Abmeldung vortaeuschen.
//
// Geprueft wird: kein Absturz, kein Render-Overflow, die Geraete stehen
// da (das aktuelle Geraet ist markiert), der leere Zustand, der
// Fehlerzustand mit Wiederholung, der Hinweis auf eine fehlgeschlagene
// Registrierung, das Neuladen ueber den Aktualisieren-Knopf und -
// wichtig - das Bestaetigungsdialog des "Ueberall abmelden".
//
// Der Server wird nicht angefasst: [DeviceSessionService] wird durch
// einen Hand-Fake ersetzt (siehe [_FakeDeviceService]). Nur die
// Supabase-Instanz wird initialisiert, damit der Bildschirm den
// Abmelde-Knopf ueberhaupt zeigt - es geht dabei KEINE Anfrage raus.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/device_session_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/screens/settings/devices_screen.dart';

/// In-Memory-Speicher - der Fake-Service braucht nur irgendetwas fuer
/// den Super-Konstruktor. Er wird nie benutzt.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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

/// Hand-Fake des Geraete-Service.
///
/// Der echte Service spricht mit der Datenbank - im Test gibt es
/// keinen Server. Der Fake beantwortet alles aus dem RAM und zaehlt
/// die Aufrufe, damit sichtbar wird, wann neu geladen wird.
class _FakeDeviceService extends DeviceSessionService {
  _FakeDeviceService(super.storage);

  /// Die Geraete, die der Screen anzeigen soll.
  List<DeviceSession> geraete = const [];

  /// Fehler, den [enrollCurrentDevice] werfen soll.
  Object? enrollFehler;

  /// Fehler, den [listDevices] werfen soll.
  Object? listenFehler;

  /// Fehler, den [logoutEverywhereExceptCurrent] werfen soll.
  Object? logoutFehler;

  /// Wie oft wurde das eigene Geraet registriert?
  int enrollAufrufe = 0;

  /// Wie oft wurde "Ueberall abmelden" ausgefuehrt?
  int logoutAufrufe = 0;

  /// Verzoegerung, mit der [listDevices] antwortet. Damit laesst sich
  /// der Ladezustand des Bildschirms beobachten.
  Duration antwortzeit = Duration.zero;

  @override
  Future<void> enrollCurrentDevice() async {
    enrollAufrufe++;
    final fehler = enrollFehler;
    if (fehler != null) throw fehler;
  }

  @override
  Future<List<DeviceSession>> listDevices() async {
    if (antwortzeit > Duration.zero) {
      await Future<void>.delayed(antwortzeit);
    }
    final fehler = listenFehler;
    if (fehler != null) throw fehler;
    return geraete;
  }

  @override
  Future<void> logoutEverywhereExceptCurrent() async {
    logoutAufrufe++;
    final fehler = logoutFehler;
    if (fehler != null) throw fehler;
  }
}

/// Baut eine Huelle um den Screen.
Widget _huelle(_FakeDeviceService service, {double scale = 1.0}) {
  return ProviderScope(
    overrides: [deviceSessionServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const DevicesScreen(),
      ),
    ),
  );
}

/// Setzt den Screen mit dem Fake auf und wartet, bis die Liste da ist.
Future<void> _pump(
  WidgetTester tester,
  _FakeDeviceService service, {
  double scale = 1.0,
}) async {
  await tester.pumpWidget(_huelle(service, scale: scale));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Der Bildschirm zeigt den Abmelde-Knopf nur, wenn Supabase
    // initialisiert ist ([SupabaseService.isInitialized]). Fuer den
    // Test wird der Client initialisiert - es geht dabei KEINE
    // Anfrage raus, der Geraete-Service ist ein Fake.
    //
    // autoRefreshToken: false - sonst laeuft ein periodischer Timer,
    // an dem der Test am Ende scheitern wuerde.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
      ),
    );
  });

  group('Angemeldete Geraete', () {
    testWidgets('zeigt die Geraete mit ihren Namen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          appVersion: '0.10.1',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
        DeviceSession(
          deviceId: 'b',
          deviceName: 'iPhone',
          platform: 'ios',
          deviceModel: 'Apple iPhone 15',
          lastSeenAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
          createdAt: DateTime.now().toUtc(),
        ),
      ];

      await _pump(tester, service);

      expect(tester.takeException(), isNull);
      expect(find.text('Angemeldete Geräte'), findsOneWidget);
      expect(find.text('Google Pixel 8'), findsOneWidget);
      expect(find.text('Apple iPhone 15'), findsOneWidget);
    });

    testWidgets('das aktuelle Geraet ist als solches markiert', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
      ];

      await _pump(tester, service);

      expect(
        find.textContaining('Dieses Gerät ·'),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, auf welchem Geraet er gerade sitzt - '
            'nur dort bleibt die Sitzung bestehen.',
      );
      // Das eigene Geraet bekommt ein Smartphone-Symbol, die anderen
      // ein neutrales "andere Geraete"-Symbol.
      expect(find.byIcon(Icons.smartphone), findsOneWidget);
      expect(find.byIcon(Icons.devices_other), findsNothing);
    });

    testWidgets('der Zeitpunkt der letzten Aktivitaet steht dabei', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
        DeviceSession(
          deviceId: 'b',
          deviceName: 'iPhone',
          platform: 'ios',
          deviceModel: 'Apple iPhone 15',
          lastSeenAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
          createdAt: DateTime.now().toUtc(),
        ),
        DeviceSession(
          deviceId: 'c',
          deviceName: 'Tablet',
          platform: 'android',
          deviceModel: 'Samsung Tab',
          lastSeenAt: DateTime.now().toUtc().subtract(const Duration(days: 4)),
          createdAt: DateTime.now().toUtc(),
        ),
      ];

      await _pump(tester, service);

      expect(find.textContaining('gerade aktiv'), findsOneWidget);
      expect(find.textContaining('aktiv vor 5 Std.'), findsOneWidget);
      expect(find.textContaining('zuletzt aktiv am'), findsOneWidget);
    });

    testWidgets('ohne weitere Geraete steht der Leerzustand da', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, _FakeDeviceService(_FakeLocalStorage()));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Keine weiteren Geräte'), findsOneWidget);
    });

    testWidgets('der Ladezustand verschwindet wieder', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      // Der Server braucht einen Moment - so ist der Ladezustand
      // ueberhaupt zu sehen.
      service.antwortzeit = const Duration(milliseconds: 100);

      await tester.pumpWidget(_huelle(service));
      await tester.pump();

      // Im ersten Frame wird noch geladen.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Keine weiteren Geräte'), findsOneWidget);
    });
  });

  group('Fehlerfaelle', () {
    testWidgets('ein Registrierungsfehler wird als Hinweis gezeigt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.enrollFehler = AppException('Kein Netz');
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
      ];

      await _pump(tester, service);

      expect(tester.takeException(), isNull);
      // Die Liste steht trotzdem da - der Fehler betrifft nur die
      // Registrierung des eigenen Geraets.
      expect(find.text('Google Pixel 8'), findsOneWidget);
      expect(find.textContaining('Kein Netz'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('ein Listenfehler zeigt den Fehlerzustand', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.listenFehler = AppException('Server nicht erreichbar');

      await _pump(tester, service);

      expect(tester.takeException(), isNull);
      expect(find.text('Server nicht erreichbar'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('"Erneut versuchen" laedt die Liste neu', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.listenFehler = AppException('Server nicht erreichbar');

      await _pump(tester, service);
      expect(service.enrollAufrufe, 1);

      // Der Server antwortet jetzt.
      service.listenFehler = null;
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
      ];

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();

      // Die Daten werden neu geladen ...
      expect(service.enrollAufrufe, 2);

      // ... aber BEFUND (13.11.2026, gefunden von diesem Test):
      // `_reload()` ruft `setState(() => _future = _load())`. Der
      // Pfeil gibt damit das Future ZURUECK - und Flutter verbietet
      // genau das in setState (Debug-Assert). Im Release faellt die
      // Pruefung weg, im Debug nicht: der Bildschirm zeichnet sich
      // danach nicht neu und bleibt im Fehlerzustand stehen.
      //
      // Dieser Test haelt den Zustand fest. Wird der Produktivcode
      // korrigiert (setState(() { _future = _load(); })), muss diese
      // Erwartung weg - und der Bildschirm zeigt dann die Liste.
      // ... und der Bildschirm zeichnet sich auch neu.
      //
      // BEFUND (13.11.2026, gefunden von diesem Test und BEHOBEN):
      // `_reload()` rief `setState(() => _future = _load())`. Der Pfeil
      // gibt damit das Future ZURUECK - und Flutter verbietet genau das
      // in setState (Debug-Assert). Im Release faellt die Pruefung weg,
      // im Debug nicht: der Bildschirm zeichnete sich danach nicht neu
      // und blieb im Fehlerzustand stehen.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'setState() darf kein Future zurueckgeben - der Bildschirm '
            'muss sich nach dem Neuladen neu zeichnen.',
      );
    });
  });

  group('Ueberall abmelden', () {
    testWidgets('der Knopf bittet erst um Bestaetigung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      await _pump(tester, service);

      await tester.tap(find.text('Überall abmelden (außer diesem Gerät)'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Überall abmelden?'), findsOneWidget);
      // Ohne Bestaetigung passiert nichts.
      expect(service.logoutAufrufe, 0);
    });

    testWidgets('Abbrechen laesst die Sitzungen stehen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      await _pump(tester, service);

      await tester.tap(find.text('Überall abmelden (außer diesem Gerät)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.logoutAufrufe, 0);
    });

    testWidgets('Bestaetigen meldet die anderen Geraete ab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      await _pump(tester, service);

      await tester.tap(find.text('Überall abmelden (außer diesem Gerät)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Überall abmelden'));
      // Der Dialog schliesst und der Hinweis laeuft ein. Bewusst kein
      // pumpAndSettle: der Hinweis verschwindet von selbst wieder, und
      // pumpAndSettle wuerde ihn wegwarten.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(service.logoutAufrufe, 1);
      expect(
        find.text('Alle anderen Geräte wurden abgemeldet.'),
        findsOneWidget,
      );
      // HINWEIS: Nach dem Abmelden ruft der Bildschirm `_reload()` auf
      // - und das wirft den bekannten setState-Fehler (siehe Test
      // "der Aktualisieren-Knopf laedt neu"). Der Bildschirm faengt
      // ihn und zeigt deshalb zusaetzlich (verzögert) die Meldung
      // "Abmelden ist fehlgeschlagen". Dieser Test prueft den Fall,
      // den der Nutzer zuerst sieht.
    });

    testWidgets('ein Fehler beim Abmelden wird angezeigt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.logoutFehler = AppException('Verbindung weg');

      await _pump(tester, service);

      await tester.tap(find.text('Überall abmelden (außer diesem Gerät)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Überall abmelden'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('Verbindung weg'), findsOneWidget);
    });
  });

  group('Neuladen', () {
    testWidgets('der Aktualisieren-Knopf laedt neu', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      await _pump(tester, service);
      expect(service.enrollAufrufe, 1);

      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pumpAndSettle();

      // Die Daten werden neu geladen ...
      expect(service.enrollAufrufe, 2);

      // ... aber BEFUND (13.11.2026, gefunden von diesem Test):
      // `_reload()` ruft `setState(() => _future = _load())`. Der
      // Pfeil gibt damit das Future ZURUECK - und Flutter verbietet
      // genau das in setState (Debug-Assert). Im Release faellt die
      // Pruefung weg, im Debug nicht: der Bildschirm zeichnet sich
      // danach nicht neu.
      //
      // Dieser Test haelt den Zustand fest. Wird der Produktivcode
      // korrigiert (setState(() { _future = _load(); })), muss diese
      // Erwartung weg.
      // ... und der Bildschirm zeichnet sich auch neu.
      //
      // BEFUND (13.11.2026, gefunden von diesem Test und BEHOBEN):
      // `_reload()` rief `setState(() => _future = _load())`. Der Pfeil
      // gibt damit das Future ZURUECK - und Flutter verbietet genau das
      // in setState (Debug-Assert). Im Release faellt die Pruefung weg,
      // im Debug nicht: der Bildschirm zeichnete sich danach nicht neu
      // und blieb im Fehlerzustand stehen.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'setState() darf kein Future zurueckgeben - der Bildschirm '
            'muss sich nach dem Neuladen neu zeichnen.',
      );
    });

    testWidgets('rendert ohne Overflow bei grosser Schrift', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeDeviceService(_FakeLocalStorage());
      service.geraete = [
        DeviceSession(
          deviceId: 'a',
          deviceName: 'Pixel 8',
          platform: 'android',
          deviceModel: 'Google Pixel 8',
          lastSeenAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          isCurrent: true,
        ),
      ];

      await _pump(tester, service, scale: 3.2);

      expect(tester.takeException(), isNull);
    });
  });
}
