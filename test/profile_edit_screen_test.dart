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
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/location_check_service.dart';
import 'package:thestia/services/location_verification_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/location_privacy.dart';

import 'support/fake_supabase_server.dart';

import 'support/plugin_mocks.dart';

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

/// Die Berechtigungen im Test.
///
/// DER GRUND: Ohne diesen Ersatz ruft `Permission.location.status` das
/// echte Plugin - im Test gibt es das nicht (und der Aufruf wuerde
/// einen Fehler werfen). Mit ihm kann der Test beide Faelle stellen:
/// die Berechtigung ist da (kein Dialog) oder sie fehlt (der Dialog
/// der Offenlegung erscheint).
class _Berechtigungen extends PermissionHandlerPlatform {
  /// Ist die Standort-Berechtigung erteilt?
  bool erteilt = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      erteilt ? PermissionStatus.granted : PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    erteilt = true;
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

/// Der Ort-Dienst im Test: liefert eine feste Position.
///
/// DER GRUND: Das GPS gibt es im Test nicht. Der Dienst liefert hier
/// die Position, die der Bildschirm dann auf das 5-km-Raster legt.
class _FakeOrtService extends LocationVerificationService {
  _FakeOrtService({this.position});

  /// Die Position, die der Dienst meldet (null = kein Standort).
  final Position? position;

  /// Wie oft wurde der Standort abgefragt?
  int abfragen = 0;

  @override
  Future<Position?> getCurrentLocation() async {
    abfragen++;
    return position;
  }

  @override
  Future<bool> isLocationSuspicious(
    Position newPosition, {
    double thresholdMeters = 100,
  }) async => false;
}

/// Die Standort-Pruefung im Test.
///
/// DER GRUND: Der echte Dienst ruft eine Edge Function. Dafuer holt der
/// Client vorher sein Token - und im Test kommt diese
/// Token-Aktualisierung nicht durch (der Aufruf bliebe haengen, der
/// Timer stuende bis zum Testende). Der Ersatz merkt sich stattdessen,
/// DASS und MIT WELCHEN Koordinaten geprueft wurde - genau das will
/// der Bildschirm testen.
class _FakeStandortPruefung extends LocationCheckService {
  _FakeStandortPruefung(super.client);

  /// Die Koordinaten, die zur Pruefung gemeldet wurden.
  final List<Map<String, dynamic>> aufrufe = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> processLocationCheck({
    required String userId,
    required double newLatitude,
    required double newLongitude,
  }) async {
    aufrufe.add(<String, dynamic>{
      'userId': userId,
      'newLatitude': newLatitude,
      'newLongitude': newLongitude,
    });
    return <String, dynamic>{'ok': true};
  }
}

/// Eine Position fuer den Test (Hamburg).
Position _position() => Position(
  latitude: 53.5511,
  longitude: 9.9937,
  timestamp: DateTime(2026, 11, 16),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

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

/// Dasselbe Profil, aber mit drei Bildern.
///
/// DER GRUND: Ohne Bilder gibt es im Editor keine Kacheln - und damit
/// auch keinen Weg, ein Bild zu entfernen. Genau das wird hier
/// geprueft: das entfernte Bild muss beim Server verschwinden.
final UserProfile _profilMitBildern = UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo aus Hamburg',
  birthDate: DateTime(1998, 6, 15),
  interests: <String>['Musik'],
  photos: <String>['ich/avatar.jpg', 'ich/photos/2.jpg', 'ich/photos/3.jpg'],
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
Future<ProviderContainer> _pump(
  WidgetTester tester,
  UserProfile profil, {
  _FakeOrtService? ortService,
}) async {
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
      // Der Ort-Dienst: im Test gibt es kein GPS.
      if (ortService != null)
        locationVerificationServiceProvider.overrideWithValue(ortService),
      // Die Standort-Pruefung (Edge Function) - der Ersatz merkt sich
      // die Aufrufe (siehe _FakeStandortPruefung).
      locationCheckServiceProvider.overrideWith(
        (ref) => _FakeStandortPruefung(SupabaseService.client),
      ),
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
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
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
    // Die Berechtigungen: ohne diesen Ersatz ruft der Bildschirm das
    // echte Plugin (im Test gibt es das nicht).
    PermissionHandlerPlatform.instance = _Berechtigungen();
  });

