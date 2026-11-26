// Der Event-Bildschirm der Dating Hour (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/screens/dating_hour/dating_hour_event_screen.dart 528 offene
// Zeilen - die Seite, auf der der Nutzer der Dating Hour beitritt.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * ohne Event steht der Hinweis da (nicht ein leerer Bildschirm),
//   * ein Serverfehler zeigt die Fehlermeldung,
//   * das Beitreten fragt erst nach und meldet es dann dem Server,
//   * das Verlassen wird dem Server gemeldet,
//   * die Regeln stehen da (sie sind der Kern der Dating Hour).
//
// OHNE SERVER: Der Dating-Hour-Dienst ist ein Hand-Fake. Es geht KEINE
// Anfrage raus.
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
///
/// DER GRUND: Der automatische Beitritt liest die Einstellung aus dem
/// Anbieter. Der Test muss sie also VOR dem Aufbau setzen - danach
/// wäre der Bildschirm schon gebaut.
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

/// Hand-Fake des Dating-Hour-Dienstes.
///
/// Der echte Dienst spricht mit der Datenbank. Der Fake hält das Event
/// im RAM und merkt sich, ob der Nutzer beigetreten ist und das Event
/// wieder verlassen hat - so wird sichtbar, ob die App wirklich etwas
/// beim Server ausgelöst hat.
class _FakeDatingHourService extends DatingHourService {
  _FakeDatingHourService({this.event, this.teilnahme = false});

  /// Das Event, das der Screen sehen soll (null = kein Event geplant).
  final DatingHourEvent? event;

  /// Ob der Nutzer am Event teilnimmt.
  bool teilnahme;

  /// Die IDs der Events, denen der Nutzer beigetreten ist.
  final List<String> beigetreten = [];

  /// Die IDs der Events, die der Nutzer verlassen hat.
  final List<String> verlassen = [];

  /// Wenn gesetzt, wirft [getCurrentOrNextEvent] diesen Fehler.
  Object? ladeFehler;

  @override
  Future<DatingHourEvent?> getCurrentOrNextEvent() async {
    final fehler = ladeFehler;
    if (fehler != null) throw fehler;
    return event;
  }

  @override
  Future<bool> isUserParticipating(String eventId) async => teilnahme;

  @override
  Future<void> joinEvent(
    String userId,
    DatingHourPreferences preferences,
  ) async {
    beigetreten.add(event?.id ?? '');
    teilnahme = true;
  }

  @override
  Future<void> leaveEvent(String userId) async {
    verlassen.add(event?.id ?? '');
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

  /// Ein Event, das JETZT läuft (Start vor 10 Minuten, Ende in 50).
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

  /// Ein Event, das NOCH NICHT läuft (Start in 30 Minuten).
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
    // Der Knopf kann auch gebaut, aber unterhalb der Falz liegen - dann
    // wäre der Tipp ins Leere.
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
        overrides: [
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

  group('Dating-Hour-Event', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DatingHourEventScreen), findsOneWidget);
      expect(find.text('Dating Hour'), findsOneWidget);
    });

    testWidgets('ohne Event steht der Hinweis da', (tester) async {
      await zeigeScreen(tester, service: _FakeDatingHourService());

      expect(tester.takeException(), isNull);
      // Kein leerer Bildschirm - der Nutzer soll wissen, dass es heute
      // nichts gibt.
      expect(
        find.text('Aktuell ist kein Dating Hour Event geplant.'),
        findsOneWidget,
      );
    });

    testWidgets('ein Serverfehler zeigt die Fehlermeldung', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService()..ladeFehler = StateError('Server'),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Fehler beim Laden'), findsOneWidget);
    });

    testWidgets('das Beitreten fragt erst nach', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      // Das laufende Event bietet den Beitritt an.
      await tester.tap(find.text('Jetzt beitreten & chatten'));
      await pumpFrames(tester);

      // Die Rückfrage steht da.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Am Event teilnehmen?'), findsOneWidget);

      // Und "Abbrechen" nimmt NICHT teil.
      await tester.tap(find.text('Abbrechen'));
      await pumpFrames(tester);

      expect(service.beigetreten, isEmpty);
    });

    testWidgets('das Beitreten wird dem Server gemeldet', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      await tester.tap(find.text('Jetzt beitreten & chatten'));
      await pumpFrames(tester);
      await tester.tap(find.text('Ich bin dabei'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.beigetreten, contains('event-1'));
      // ... und der Nutzer bekommt die Bestätigung.
      expect(find.text('Du nimmst am Dating Hour Event teil!'), findsOneWidget);
    });

    testWidgets('das Verlassen wird dem Server gemeldet', (tester) async {
      final service = await zeigeScreen(
        tester,
        service: _FakeDatingHourService(
          event: kommendesEvent(),
          teilnahme: true,
        ),
      );

      // Das kommende Event zeigt den Raus-Knopf (der Nutzer nimmt ja
      // schon teil). Der Knopf kann unterhalb der Falz liegen.
      await scrolleZu(tester, 'Raus');
      await tester.tap(find.text('Raus'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(service.verlassen, contains('event-1'));
      expect(find.text('Du hast das Event verlassen.'), findsOneWidget);
    });

    testWidgets('die Regeln stehen da', (tester) async {
      await zeigeScreen(
        tester,
        service: _FakeDatingHourService(event: laufendesEvent()),
      );

      // Die Regeln sind der Kern der Dating Hour - sie müssen da
      // stehen, nicht nur im Kleingedruckten.
      expect(find.text('Wichtige Regeln'), findsOneWidget);
    });

    group('Der automatische Beitritt und der Wiedereinstieg', () {
      testWidgets('nach dem Event-Ende wird nach dem Wiedereinstieg gefragt', (
        tester,
      ) async {
        // DER FALL: Das Event ist vorbei und der Nutzer war dabei.
        // Einmal fragen, ob er beim nächsten Mal automatisch wieder
        // dabei sein will - das ist die Zusage aus dem Event.
        final service = await zeigeScreen(
          tester,
          service: _FakeDatingHourService(
            event: beendetesEvent(),
            teilnahme: true,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'Nach dem Event-Ende muss der Nutzer gefragt werden - sonst '
              'weiss er nicht, dass es eine solche Moeglichkeit gibt.',
        );
        expect(find.text('Ja, gerne'), findsOneWidget);
        expect(find.text('Nein, danke'), findsOneWidget);

        // "Ja, gerne" wird gemerkt.
        await tester.tap(find.text('Ja, gerne'));
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(service.beigetreten, isEmpty);
      });

      testWidgets('der automatische Beitritt nimmt ohne Rueckfrage teil', (
        tester,
      ) async {
        // DER FALL: Der Nutzer hat beim letzten Mal "Ja, gerne" gesagt.
        // Beim nächsten laufenden Event nimmt er automatisch teil - ohne
        // erneut gefragt zu werden.
        final service = await zeigeScreen(
          tester,
          service: _FakeDatingHourService(event: laufendesEvent()),
          autoJoin: true,
        );

        expect(tester.takeException(), isNull);
        expect(
          service.beigetreten,
          contains('event-1'),
          reason:
              'Mit dem Auto-Beitritt muss der Nutzer ohne Rueckfrage dabei '
              'sein - sonst waere die Zusage nicht eingehalten.',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason:
              'Der Auto-Beitritt fragt nicht - genau das ist der Sinn der '
              'Einstellung.',
        );
      });
    });
  });
}
