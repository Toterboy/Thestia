// Widget-Tests fuer den Profil-Editor ("Profil bearbeiten").
//
// ANLASS: Die Coverage-Messung (13.11.2026) zeigte fuer
// lib/screens/profile/profile_edit_screen.dart 583 offene Zeilen. Der
// Screen ist die einzige Stelle, an der der Nutzer sein Profil
// aendert - und der Betreiber hat dort im November 2026 gemeldet:
// "Wenn man Buttons auswählt, z. B. in den Profileinstellungen, sollen
// sie sich nicht in die nächste Zeile durch auswählen verschieben."
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen zeigt die Werte des Profils,
//   * der Zurück-Knopf fragt nach ungespeicherten Änderungen
//     ("Speichern?"-Nachfrage) und bietet Speichern/Verwerfen/Abbrechen,
//   * "Speichern" meldet Erfolg, ein Serverfehler wird gemeldet,
//   * ein ungültiges Formular wird abgewiesen (mit Hinweis),
//   * die Chips (Interessen, Gesundheit, Musik) springen beim Auswählen
//     NICHT in die nächste Zeile (StableChip) - und die Auswahl wird
//     übernommen.
//
// OHNE SERVER: Der Supabase-Client bekommt einen [FakeSupabaseServer].
// Damit kann der Test den Erfolgsfall UND den Fehlerfall stellen,
// ohne Netz und ohne Wartezeit.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/fake_supabase_server.dart';

/// In-Memory-Speicher fuer die lokalen Einstellungen.
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

/// Der sichere Speicher ohne Plugin: haelt die Werte im RAM.
///
/// WARUM DAS NOETIG IST (14.11.2026, gefunden von diesem Test):
/// [SecurePreferencesStorage] schreibt ueber flutter_secure_storage in
/// den verschluesselten Speicher des Geraets. Im Test gibt es dieses
/// Plugin nicht - der Aufruf lief ins Leere und das "await" haengte
/// fuer immer. Das haengende "Verwerfen" war die Ursache: der Dialog
/// schloss sich, aber der Bildschirm blieb stehen.
class _FakeSecurePrefs extends SecurePreferencesStorage {
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

/// Keystore ohne Plugin: liefert kein gespeichertes Profil.
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Das eigene Profil im Test.
///
/// [birthDate] ist Pflicht: ohne Geburtsdatum weist das Formular das
/// Speichern ab ("Bitte wählen") - es würde also gar nichts gespeichert.
/// (Darum ist das hier `final` und nicht `const`: [DateTime] hat keinen
/// const-Konstruktor.)
final UserProfile _profil = UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo aus Hamburg',
  birthDate: DateTime(1998, 6, 15),
  interests: <String>['Musik'],
);

/// Der Router, den der Screen braucht (Profil- und Test-Route).
GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.profileEdit,
    routes: [
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Mein Profil'))),
      ),
      GoRoute(
        path: AppRoutes.personalityTest,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Persönlichkeitstest'))),
      ),
    ],
  );
}

/// Der Knopf IM DIALOG - "Speichern" gibt es zweimal (im Bildschirm
/// und im Nachfrage-Dialog), deshalb muss der Finder den Dialog
/// einschraenken.
Finder _imDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

/// Alles, was der Screen zum Bauen braucht.
Future<ProviderContainer> _pump(WidgetTester tester, UserProfile profil) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  // Der IntroEditor erzeugt im initState einen AudioRecorder -> Kanal
  // mocken, sonst sucht das Plugin einen Plattform-Implementierer.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );

  final storage = _FakeLocalStorage();
  final secure = _FakeSecureProfileStore();
  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      secureProfileStoreProvider.overrideWithValue(secure),
      // Der sichere Speicher der Einstellungen (Audit M-16) - ohne ihn
      // haengt jedes Schreiben in den Keystore (siehe _FakeSecurePrefs).
      securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
      sharedPrefsProvider.overrideWithValue(prefs),
      profileProvider.overrideWith((ref) {
        final notifier = ProfileNotifier(storage, secure);
        // setProfile ist async, setzt den State aber sofort.
        unawaited(notifier.setProfile(profil));
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);

  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await _pumpFrames(tester);
  return container;
}

