// Der Transit-Radar (Transit Spark) - bisher ungetestet.
//
// ANLASS (13.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/transit_radar_screen.dart 936 offene Zeilen. Der
// Bildschirm ist der Kern von Transit Spark ("Blicke getauscht, dich
// nicht getraut?") - und er wurde nie gerendert.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Alterssperre ist fail-closed (ohne Geburtsdatum gesperrt),
//   * beim ersten Oeffnen fragt die App, ob der Name sichtbar sein soll,
//   * der Start fragt zuerst nach der eigenen Beschreibung,
//   * "Blicke getauscht" oeffnet die Merkmalsauswahl und sendet die Tags,
//   * die Kandidatenliste erscheint und der Zuwink meldet Erfolg/Fehlschlag,
//   * der Ort wird uebernommen (frei gewaehlt - KEIN Standort),
//   * der Name-Schalter speichert die Entscheidung.
//
// OHNE FUNK, OHNE SERVER: Das BLE-Starten und der Server werden durch
// einen Fake-Notifier ersetzt (kein Bluetooth, kein Netz). Die
// Merkmalsauswahl selbst ist das ECHTE Widget der App - sie wird nicht
// nachgebaut, sonst wuerde der Test nur Flutter pruefen und nicht die
// App.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/providers/transit_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/transit_radar_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/transit_ble_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/utils/constants.dart';

import 'support/ble_mocks.dart';
import 'support/plugin_mocks.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

/// Keystore ohne Plugin: das Profil liegt nur im RAM.
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Transit-Notifier ohne Bluetooth und ohne Server.
///
/// DER GRUND: Das echte `activate()` startet das BLE-Advertising (ein
/// Plattform-Kanal, den es im Test nicht gibt) und der echte Versand
/// geht ueber den Server. Der Fake bildet nur ab, was der Bildschirm
/// braucht: den Zustand und die Antworten (Match ja/nein, Kandidaten,
/// Zuwink).
class _FakeTransit extends TransitNotifier {
  _FakeTransit() : super();

  /// Das Ergebnis des naechsten "Blicke getauscht" (null = kein Match).
  ///
  /// DER STANDARD: Das Signal wird gesendet, aber es gibt noch keinen
  /// Match. Mit `null` waere der Bildschirm nach dem Senden fertig - es
  /// gaebe keine Kandidatenliste und keinen Zuwink.
  TransitSparkResult? sparkErgebnis = const TransitSparkResult(matched: false);

  /// Der Fehlergrund des letzten Sendens (fuer die Snackbar-Diagnose).
  String? sendFehler;

  /// Die Kandidaten, die der Server liefern wuerde.
  List<TransitCandidate> kandidaten = const [];

  /// Antwort auf das Zuwinken.
  bool zuwinkKlappt = true;

  /// Die Tags, die zuletzt gesendet wurden.
  List<String> gesendeteTags = const [];

  /// Wie oft wurde zugewinkt?
  int zuwinke = 0;

  /// Wie oft wurde gestartet bzw. gestoppt?
  int starts = 0;
  int stops = 0;

  /// Wenn gesetzt: das Starten schlaegt fehl (mit diesem Grund).
  String? startFehler;

  /// Die gesehenen Geraete (die Begegnungsliste).
  List<TransitEncounter> begegnungen = const [];

  /// Die gesendeten Gruesse (Text und eigene Zeile).
  final List<({String messageKey, String? customLine})> gruesse = [];

  /// Setzt die Anzahl der gesehenen Geraete (ohne den Radar zu starten).
  ///
  /// DER GRUND: Nach dem Radar bleibt die Liste ueber "in Ruhe finden"
  /// erreichbar - dafuer muss der Zaehler in der App stimmen.
  void setzeBegegnungszahl(int anzahl) {
    state = state.copyWith(encounterCount: anzahl);
  }

  @override
  Future<bool> activate() async {
    starts++;
    if (startFehler != null) {
      state = state.copyWith(active: false, endsAt: null, busy: false);
      return false;
    }
    state = state.copyWith(
      active: true,
      endsAt: DateTime.now().add(const Duration(minutes: 45)),
    );
    return true;
  }

  @override
  Future<void> deactivate() async {
    stops++;
    state = state.copyWith(active: false, endsAt: null, busy: false);
  }

  @override
  Future<TransitSparkResult?> sendSpark(List<String> tags) async {
    gesendeteTags = List<String>.of(tags);
    state = state.copyWith(
      busy: false,
      lastResult: sparkErgebnis,
      lastError: sendFehler,
    );
    return sparkErgebnis;
  }

