// Der Event-Bildschirm der Dating Hour: die Fehler- und Rand-Wege.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/dating_hour/dating_hour_event_screen.dart 63 offene
// Zeilen - die Fehlerfaelle, der App-Wechsel und die Nebenwege.
//
// DER WEG: Der Dating-Hour-Dienst ist ein Hand-Fake. Er kann jeden
// Aufruf scheitern lassen - so sieht man, was der Bildschirm dem
// Nutzer sagt, wenn es nicht klappt.
//
// WAS HIER GEPRUEFT WIRD:
//   * schlaegt das Beitreten fehl, wird es gesagt (nicht verschwiegen),
//   * schlaegt das Verlassen fehl, wird es gesagt,
//   * schlaegt der Auto-Beitritt fehl, wird es gesagt,
//   * "Nein, danke" beim Wiedereinstieg schaltet den Auto-Beitritt ab,
//   * ein abgesagtes Event wird deutlich gesagt,
//   * der Bildschirm laedt nach (Timer, App-Wechsel, Refresh-Knopf),
//   * die Wege zu den Praeferenzen und zurueck sind da.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/dating_hour/dating_hour_event_screen.dart';
import 'package:thestia/services/dating_hour/dating_hour_service.dart';
import 'package:thestia/services/storage/local_storage.dart';

/// Die Einstellungen als Ersatz (der Test gibt sie direkt vor).
class _Einstellungen extends SettingsNotifier {
  _Einstellungen(Ref ref, {bool autoJoin = false})
    : super(_FakeLocalStorage(), ref) {
    if (autoJoin) {
      state = AppSettings.defaults().copyWith(datingHourAutoJoin: true);
    }
  }
}

/// Der Speicher im RAM - die Einstellungen kommen daraus.
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

/// Hand-Fake des Dating-Hour-Dienstes.
///
/// Der echte Dienst spricht mit der Datenbank. Der Fake haelt das Event
/// im RAM und zaehlt die Aufrufe - so sieht man, ob der Bildschirm den
/// Server wirklich neu laedt.
class _FakeDatingHourService extends DatingHourService {
  _FakeDatingHourService({this.event, this.teilnahme = false});

  /// Das Event, das der Screen sehen soll (null = kein Event geplant).
  final DatingHourEvent? event;

  /// Ob der Nutzer am Event teilnimmt.
  bool teilnahme;

  /// Wie oft wurde das Event geladen?
  int ladeAufrufe = 0;

  /// Wenn gesetzt, wirft [joinEvent] diesen Fehler.
  Object? joinFehler;

  /// Wenn gesetzt, wirft [leaveEvent] diesen Fehler.
  Object? leaveFehler;

  @override
  Future<DatingHourEvent?> getCurrentOrNextEvent() async {
    ladeAufrufe++;
    return event;
  }

  @override
  Future<bool> isUserParticipating(String eventId) async => teilnahme;

  @override
  Future<void> joinEvent(
    String userId,
    DatingHourPreferences preferences,
  ) async {
    final fehler = joinFehler;
    if (fehler != null) throw fehler;
    teilnahme = true;
  }

  @override
  Future<void> leaveEvent(String userId) async {
    final fehler = leaveFehler;
    if (fehler != null) throw fehler;
    teilnahme = false;
  }

  @override
  Future<int> getParticipantCount(String eventId) async => 7;

  @override
  Future<DatingHourSession?> getMyActiveSession(String eventId) async => null;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Ein Event, das JETZT laeuft (Start vor 10 Minuten, Ende in 50).
  DatingHourEvent laufendesEvent() {
    final jetzt = DateTime.now();
    return DatingHourEvent(
      id: 'event-1',
      eventDate: jetzt,
      dayOfWeek: jetzt.weekday % 7,
      startHour: jetzt.subtract(const Duration(minutes: 10)).hour,
      startMinute: jetzt.subtract(const Duration(minutes: 10)).minute,
      endHour: jetzt.add(const Duration(minutes: 50)).hour,
      endMinute: jetzt.add(const Duration(minutes: 50)).minute,
      startsAt: jetzt.subtract(const Duration(minutes: 10)),
      endsAt: jetzt.add(const Duration(minutes: 50)),
      status: 'active',
    );
  }

  /// Ein Event, das NOCH NICHT laeuft (Start in 30 Minuten).
  DatingHourEvent kommendesEvent() {
    final jetzt = DateTime.now();
    final start = jetzt.add(const Duration(minutes: 30));
    return DatingHourEvent(
      id: 'event-1',
      eventDate: jetzt,
      dayOfWeek: jetzt.weekday % 7,
      startHour: start.hour,
      startMinute: start.minute,
      endHour: start.add(const Duration(hours: 1)).hour,
      endMinute: start.add(const Duration(hours: 1)).minute,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      status: 'scheduled',
    );
  }

