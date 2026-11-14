// Der Chat der Dating Hour (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/dating_hour/dating_hour_chat_screen.dart 650 offene
// Zeilen - der Screen, in dem fuenf Minuten lang zwei fremde Menschen
// miteinander reden.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Leerzustand steht da (mit dem Gesprächsstarter),
//   * der Timer lässt sich aus- und wieder einblenden (Nutzerwunsch:
//     "einen Timer gibt, den man sichtbar und unsichtbar machen kann"),
//   * das Beenden des Gesprächs fragt erst nach,
//   * ohne Gegenstelle sagt die App, dass die Nachricht nicht rausging
//     (statt sie zu verschlucken),
//   * das Verlassen fragt nach.
//
// OHNE SERVER: Der Dating-Hour-Dienst und der Datenbank-Dienst werden
// durch Hand-Fakes ersetzt. Es geht KEINE Anfrage raus.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/dating_hour_models.dart';
import 'package:thestia/screens/dating_hour/dating_hour_chat_screen.dart';
import 'package:thestia/services/dating_hour_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';

import 'support/plugin_mocks.dart';

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
/// Der echte Dienst spricht mit der Datenbank. Der Fake haelt die
/// Session im RAM und merkt sich, ob das Gespraech beendet wurde - so
/// wird sichtbar, ob die App wirklich beendet hat oder nur so tut.
class _FakeDatingHourService extends DatingHourService {
  _FakeDatingHourService(this.session);

  /// Die Session, die der Screen sehen soll.
  final DatingHourSession session;

  /// Die IDs der beendeten Gespraeche.
  final List<String> beendet = [];

  @override
  Future<DatingHourSession?> getSession(String sessionId) async => session;

  @override
  Future<bool> endConversation(String sessionId) async {
    beendet.add(sessionId);
    return true;
  }
}

/// Hand-Fake des Datenbank-Dienstes.
///
/// Nur das oeffentliche Profil des Chat-Partners wird beantwortet
/// (die Kopfzeile zeigt daraus die Gewohnheiten an).
class _FakeSupabaseDatabaseService extends SupabaseDatabaseService {
  _FakeSupabaseDatabaseService(super.client);

  @override
  Future<Map<String, dynamic>?> fetchPublicProfile(String userId) async {
    return {'smoking': 'nein', 'alcohol': 'selten', 'drugs': null};
  }
}

void main() {
  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // HIVE: die verschluesselten Schluessel (Signal-Protokoll) liegen in
    // Hive-Boxen. Ohne initialisierten Hive schlaegt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_dh');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// Die Session, die der Screen sehen soll: laeuft noch (4 Minuten
  /// Restzeit), niemand hat entschieden.
  DatingHourSession session() {
    final jetzt = DateTime.now();
    return DatingHourSession(
      id: 'session-1',
      eventId: 'event-1',
      userA: 'ich',
      userB: 'partner',
      startedAt: jetzt.subtract(const Duration(minutes: 1)),
      expiresAt: jetzt.add(const Duration(minutes: 4)),
    );
  }

  /// Pumpt eine feste Zahl von Frames.
  ///
  /// `pumpAndSettle` waere hier falsch: der Timer tickt jede Sekunde -
  /// es wird nie "alles ruhig".
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut den Screen mit den Fakes.
  Future<_FakeDatingHourService> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeDatingHourService(session());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          datingHourServiceProvider.overrideWithValue(service),
          supabaseDatabaseServiceProvider.overrideWithValue(
            _FakeSupabaseDatabaseService(supabase.Supabase.instance.client),
          ),
        ],
        child: const MaterialApp(
          home: DatingHourChatScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await pumpFrames(tester);
    return service;
  }

  group('Dating-Hour-Chat', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DatingHourChatScreen), findsOneWidget);
    });

    testWidgets('der Leerzustand steht da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Name der Gegenseite steht in der Kopfzeile.
      expect(find.text('Teilnehmer A'), findsWidgets);
      // Der Leerzustand erklaert, was los ist, und bietet den
      // Gesprächsstarter an - ein leerer Chat sonst wäre tote Hose.
      expect(find.textContaining('Sag hallo zu'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.icebreakerBtn')),
        findsOneWidget,
      );
    });

    testWidgets('die Gewohnheiten der Gegenseite stehen in der Kopfzeile', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // Der Chip wartet auf die Antwort des Servers - erst nach einem
      // weiteren Frame ist er da.
      await pumpFrames(tester);
      expect(find.text('Rauchen: nein'), findsOneWidget);
      expect(find.text('Alkohol: selten'), findsOneWidget);
    });

    testWidgets('der Timer lässt sich aus- und wieder einblenden', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // Der Timer ist da (das E2E-Schild).
      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsOneWidget);
      expect(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerHide')),
        findsOneWidget,
      );

      // Ausblenden (NUTZERWUNSCH: der Timer soll auch unsichtbar sein).
      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerHide')),
      );
      await pumpFrames(tester);

      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsNothing);
      expect(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerShow')),
        findsOneWidget,
      );

      // Und wieder einblenden.
      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerShow')),
      );
      await pumpFrames(tester);

      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsOneWidget);
    });

    testWidgets('das Beenden des Gespraechs fragt erst nach', (tester) async {
      final service = await zeigeScreen(tester);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);

      // Die Rueckfrage steht da.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.endConversationTitle')),
        findsOneWidget,
      );
      // Und "Abbrechen" beendet wirklich NICHT.
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await pumpFrames(tester);

      expect(service.beendet, isEmpty);
    });

    testWidgets('das Beenden des Gespraechs funktioniert', (tester) async {
      final service = await zeigeScreen(tester);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);
      await tester.tap(
        find.text(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.beendet, contains('session-1'));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(
        find.text(L10n.tWithoutContext('dh.chat.endConversationDone')),
        findsOneWidget,
      );
    });

    testWidgets(
      'ohne Gegenstelle meldet die App die fehlgeschlagene Nachricht',
      (tester) async {
        await zeigeScreen(tester);

        // Der Gesprächsstarter schreibt die Nachricht und sendet sie -
        // im Test gibt es keine Gegenstelle (keine Sitzung).
        await tester.tap(
          find.text(L10n.tWithoutContext('dh.chat.icebreakerBtn')),
        );
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('dh.chat.sendFailed')),
          findsOneWidget,
          reason:
              'Ohne Gegenstelle muss der Nutzer erfahren, dass die Nachricht '
              'nicht rausging - sonst schreibt er ins Leere.',
        );
      },
    );

    testWidgets('das Verlassen fragt nach', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.byIcon(Icons.close));
      await pumpFrames(tester);

      // Die Rueckfrage steht da - ohne sie waere der Chat nach einem
      // Fehlgriff weg.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.leaveTitle')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('dh.chat.stay')), findsOneWidget);
    });
  });
}