  // Der Einspruch: Wenn der Admin ein beanstandetes Foto freigibt oder
  // ablehnt, muss der Nutzer das erfahren - der Profil-Editor holt den
  // Stand beim Oeffnen.
  group('Der Einspruch gegen ein Foto', () {
    testWidgets('eine Freigabe fragt nach, ob das Bild uebernommen wird', (
      tester,
    ) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-1',
        'status': 'approved',
        'storagePath': 'einspruch/foto.jpg',
      };

      await _pump(tester, _profil);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.approvedTitle')),
        findsOneWidget,
        reason:
            'Nach der Freigabe muss der Nutzer entscheiden, ob das Bild '
            'sein Profilfoto wird.',
      );
    });

    testWidgets('eine Ablehnung wird erklaert und quittiert', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-2',
        'status': 'rejected',
        'storagePath': 'einspruch/foto.jpg',
      };

      await _pump(tester, _profil);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.rejectedTitle')),
        findsOneWidget,
        reason:
            'Eine Ablehnung muss der Nutzer kennen - sonst wartet er '
            'unendlich auf eine Entscheidung.',
      );

      // Der Dialog wartet, bis der Nutzer ihn wegklickt - erst DANACH
      // wird die Entscheidung quittiert.
      final ok = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('profile.appeal.okBtn'),
      );
      expect(ok, findsOneWidget);
      await tester.tap(ok);
      await _pumpFrames(tester);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }

      // Und die Entscheidung wird quittiert - sonst kommt der Dialog
      // bei jedem Oeffnen wieder.
      expect(
        server.pfade.any((p) => p.contains('acknowledge_photo_appeal')),
        isTrue,
        reason: 'Die Entscheidung muss dem Server gemeldet werden.',
      );
    });
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

  // Die Bilder im Profil: der Nutzer entfernt ein Bild - und es muss
  // wirklich beim Server verschwinden.
  group('Die Bilder im Profil', () {
    testWidgets('ein entferntes Bild kommt beim Server nicht mehr an', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pump(tester, _profilMitBildern);

      expect(tester.takeException(), isNull);
      // Drei Bilder = drei Entfernen-Knoepfe (einer je Kachel).
      final knoepfe = find.byIcon(Icons.close);
      expect(
        knoepfe,
        findsNWidgets(3),
        reason:
            'Zu jedem Bild gehoert ein Entfernen-Knopf - sonst kann der '
            'Nutzer sein Bild nie wieder loswerden.',
      );

      // Die mittlere Kachel (Slot 1) leeren.
      await tester.tap(knoepfe.at(1));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Bildschirm weiss jetzt, dass sich etwas geaendert hat.
      expect(
        container.read(profileEditDirtyProvider),
        isTrue,
        reason:
            'Nach dem Entfernen eines Bildes muss der Bildschirm als '
            '"geaendert" gelten - sonst ginge der Aenderung beim '
            'Zurueckgehen verloren.',
      );

      await _scrolleZumSpeichern(tester);
      await tester.tap(find.text('Speichern').last);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);

      // DER SERVER-CHECK: Der Schreibvorgang mit den Fotos.
      final mitFotos = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profiles' && v['photos'] != null)
          .toList();
      expect(
        mitFotos,
        isNotEmpty,
        reason:
            'Die Fotos muessen zum Server gehen - sonst sieht der '
            'Nutzer sein Bild zwar entfernt, auf anderen Geraeten aber '
            'weiterhin.',
      );
      final gesendet = (mitFotos.last['photos'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      expect(
        gesendet,
        isNot(contains('ich/photos/2.jpg')),
        reason:
            'Das entfernte Bild darf NICHT mehr beim Server stehen - '
            'sonst ist es nach dem Neustart wieder da.',
      );
      expect(
        gesendet,
        contains('ich/photos/3.jpg'),
        reason:
            'Die Galerie rueckt nach: das dritte Bild nimmt den Platz '
            'des entfernten ein - sonst waere eine Luecke in der '
            'Galerie.',
      );

      // Und auch lokal ist es weg.
      expect(
        container.read(profileProvider).photos,
        isNot(contains('ich/photos/2.jpg')),
      );

      await _aufraeumen(tester);
    });
  });

  // Die Standortermittlung: der GPS-Knopf im Bundesland-Feld.
  group('Die Standortermittlung', () {
    testWidgets('der Standort wird erkannt, gerastert und gespeichert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ortService = _FakeOrtService(position: _position());

      final container = await _pump(tester, _profil, ortService: ortService);

      expect(tester.takeException(), isNull);

      // Der GPS-Knopf sitzt am Bundesland-Feld (das steht weit unten im
      // Formular - erst dorthin scrollen).
      final gps = find.byIcon(Icons.my_location);
      expect(gps, findsOneWidget);
      await tester.scrollUntilVisible(
        gps,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);
      await tester.tap(gps);
      await _pumpFrames(tester);

      // Die Offenlegung kommt VOR der Berechtigung (das verlangt
      // Google Play) - der Nutzer muss sie bestaetigen.
      expect(
        find.text(L10n.tWithoutContext('location.disclosureTitle')),
        findsOneWidget,
        reason:
            'Ohne Offenlegung fragt die App die Berechtigung im Hintergrund '
            'ab - das verlangt Google Play nicht.',
      );
      await tester.tap(
        find.text(L10n.tWithoutContext('location.disclosureAccept')),
      );
      await _pumpFrames(tester);

      // Der Standort wurde abgefragt ...
      expect(
        ortService.abfragen,
        greaterThan(0),
        reason: 'Der Knopf muss den Standort wirklich abfragen.',
      );

      // ... und auf dem 5-km-Raster gespeichert (nicht der exakte Punkt).
      final erwartet = LocationPrivacy.snapToGrid(53.5511, 9.9937);
      final profil = container.read(profileProvider);
      expect(
        profil.locationLat,
        erwartet.lat,
        reason:
            'Der Standort muss auf dem Raster liegen - sonst speichert die '
            'App genauer, als sie verspricht.',
      );
      expect(profil.locationLng, erwartet.lng);

      // Und der Standort geht zum Server (in der Tabelle, die nur der
      // Eigentuemer lesen darf - nicht in profiles).
      final orte = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profile_locations')
          .toList();
      expect(
        orte,
        isNotEmpty,
        reason:
            'Der Standort muss zum Server - sonst sieht niemand, in der '
            'Naehe der Nutzer ist.',
      );
      expect(orte.last['lat'], erwartet.lat);

      // Und der Nutzer bekommt die Bestaetigung.
      expect(
        find.text(L10n.tWithoutContext('profile.edit.locationDetected')),
        findsOneWidget,
      );

      // Der Standort wird auch serverseitig geprueft (Massen-Fake-
      // Konten) - das muss raus.
      final pruefung =
          container.read(locationCheckServiceProvider) as _FakeStandortPruefung;
      expect(
        pruefung.aufrufe,
        isNotEmpty,
        reason:
            'Der Standort muss auch serverseitig geprueft werden - sonst '
            'faellt eine Massen-Anmeldung mit demselben Standort nicht '
            'auf.',
      );
      expect(pruefung.aufrufe.last['newLatitude'], erwartet.lat);

      await _aufraeumen(tester);
    });

    testWidgets('ohne Berechtigung wird kein Standort gespeichert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Die Berechtigung wird verweigert (der Nutzer sagt Nein zur
      // Offenlegung) - dann darf kein Standort im Profil landen.
      final ortService = _FakeOrtService(position: _position());

      final container = await _pump(tester, _profil, ortService: ortService);

      expect(tester.takeException(), isNull);

      // Der GPS-Knopf sitzt am Bundesland-Feld (das steht weit unten im
      // Formular - erst dorthin scrollen).
      final gps = find.byIcon(Icons.my_location);
      await tester.scrollUntilVisible(
        gps,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);
      await tester.tap(gps);
      await _pumpFrames(tester);

      // Die Offenlegung abbrechen.
      final abbrechen = find.text(L10n.tWithoutContext('common.cancel'));
      expect(abbrechen, findsOneWidget);
      await tester.tap(abbrechen);
      await _pumpFrames(tester);

      // Der Standort wurde NICHT abgefragt ...
      expect(ortService.abfragen, 0);
      // ... und nichts steht im Profil.
      expect(container.read(profileProvider).locationLat, isNull);

      await _aufraeumen(tester);
    });
  });
}