  /// Ein Event, das in 60 Minuten startet (die Anzeige in Stunden).
  DatingHourEvent eventInStunden() {
    final jetzt = DateTime.now();
    // Die 45 Sekunden Reserve: die Anzeige rechnet in ganzen Minuten -
    // ohne Reserve waere sie "59 Minuten" und die Stunden-Formatierung
    // wuerde nicht getroffen.
    final start = jetzt.add(const Duration(minutes: 60, seconds: 45));
    return DatingHourEvent(
      id: 'event-1',
      eventDate: jetzt,
      dayOfWeek: jetzt.weekday % 7,
      startHour: start.hour,
      startMinute: start.minute,
      endHour: start.add(const Duration(hours: 1)).hour,
      endMinute: start.add(const Duration(hours: 1)).minute,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      status: 'scheduled',
    );
  }

  /// Ein Event, das VORBEI ist (es ist vor einer Stunde zu Ende gegangen).
  DatingHourEvent beendetesEvent() {
    final jetzt = DateTime.now();
    final start = jetzt.subtract(const Duration(hours: 2));
    final ende = jetzt.subtract(const Duration(hours: 1));
    return DatingHourEvent(
      id: 'event-1',
      eventDate: jetzt,
      dayOfWeek: jetzt.weekday % 7,
      startHour: start.hour,
      startMinute: start.minute,
      endHour: ende.hour,
      endMinute: ende.minute,
      startsAt: start,
      endsAt: ende,
      status: 'ended',
    );
  }