  @override
  Future<List<TransitCandidate>> listCandidates({
    required List<String> tags,
    List<String> selfTags = const [],
  }) async => kandidaten;

  @override
  Future<bool> sendSoftPing({
    required String token,
    required String messageKey,
    String? customLine,
    String? recipientId,
    String? placeKind,
    String? placeText,
    List<String> tags = const [],
    List<String> selfTags = const [],
  }) async {
    zuwinke++;
    gruesse.add((messageKey: messageKey, customLine: customLine));
    return zuwinkKlappt;
  }

  @override
  List<TransitEncounter> softEncounters() => begegnungen;

  @override
  DateTime? softUntil() => null;
}

/// Eine Person, die Transit Spark benutzen darf (volljaehrig).
UserProfile _volljaehrig() => UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: '',
  birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
);

/// Eine Person ohne hinterlegtes Geburtsdatum - der Radar bleibt zu.
UserProfile _ohneGeburtsdatum() =>
    const UserProfile(id: 'ich', name: 'Lena', bio: '');

/// Baut den Container mit Storage, Profil und Radar-Fake.
///
/// DER GRUND FUER DEN EIGENEN CONTAINER: Die App liest die Einstellungen
/// sofort beim ersten Frame (die Namensfrage). Der Ladevorgang der
/// Einstellungen ist aber asynchron - ohne Vorabladen wuerde der
/// Bildschirm immer den Vorgabewert sehen und die Namensfrage immer
/// stellen, egal was gespeichert ist.
ProviderContainer _container({
  _FakeTransit? transit,
  UserProfile? profil,
  bool namensfrageErledigt = true,
}) {
  final storage = _FakeLocalStorage();
  if (namensfrageErledigt) {
    storage.saveString(
      AppConstants.prefsSettingsKey,
      // DER SCHLUESSEL: Lokal werden die Einstellungen mit CAMELCASE
      // gespeichert (siehe AppSettings.fromJson) - nur die Server-Spalten
      // heissen snake_case.
      jsonEncode(<String, dynamic>{'transitShowNameSet': true}),
    );
  }
  final profilNotifier = ProfileNotifier(storage, _FakeSecureProfileStore());
  profilNotifier.setProfile(profil ?? _volljaehrig());
  return ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
      profileProvider.overrideWith((ref) => profilNotifier),
      if (transit != null) transitProvider.overrideWith((ref) => transit),
    ],
  );
}

/// Der Router des Tests.
///
/// Der Bildschirm springt nach einem Match zu den Funken
/// ([AppRoutes.interessen]) - ohne diese Route waere der Knopf im Test
/// ein Totalausfall statt einer Navigation.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/radar',
    routes: [
      GoRoute(path: '/radar', builder: (_, _) => const TransitRadarScreen()),
      GoRoute(
        path: AppRoutes.interessen,
        builder: (_, _) => const Scaffold(body: Text('Funken-Liste')),
      ),
    ],
  );
}