/// Pumpt feste Frames - im Test gibt es Stellen mit endloser Animation
/// (der Ladeindikator), auf die kann man nicht warten.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Wartet auf einen Text (mit Hoechstgrenze) - fuer Meldungen, die erst
/// nach mehreren Server-Versuchen auftauchen.
Future<bool> _warteAuf(
  WidgetTester tester,
  Finder ziel, {
  int hoechstSchritte = 40,
}) async {
  for (var i = 0; i < hoechstSchritte; i++) {
    if (ziel.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 250));
  }
  return ziel.evaluate().isNotEmpty;
}

/// Der Bildschirm wird nach dem Test abgebaut - sonst laeuft der
/// NSFW-Aufwaerm-Timer noch und der Test scheitert daran.
///
/// DIE ZEIT VORHER: Der entprellte Server-Sync der Einstellungen geht
/// 1,5 Sekunden nach der letzten Aenderung an den Server. Bleibt dieser
/// Timer beim Testende uebrig, scheitert der Test an "A Timer is still
/// pending". Deshalb wird hier so lange gepumpt, bis er abgelaufen ist.
Future<void> _aufraeumen(WidgetTester tester) async {
  // Zehn Sekunden (in Sekunden-Schritten, damit die Timer dazwischen
  // feuern): der entprellte Sync der Einstellungen (1,5 s) UND die
  // Wiederholungsversuche des Server-Syncs (1 s + 2 s Wartezeit je
  // Versuch) muessen alle abgelaufen sein, sonst steht am Ende ein
  // Timer uebrig und der Test scheitert an "A Timer is still pending".
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrollt zum Speichern-Knopf (er steht ganz unten im Formular).
Future<void> _scrolleZumSpeichern(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Speichern').last,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await _pumpFrames(tester);
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();

    // Der Supabase-Client zeigt auf den Fake-Server: es geht KEINE
    // Anfrage raus. Der Client wird nur EINMAL initialisiert (das ist
    // eine globale Singleton-Variable) - deshalb hier und nicht im Test.
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
      ),
    );
    // Angemeldet sein: ohne Konto darf die App nicht schreiben
    // ("Nicht eingeloggt").
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Jeder Test startet mit einem gesunden Server.
    server.antwortetMitFehler = false;
    server.rpcAntworten.clear();
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
  });

  group('Profil bearbeiten', () {
    testWidgets('zeigt die Werte des Profils', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, _profil);

      expect(tester.takeException(), isNull);
      expect(find.text('Profil bearbeiten'), findsOneWidget);
      // Der Name steht im Feld ...
      expect(find.text('Lena'), findsOneWidget);
      // ... und die Bio auch.
      expect(find.text('Hallo aus Hamburg'), findsOneWidget);

      await _aufraeumen(tester);
    });

    testWidgets('der Zurück-Knopf fragt nach ungespeicherten Änderungen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      // Der Name aendern - das Feld ist das erste TextFormular.
      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await _pumpFrames(tester);
      expect(container.read(profileEditDirtyProvider), isTrue);

      // Der Zurück-Knopf fragt nach.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Ungespeicherte Änderungen'), findsOneWidget);
      // Alle drei Wege stehen da: Speichern, Verwerfen, Abbrechen.
      expect(_imDialog('Speichern'), findsOneWidget);
      expect(_imDialog('Verwerfen'), findsOneWidget);
      expect(_imDialog('Abbrechen'), findsOneWidget);

      await _aufraeumen(tester);
    });

    testWidgets('"Verwerfen" lässt die Änderung fallen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await _pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _pumpFrames(tester);
      await tester.tap(_imDialog('Verwerfen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Das Profil ist unveraendert ...
      expect(container.read(profileProvider).name, 'Lena');
      // ... der Dirty-Flag ist zurueckgesetzt ...
      expect(container.read(profileEditDirtyProvider), isFalse);
      // ... und der Screen ist verlassen.
      expect(find.text('Mein Profil'), findsOneWidget);

      await _aufraeumen(tester);
    });

    testWidgets('"Speichern" im Dialog speichert das Profil', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await _pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _pumpFrames(tester);
      await tester.tap(_imDialog('Speichern'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der neue Name steht im Profil ...
      expect(container.read(profileProvider).name, 'Lena Neu');
      // ... der Dirty-Flag ist zurueck ...
      expect(container.read(profileEditDirtyProvider), isFalse);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Profil gespeichert'), findsOneWidget);

      await _aufraeumen(tester);
    });

    testWidgets('der Speichern-Knopf meldet einen Serverfehler', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await _pumpFrames(tester);
      await _scrolleZumSpeichern(tester);

      // Der Server schweigt ab jetzt.
      server.antwortetMitFehler = true;

      await tester.tap(find.text('Speichern').last);
      // Die Verifikation wiederholt dreimal (mit Wartezeit) - die
      // Meldung kommt erst danach.
      final gemeldet = await _warteAuf(
        tester,
        find.textContaining('Server-Sync fehlgeschlagen'),
      );

      expect(tester.takeException(), isNull);
      // Lokal ist gespeichert ...
      expect(container.read(profileProvider).name, 'Lena Neu');
      // ... aber der Nutzer wird gewarnt: der Server hat es nicht.
      expect(
        gemeldet,
        isTrue,
        reason:
            'Ein gescheiterter Server-Sync muss dem Nutzer gesagt werden - '
            'sonst glaubt er, die Änderung sei auch serverseitig angekommen.',
      );

      await _aufraeumen(tester);
    });

    testWidgets('ein ungültiges Formular wird abgewiesen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      // Der Name leer - der Validator verlangt mindestens zwei Zeichen.
      await tester.enterText(find.byType(TextFormField).first, 'x');
      await _pumpFrames(tester);
      await _scrolleZumSpeichern(tester);

      await tester.tap(find.text('Speichern').last);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer erfaehrt, dass es nicht gespeichert wurde.
      expect(find.textContaining('Es fehlen noch Angaben'), findsWidgets);
      // Und das Profil ist unveraendert.
      expect(container.read(profileProvider).name, 'Lena');

      await _aufraeumen(tester);
    });

    testWidgets('ein Interessen-Chip springt beim Auswählen nicht', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profil);

      // Zum Abschnitt "Interessen" scrollen.
      final chip = find.widgetWithText(FilterChip, 'Fotografie');
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(chip),
        vorher,
        reason:
            'BEFUND (13.11.2026, Betreiber): ein ausgewaehltes Chip darf '
            'nicht in die naechste Zeile springen - das fuehlt sich wie '
            'ein Fehlklick an.',
      );
      // Und die Auswahl ist angekommen (die Interessen stehen sofort
      // im Profil, nicht erst beim Speichern).
      expect(container.read(profileProvider).interests, contains('Fotografie'));

      await _aufraeumen(tester);
    });

    testWidgets('ein Gesundheits-Chip springt nicht und merkt sich die Wahl', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, _profil);

      // "Nie" beim Rauchen - das erste "Nie" gehört zum Rauchen.
      final chip = find.widgetWithText(ChoiceChip, 'Nie').first;
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(chip), vorher);
      // Die Auswahl ist als getroffen markiert.
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);

      await _aufraeumen(tester);
    });

    testWidgets('ein Musik-Chip springt nicht und merkt sich die Wahl', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, _profil);

      final chip = find.widgetWithText(FilterChip, 'Rock');
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(chip), vorher);
      expect(tester.widget<FilterChip>(chip).selected, isTrue);

      await _aufraeumen(tester);
    });
  });
}