  /// Ein Event, das abgesagt wurde (zu wenige Teilnehmer).
  DatingHourEvent abgesagtesEvent() {
    final jetzt = DateTime.now();
    final start = jetzt.add(const Duration(minutes: 30));
    return DatingHourEvent(
      id: 'event-1',
      eventDate: jetzt,
      dayOfWeek: jetzt.weekday % 7,
      startHour: start.hour,
      startMinute: start.minute,
      endHour: start.add(const Duration(hours: 1)).hour,
      endMinute: start.add(const Duration(hours: 1)).minute,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      status: 'cancelled',
    );
  }

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Scrollt zu einem Text (die Seite baut nur die sichtbaren Kacheln).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    if (ziel.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        ziel,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
    }
    await tester.ensureVisible(ziel);
    await pumpFrames(tester);
  }

  /// Baut den Bildschirm mit dem Fake.
  Future<_FakeDatingHourService> zeigeScreen(
    WidgetTester tester, {
    required _FakeDatingHourService service,
    bool autoJoin = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.datingHourEvent,
      routes: [
        GoRoute(
          path: AppRoutes.datingHourEvent,
          builder: (context, state) => const DatingHourEventScreen(),
        ),
        GoRoute(
          path: AppRoutes.swipeModeSelection,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Modi'))),
        ),
        GoRoute(
          path: AppRoutes.datingHourPreferences,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Präferenzen'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          datingHourServiceProvider.overrideWithValue(service),
          settingsProvider.overrideWith(
            (ref) => _Einstellungen(ref, autoJoin: autoJoin),
          ),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
    return service;
  }

  group('Die Fehler', () {
    testWidgets('schlaegt das Beitreten fehl, wird es gesagt', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent())
          ..joinFehler = DatingHourException('Der Server hat nein gesagt.'),
      );

      await tester.tap(find.text('Jetzt beitreten & chatten'));
      await pumpFrames(tester);
      await tester.tap(find.text('Ich bin dabei'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Der Server hat nein gesagt.'),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass das Beitreten nicht geklappt hat - '
            'sonst wartet er vergeblich auf den Chat.',
      );
    });

    testWidgets('schlaegt das Verlassen fehl, wird es gesagt', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(
          event: kommendesEvent(),
          teilnahme: true,
        )..leaveFehler = DatingHourException('Der Server hat nein gesagt.'),
      );

      await scrolleZu(tester, 'Raus');
      await tester.tap(find.text('Raus'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Der Server hat nein gesagt.'),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass er noch dabei ist - sonst zeigt er '
            'dem Partner die falsche Erwartung.',
      );
    });

    testWidgets('schlaegt der Auto-Beitritt fehl, wird es gesagt', (
      tester,
    ) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent())
          ..joinFehler = DatingHourException('Der Server hat nein gesagt.'),
        autoJoin: true,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Der Server hat nein gesagt.'),
        findsOneWidget,
        reason:
            'Auch der automatische Beitritt muss melden, wenn er nicht '
            'klappt - sonst wartet der Nutzer auf einen Chat, den es nicht '
            'gibt.',
      );
    });
  });

  group('Der Wiedereinstieg', () {
    testWidgets('"Nein, danke" schaltet den Auto-Beitritt ab', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(
          event: beendetesEvent(),
          teilnahme: true,
        ),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Nein, danke'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Alles klar, du wirst beim nächsten Mal gefragt.'),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, dass seine Antwort gespeichert wurde - '
            'sonst fragt die App beim naechsten Mal wieder.',
      );
    });
  });

  group('Das abgesagte Event', () {
    testWidgets('es wird deutlich gesagt', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: abgesagtesEvent()),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Dating Hour'),
        findsWidgets,
        reason: 'Der Bildschirm baut sich auch bei einem abgesagten Event.',
      );
      expect(
        find.byIcon(Icons.event_busy),
        findsWidgets,
        reason:
            'Ein abgesagtes Event muss sichtbar sein - der Nutzer darf nicht '
            'auf ein Event warten, das nicht stattfindet.',
      );
    });
  });

  group('Das Nachladen', () {
    testWidgets('der Timer laedt den Stand neu', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );
      final vorher = service.ladeAufrufe;

      // DER TIMER: Alle 30 Sekunden laedt der Bildschirm neu.
      await tester.pump(const Duration(seconds: 31));
      await pumpFrames(tester);

      expect(
        service.ladeAufrufe,
        greaterThan(vorher),
        reason:
            'Der Stand wird regelmaessig neu geladen - sonst wuerde der '
            'Nutzer einen alten Status sehen.',
      );
    });

    testWidgets('der Refresh-Knopf laedt neu', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );
      final vorher = service.ladeAufrufe;

      // DER REFRESH-KNOPF: Ueber seinen Hinweis gesucht - das Symbol
      // ist auf dem Bildschirm nicht eindeutig.
      await tester.tap(find.byTooltip('Aktualisieren'));
      await pumpFrames(tester);

      expect(
        service.ladeAufrufe,
        greaterThan(vorher),
        reason: 'Der Refresh-Knopf muss den Stand neu laden.',
      );
    });

    testWidgets('im Hintergrund laeuft kein Timer', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      // DER APP-WECHSEL: Das Geraet geht in den Hintergrund.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumpFrames(tester);
      final nachWechsel = service.ladeAufrufe;

      await tester.pump(const Duration(seconds: 31));
      await pumpFrames(tester);

      expect(
        service.ladeAufrufe,
        nachWechsel,
        reason:
            'Im Hintergrund darf nicht gepollt werden - das kostet Akku und '
            'der Nutzer sieht den Bildschirm gar nicht.',
      );
    });

    testWidgets('aus dem Hintergrund zurueck: der Stand wird neu geladen', (
      tester,
    ) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumpFrames(tester);
      final vorher = service.ladeAufrufe;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);

      expect(
        service.ladeAufrufe,
        greaterThan(vorher),
        reason:
            'Zurueck aus dem Hintergrund wird der Stand neu geladen - auf '
            'dem anderen Geraet kann etwas passiert sein.',
      );

      // DER SERVERZEIT-DIENST: Bei "Zurueck" startet er einen Sync-Timer
      // (5 Minuten) und ein paar Warteschleifen (3 und 8 Sekunden). Der
      // Test laeuft aber nicht so lange - ohne das bleibt am Ende des
      // Tests ein Timer "pending" und der Test waere rot.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
    });
  });

  group('Die Wege', () {
    testWidgets('zu den Praeferenzen', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: kommendesEvent()),
      );

      await scrolleZu(tester, 'Präferenzen festlegen');
      await tester.tap(find.text('Präferenzen festlegen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Präferenzen'),
        findsOneWidget,
        reason:
            'Der Nutzer muss die Praeferenzen setzen koennen, bevor er '
            'beitritt - sonst sucht er die passenden Leute nicht.',
      );
    });

    testWidgets('zurueck zu den Modi', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      // DER ZURUECK-KNOPF: Die Dating Hour wird per "go" erreicht - es
      // gibt keinen Stack zum Zurueckpoppen.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Modi'),
        findsOneWidget,
        reason:
            'Der Zurueck-Knopf muss zurueckbringen - sonst ist der Nutzer im '
            'Dating-Hour-Bildschirm gefangen.',
      );
    });
  });

  group('Die Anzeige', () {
    testWidgets('die Restzeit steht in Stunden und Minuten', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: eventInStunden()),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Stunde'),
        findsWidgets,
        reason:
            'Die Restzeit muss lesbar sein - "1 Stunde 30 Minuten" sagt mehr '
            'als eine kryptische Zahl.',
      );
    });
  });
}