/// Setzt den Bildschirm auf und laesst die erste Frame-Rechnung laufen.
///
/// DIE EINSTELLUNGEN VORHER LADEN: Der Bildschirm fragt in seinem
/// ersten Frame nach der Namens-Entscheidung - und laesst sie aus,
/// wenn die Einstellungen schon geladen sind. Die App wartet darauf im
/// Router (der startet erst, wenn die Einstellungen da sind). Im Test
/// muss das von Hand geschehen, sonst stellt der Bildschirm die Frage,
/// obwohl sie im Speicher schon beantwortet ist.
Future<void> _aufbauen(
  WidgetTester tester,
  ProviderContainer container,
  GoRouter router,
) async {
  await container.read(settingsProvider.notifier).whenLoaded();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Waehlt im Merkmals-Sheet [anzahl] Merkmale aus (je eins je Kategorie -
/// zwei Merkmale derselben Kategorie wuerden sich gegenseitig
/// verdraengen, das ist die Regel der App).
Future<void> _merkmaleWaehlen(
  WidgetTester tester,
  List<String> bezeichnungen,
) async {
  for (final bezeichnung in bezeichnungen) {
    final chip = find.text(bezeichnung);
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
  }
}

/// Tippt den Senden-Knopf im Merkmals-Sheet ("Funken").
Future<void> _sendenTippen(WidgetTester tester) async {
  final knopf = find.widgetWithText(FilledButton, 'Funken');
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Wartet auf einen Text (die Snackbar wartet in der Warteschlange
/// hinter der vorherigen - die "Dein Signal ist gespeichert" steht acht
/// Sekunden, erst danach kommt die naechste durch).
Future<void> _warteAufText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Tippt auf einen Knopf des Bildschirms.
///
/// DER GRUND FUER DAS SCROLLEN: Der Bildschirm ist eine lange Liste -
/// viele Knöpfe liegen unterhalb des sichtbaren Bereichs. Ohne das
/// Scrollen geht der Tipp ins Leere (Flutter warnt, der Test laeuft
/// trotzdem weiter und behauptet, es sei nichts passiert).
Future<void> _knopfTippen(WidgetTester tester, String text) async {
  final knopf = find.text(text);
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tippt auf "Radar aktivieren".
///
/// DER GRUND FUER DAS SCROLLEN: Der Knopf steht unterhalb des
/// sichtbaren Bereichs (der Bildschirm ist eine lange Liste). Ohne das
/// Scrollen geht der Tipp ins Leere - Flutter warnt dann zwar, aber der
/// Test laeuft weiter und behauptet, der Radar haette nicht gestartet.
Future<void> _startTippen(WidgetTester tester) async {
  final knopf = find.text('Radar aktivieren');
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Startet den Radar (mit der Selbstbeschreibung).
///
/// DER GRUND: Die Begegnungsliste steht nur im LAUFENDEN Radar - vorher
/// gibt es sie gar nicht.
Future<void> _radarStarten(WidgetTester tester) async {
  await _startTippen(tester);
  await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
  await _sendenTippen(tester);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: Der Bildschirm liest die Einstellungen (Altersspanne
    // und Suchradius) aus dem verschluesselten Speicher. Ohne diesen
    // Mock ruft der Test auf dem CI-Runner das echte Plugin - und das
    // findet dort keine libsecret-Sitzung.
    mockKeystore();
  });

  group('Der Transit-Radar', () {
    // Die Fehlerpfade beim Start (15.11.2026): Der Bildschirm
    // unterscheidet die Gruende (Standortdienst, fehlende
    // Bluetooth-Berechtigung, Bluetooth aus) und zeigt fuer jeden einen
    // eigenen Dialog - der Nutzer soll nicht raten muessen, was fehlt.
    group('Die Fehler beim Start', () {
      /// Startet den Radar mit einem Start, der scheitert.
      ///
      /// [grund] ist der Fehlergrund, den der echte Dienst liefert
      /// ([TransitBleService.lastError]) - der Bildschirm liest ihn
      /// von dort, um die passende Erklaerung zu zeigen.
      Future<_FakeTransit> starteFehlgeschlagen(
        WidgetTester tester, {
        required String grund,
      }) async {
        final transit = _FakeTransit()..startFehler = grund;
        TransitBleService.instance.lastError = grund;
        addTearDown(() => TransitBleService.instance.lastError = null);

        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);
        await _startTippen(tester);
        // Der Start fragt zuerst nach der eigenen Beschreibung.
        // Wichtig: es muessen MINDESTENS ZWEI Merkmale sein (Migration
        // 149) - mit einem einzigen bleibt der Senden-Knopf gesperrt und
        // der Start kommt nie zustande.
        await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
        await _sendenTippen(tester);
        return transit;
      }

      testWidgets('ohne den Standortdienst sagt die App, was fehlt', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'location_service',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        // Der Dialog nennt den Standortdienst - sonst sucht der Nutzer
        // vergebens nach Bluetooth.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(L10n.tWithoutContext('transit.locationTitle')),
          findsOneWidget,
        );
      });

      testWidgets('ohne Bluetooth-Berechtigung kommt der Hinweis', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'bluetooth_scan',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('ist Bluetooth aus, steht das auch da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'bluetooth_off',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        // Auch fuer "Bluetooth ist aus" gibt es eine eigene Erklaerung.
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });

    testWidgets('rendert ohne Absturz und zeigt die Bedienung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      // Der Titel steht da.
      expect(find.text('Transit Spark'), findsOneWidget);
      // Der Radar ist aus - mit dem Klartext, was das bedeutet.
      expect(find.textContaining('Radar aus'), findsOneWidget);
      // Start und "Blicke getauscht" sind da.
      expect(find.text('Radar aktivieren'), findsOneWidget);
      expect(find.text('Blicke getauscht'), findsOneWidget);
      // Die Ortseingabe steht bereit.
      expect(find.byKey(const Key('transit.placeText')), findsOneWidget);
      // Der Schalter fuer den Namen steht da.
      expect(find.text('Namen beim Zuwinken zeigen'), findsOneWidget);
      // Und die Datenschutz-Erklaerung nicht vergessen.
      expect(find.text('Wie funktioniert das?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ohne Geburtsdatum bleibt der Radar gesperrt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(
        transit: transit,
        profil: _ohneGeburtsdatum(),
      );
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      // Die Sperre wird erklaert, nicht kommentarlos gezeigt.
      expect(find.text('Transit Spark nur ab 18'), findsOneWidget);
      // Und es gibt KEINEN Start-Knopf (fail-closed).
      expect(find.text('Radar aktivieren'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('beim ersten Oeffnen fragt die App nach dem Namen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      // Die Namensfrage ist noch nicht beantwortet.
      final container = _container(
        transit: transit,
        namensfrageErledigt: false,
      );
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      expect(find.text('Soll dein Name sichtbar sein?'), findsOneWidget);

      // "Nein" heisst: anonym bleiben.
      await tester.tap(find.text('Nein, bleib anonym'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final settings = container.read(settingsProvider);
      expect(
        settings.transitShowName,
        isFalse,
        reason: 'Die Entscheidung "anonym" muss gespeichert werden.',
      );
      expect(
        settings.transitShowNameSet,
        isTrue,
        reason:
            'Nach der Entscheidung darf die Frage nicht mehr kommen - '
            'sonst fragt die App bei jedem Oeffnen.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Start fragt zuerst nach der eigenen Beschreibung', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      await _startTippen(tester);

      expect(find.text('Wie siehst du gerade aus?'), findsOneWidget);
      expect(transit.starts, 0, reason: 'Der Radar darf noch nicht laufen.');

      // Mit einem Merkmal allein ist der Senden-Knopf noch gesperrt
      // (die Server-Regel verlangt mindestens zwei).
      await _merkmaleWaehlen(tester, ['Haarfarbe']);
      final knopf = find.widgetWithText(FilledButton, 'Funken');
      expect(
        tester.widget<FilledButton>(knopf).onPressed,
        isNull,
        reason: 'Mit einem Merkmal darf noch nicht gesendet werden.',
      );

      // Zwei Merkmale aus verschiedenen Kategorien - dann geht es.
      await _merkmaleWaehlen(tester, ['Haarlänge']);
      expect(
        tester.widget<FilledButton>(knopf).onPressed,
        isNotNull,
        reason: 'Zwei Merkmale muessen reichen.',
      );

      await _sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(transit.starts, 1, reason: 'Der Radar muss jetzt laufen.');
      // Die eigene Beschreibung steht im Zustand.
      expect(container.read(transitProvider).selfTags, hasLength(2));
      // Und die Bedienung wechselt auf "Stoppen".
      expect(find.text('Radar stoppen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Blicke getauscht schickt die gewaehlten Merkmale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      // Erst den Radar starten - "Blicke getauscht" ist nur im laufenden
      // Radar moeglich.
      await _startTippen(tester);
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      // Jetzt der eigentliche Knopf.
      await _knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Die Merkmalsauswahl geht auf - mit der Frage "Wer war das?".
      expect(find.text('Wer war das?'), findsOneWidget);
      // Der Zaehler zeigt noch nichts.
      expect(find.text('0 gewaehlt'.replaceAll('ae', 'ä')), findsOneWidget);

      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(
        transit.gesendeteTags,
        hasLength(2),
        reason: 'Die beiden gewaehlten Merkmale muessen gesendet werden.',
      );
      expect(transit.gesendeteTags, contains('hair_color'));
      expect(transit.gesendeteTags, contains('hair_length'));
      // Ohne Gegensignal wird das Signal gespeichert - der Nutzer
      // bekommt eine Antwort, nicht Schweigen.
      expect(find.textContaining('Signal'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Zuwink meldet Erfolg und Fehlschlag', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      transit.kandidaten = const [
        TransitCandidate(
          id: 'kandidat-1',
          tags: ['hemd'],
          selfTags: ['schal'],
          name: 'Mira',
          placeText: 'Wagen 3',
        ),
      ];
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      await _startTippen(tester);
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      await _knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      // Die Kandidatenliste erscheint - mit Name und Ort der Person.
      expect(find.text('Menschen mit deiner Beschreibung'), findsOneWidget);
      expect(find.text('Mira'), findsOneWidget);
      // Der Untertitel nennt die Merkmale UND den Ort in einem Text
      // ("hemd - Wagen 3") - deshalb "enthält" statt "ist gleich".
      // (Der Ort steht auch im Platzhalter des Eingabefelds - deshalb
      // muss der Text vollstaendig passen.)
      expect(find.textContaining('hemd - Wagen 3'), findsOneWidget);

      await _knopfTippen(tester, 'Zuwinken');
      await _warteAufText(tester, 'Zugewinkt');

      expect(tester.takeException(), isNull);
      expect(
        find.text('Zugewinkt'),
        findsOneWidget,
        reason: 'Der Zuwink muss bestaetigt werden.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Zuwink meldet auch einen Fehlschlag', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      transit.kandidaten = const [
        TransitCandidate(id: 'kandidat-1', tags: ['hemd'], selfTags: ['schal']),
      ];
      transit.zuwinkKlappt = false;
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      await _startTippen(tester);
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      await _knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      // Ohne freigegebenen Namen bleibt die Person anonym.
      expect(find.text('Jemand in der Nähe'), findsOneWidget);

      await _knopfTippen(tester, 'Zuwinken');
      await _warteAufText(tester, 'Das hat nicht geklappt');

      expect(tester.takeException(), isNull);
      expect(
        find.text('Das hat nicht geklappt'),
        findsOneWidget,
        reason: 'Ein Fehlschlag muss gesagt werden - nicht still bleiben.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Ort wird uebernommen - er wird nicht ermittelt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      // Die Art des Ortes wird als Chip gewaehlt.
      await tester.ensureVisible(find.text('Zug'));
      await tester.pump();
      await tester.tap(find.text('Zug'));
      await tester.pump();

      expect(container.read(transitProvider).placeKind, 'zug');

      // Und der Ort selbst wird frei getextet.
      final feld = find.byKey(const Key('transit.placeText'));
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, 'Wagen 3');
      await tester.pump();

      expect(container.read(transitProvider).placeText, 'Wagen 3');
      // Der Datenschutz-Hinweis steht daneben - der Ort ist eine
      // Selbstauskunft, keine Ortung.
      expect(find.textContaining('selbst'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Name-Schalter speichert die Entscheidung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = _FakeTransit();
      final container = _container(transit: transit);
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      final schalter = find.ancestor(
        of: find.text('Namen beim Zuwinken zeigen'),
        matching: find.byType(SwitchListTile),
      );
      expect(schalter, findsOneWidget);

      // Der Schalter steht jetzt in der Karte mit der Erinnerung
      // (BEFUND 14.11.2026: "Transit Spark Screen sieht ueberfuellt und
      // durcheinander aus") - er liegt damit weiter unten auf der
      // Seite. Ohne Scrollen geht der Tipp ins Leere.
      await tester.ensureVisible(schalter);
      await tester.pump();
      await tester.tap(schalter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final settings = container.read(settingsProvider);
      expect(
        settings.transitShowName,
        isFalse,
        reason: 'Der Schalter muss die Entscheidung uebernehmen.',
      );
      expect(
        settings.transitShowNameSet,
        isTrue,
        reason: 'Nach dem Schalter ist die Frage entschieden.',
      );
      // Und die Grenze wird genannt - ein Schalter ohne diese Erklaerung
      // erzeugt eine falsche Sicherheit.
      expect(
        find.textContaining('erkennt dich trotzdem'),
        findsOneWidget,
        reason:
            'Der Schalter muss die Grenze nennen - ein Schalter ohne diese '
            'Erklaerung erzeugt eine falsche Sicherheit.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    // Der echte Startweg: der Bildschirm ruft den Transit-Notifier, der
    // den Bluetooth-Dienst, der das Advertising einschaltet. Mit dem
    // Bluetooth-Ersatz (test/support/ble_mocks.dart) laeuft die Kette
    // wirklich - nur das Funkgeraet fehlt.
    testWidgets('der Start schaltet das Advertising ein', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      mockBluetooth();
      resetAdvertisingZaehler();

      // OHNE den Fake-Notifier: hier laeuft der echte Transit-Notifier
      // (er spricht den Bluetooth-Dienst an).
      final container = _container();
      final router = _router();
      addTearDown(router.dispose);

      await _aufbauen(tester, container, router);

      // Der Start fragt zuerst nach der eigenen Beschreibung (zwei
      // Merkmale sind Pflicht).
      await _startTippen(tester);
      await _merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await _sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(
        advertisingStarts,
        greaterThan(0),
        reason:
            'Der Start muss das Advertising wirklich einschalten - sonst '
            'sendet der Radar nichts.',
      );

      // Der Container schliesst den Transit-Notifier - und damit die
      // Timer (der 45-Minuten-Countdown und der Scan-Puls). Das muss
      // VOR dem Testende passieren: die Pruefung auf offene Timer laeuft
      // noch vor den tearDowns.
      container.dispose();

      // Der Scan-Aufruf des Plugins hat einen eigenen Timer (12 s) - der
      // laeuft hier einfach ab.
      await tester.pump(const Duration(seconds: 13));
    });

    // Die Begegnungsliste: nach dem Radar sieht der Nutzer, welche
    // Geraete er gesehen hat - und kann sie anonym gruessen.
    group('Die Begegnungsliste', () {
      testWidgets('sie zeigt die gesehenen Geraete', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = _FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
          TransitEncounter(
            token: 'token-2',
            seenAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ];
        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);
        // Die Begegnungsliste steht nur im laufenden Radar.
        await _radarStarten(tester);

        expect(tester.takeException(), isNull);
        // Beide Geraete stehen da - mit dem Alter ("gerade eben", "vor
        // 5 Min.").
        expect(find.text('gerade eben'), findsOneWidget);
        expect(find.text('vor 5 Min.'), findsOneWidget);
        // Und beide kann der Nutzer gruessen.
        expect(
          find.text(L10n.tWithoutContext('transit.greet')),
          findsNWidgets(2),
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ohne Geraete steht der Leerzustand da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = _FakeTransit();
        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);
        await _radarStarten(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.noEncounters')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('der Gruss wird gesendet', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = _FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
        ];
        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);
        await _radarStarten(tester);

        // Der Gruss-Knopf oeffnet das Blatt mit den Vorschlaegen.
        await _knopfTippen(tester, L10n.tWithoutContext('transit.greet'));

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.pingSheetTitle')),
          findsOneWidget,
          reason: 'Das Blatt mit den Vorschlaegen muss aufgehen.',
        );
        expect(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
          findsOneWidget,
        );

        // Einen Vorschlag waehlen und senden.
        await tester.tap(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('transit.pingSend'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(
          transit.gruesse,
          hasLength(1),
          reason:
              'Der Gruss muss wirklich raus - sonst sieht die Person '
              'nie, dass jemand in der Naehe war.',
        );
        expect(transit.gruesse.first.messageKey, 'wave');
        // Und der Nutzer bekommt die Bestaetigung.
        expect(find.textContaining('Gruß gesendet'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('die eigene Zeile wandert mit', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = _FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
        ];
        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);
        await _radarStarten(tester);

        await _knopfTippen(tester, L10n.tWithoutContext('transit.greet'));

        // Die eigene Zeile eintippen (das Feld im Blatt - der Bildschirm
        // hat noch ein eigenes Eingabefeld).
        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          'Bis gleich im Zug!',
        );
        await tester.pump();
        await tester.tap(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('transit.pingSend'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(
          transit.gruesse.first.customLine,
          'Bis gleich im Zug!',
          reason:
              'Die eigene Zeile muss mitgesendet werden - sie ist der '
              'einzige frei formulierte Teil des Grusses.',
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('nach dem Radar bleiben die Begegnungen erreichbar', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = _FakeTransit();
        transit.begegnungen = [
          TransitEncounter(
            token: 'token-1',
            seenAt: DateTime.now().subtract(const Duration(minutes: 50)),
          ),
        ];
        // Der Radar ist nicht aktiv, aber es gab Begegnungen.
        transit.setzeBegegnungszahl(1);
        final container = _container(transit: transit);
        addTearDown(container.dispose);
        final router = _router();
        addTearDown(router.dispose);

        await _aufbauen(tester, container, router);

        // Der Knopf "in Ruhe finden" steht da - die Begegnungen gehen
        // nach dem Radar nicht verloren.
        await _knopfTippen(tester, L10n.tWithoutContext('transit.retainedBtn'));

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.retainedTitle')),
          findsOneWidget,
          reason: 'Das Blatt mit den erhaltenen Begegnungen muss aufgehen.',
        );
        // Und die Begegnung steht drin.
        expect(find.text('vor 50 Min.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
