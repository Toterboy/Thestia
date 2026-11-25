// Der Abschluss der Ersteinrichtung: die Standort-Erkennung und der
// Weg zum Ende.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/onboarding/parts/einrichtungabschluss.dart 57 offene
// Zeilen - der groesste Teil davon war die Standort-Erkennung.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Standort landet auf dem 5-km-Raster (sonst speichert die
//     App genauer, als sie verspricht),
//   * das erkannte Bundesland steht im Profil und wird dem Server
//     gemeldet,
//   * die Koordinaten gehen in profile_locations - die einzige
//     Tabelle, in der die genauen Werte liegen und die nur der
//     Eigentuemer lesen darf,
//   * der Standort wird auch serverseitig geprueft (Massen-Konten),
//   * ohne Geocoder-Treffer ratet die App nicht, sondern sagt dem
//     Nutzer, dass er das Bundesland selbst waehlt,
//   * ein Serverfehler blockiert die Einrichtung nicht (Best-Effort),
//   * ein Fehler bei der Ortung wird dem Nutzer gemeldet,
//   * der Hinweis auf den zweiten Faktor fuehrt auf die 2FA-Seite,
//   * der Abschluss sichert den Stand der Einrichtung und die
//     Praeferenzen beim Server.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:thestia/services/auth/mfa_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/profile/location_check_service.dart';
import 'package:thestia/services/profile/location_verification_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/location/location_privacy.dart';

// Die Attrappen des Profil-Editors (mit Praefix, damit hier nichts
// kollidiert): der Ort-Dienst und die Standort-Pruefung.
import '../profile_edit_screen/hilfen.dart' as attrappen;
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - der Screen schreibt Bio, Interessen usw. dorthin.
class _Speicher implements LocalStorage {
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

/// Der Keystore ohne Plugin.
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Die Berechtigungen im Test.
///
/// DER GRUND: Die Standort-Berechtigung ist im Test nicht erteilt. So
/// erscheint die Offenlegung (die vor der Berechtigung kommen muss -
/// das verlangt Google Play) und der Weg laesst sich pruefen.
class _Berechtigungen extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: PermissionStatus.granted};
}

/// Der Geokoder-Ersatz: er liefert das Bundesland zu einer Position.
///
/// DER GRUND: Der echte Geocoder laeuft nur auf Android und iOS. Ohne
/// den Ersatz liefert er im Test nichts - die App wuerde nie ein
/// Bundesland finden und der Weg waere ungetestet.
class _Geocoder extends GeocodingPlatform {
  _Geocoder(this.bundesland);

  /// Das Bundesland, das der Geocoder meldet (null = kein Treffer).
  final String? bundesland;

  /// Die Koordinaten, die abgefragt wurden.
  final List<({double lat, double lng})> anfragen =
      <({double lat, double lng})>[];

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    anfragen.add((lat: latitude, lng: longitude));
    final bundesland = this.bundesland;
    if (bundesland == null) return <Placemark>[];
    return <Placemark>[
      Placemark(administrativeArea: bundesland, country: 'Deutschland'),
    ];
  }
}

/// Der Ort-Dienst, der abstuerzt (der Fehlerfall der Ortung).
class _FehlerOrtDienst extends attrappen.FakeOrtService {
  _FehlerOrtDienst() : super();

  @override
  Future<Position?> getCurrentLocation() async {
    throw StateError('Das GPS liefert keine Position.');
  }
}

/// Die Position, die der Test meldet (Hamburg).
Position _position() => Position(
  latitude: 53.5511,
  longitude: 9.9937,
  timestamp: DateTime(2026, 11, 25),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );

    // HIVE: die verschluesselten Schluessel (Signal-Protokoll) liegen in
    // Hive-Boxen - ohne initialisierten Hive schlaegt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_abschluss');
    Hive.init(tempDir.path);

    // ANGEMELDET: Ohne Sitzung gibt der Server-Dienst nichts frei
    // ("Nicht eingeloggt") - es wuerde nichts gespeichert.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    // DIE AUFNAHME: die Vorstellung kann mit Stimme aufgenommen werden -
    // ohne den Ersatz wartet der Aufruf endlos.
    mockAufnahme();
    PermissionHandlerPlatform.instance = _Berechtigungen();
    server.schreibvorgaenge.clear();
    server.zeilen.clear();
    server.fehlerAntworten.clear();
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut die Ersteinrichtung und liefert den Container der Provider.
  ///
  /// [ortDienst] ist der Dienst, der den Standort meldet. [geocoder]
  /// liefert das Bundesland zu einer Position. [pruefung] merkt sich die
  /// Aufrufe der Standort-Pruefung. [mitMfa] meldet einen bereits
  /// eingerichteten zweiten Faktor - dann fragt die App beim Abschluss
  /// nicht mehr nach.
  Future<ProviderContainer> zeigeEinrichtung(
    WidgetTester tester, {
    LocationVerificationService? ortDienst,
    _Geocoder? geocoder,
    attrappen.FakeStandortPruefung? pruefung,
    bool mitMfa = false,
  }) async {
    final dienst = ortDienst ?? attrappen.FakeOrtService(position: _position());
    final geokoder = geocoder ?? _Geocoder('Hamburg');
    final standortPruefung =
        pruefung ?? attrappen.FakeStandortPruefung(SupabaseService.client);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/einrichtung',
      routes: [
        GoRoute(
          path: '/einrichtung',
          builder: (context, state) => const SettingsPrivacyOnceScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    // DER GEOCODER: das Bundesland zu einer Position.
    GeocodingPlatform.instance = geokoder;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          // Der Ort-Dienst: im Test gibt es kein GPS.
          locationVerificationServiceProvider.overrideWithValue(dienst),
          // Die Standort-Pruefung (Edge Function) - der Ersatz merkt
          // sich die Aufrufe.
          locationCheckServiceProvider.overrideWith((ref) => standortPruefung),
          // Der zweite Faktor: mit ihm fragt die App beim Abschluss nicht
          // mehr nach Passkey oder 2FA.
          if (mitMfa)
            mfaStatusProvider.overrideWith(
              (ref) => const MfaStatus(
                currentAal: 'aal2',
                hasVerifiedFactors: true,
                hasAnyFactor: true,
                loaded: true,
              ),
            ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                birthDate: DateTime(DateTime.now().year - 30, 5, 4),
              ),
            );
            return notifier;
          }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsPrivacyOnceScreen)),
    );
  }

  /// Tippt auf "Weiter" und wartet die Seitenanimation ab.
  Future<void> weiter(WidgetTester tester) async {
    await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
    await pumpFrames(tester);
  }

  /// Geht durch alle zehn Schritte bis zur letzten Seite.
  ///
  /// Schritt 2 (Profil) hat Pflichtangaben - ohne Bio und Interesse geht
  /// der "Weiter"-Knopf nicht weiter.
  Future<void> geheBisZumLetztenSchritt(WidgetTester tester) async {
    await weiter(tester);

    // Schritt 2: Bio und Interesse.
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich mag lange Spaziergaenge am Fluss.',
    );
    await pumpFrames(tester);
    final chip = find.widgetWithText(FilterChip, 'Sport');
    await tester.ensureVisible(chip);
    await pumpFrames(tester);
    await tester.tap(chip);
    await pumpFrames(tester);
    await weiter(tester);

    // Schritt 3: die Vorstellung (der Text ist Pflicht).
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich bin gern draussen unterwegs.',
    );
    await pumpFrames(tester);
    await weiter(tester);

    // Die Schritte 4 bis 9 kommen ohne weitere Pflichtangabe.
    for (var i = 0; i < 6; i++) {
      await weiter(tester);
    }
  }

  /// Tippt auf den Abschluss-Knopf (auf der letzten Seite).
  Future<void> tippeAbschluss(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('setupp.finish'));
    await tester.ensureVisible(knopf);
    await pumpFrames(tester);
    await tester.tap(knopf);
    await pumpFrames(tester);
  }

  /// Wartet, bis die Server-Anfragen durch sind.
  Future<void> warteAufServer(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Tippt auf "Bundesland erkennen" und bestaetigt die Offenlegung.
  Future<void> tippeOrtErkennung(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('setupp.detectState'));
    await tester.scrollUntilVisible(
      knopf,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(knopf);
    await pumpFrames(tester);

    // DIE OFFENLEGUNG: Sie kommt VOR der Berechtigung (das verlangt
    // Google Play) - ohne sie passiert gar nichts.
    final annehmen = find.text(
      L10n.tWithoutContext('location.disclosureAccept'),
    );
    expect(
      annehmen,
      findsOneWidget,
      reason: 'Ohne Offenlegung fragt die App den Standort nicht ab.',
    );
    await tester.tap(annehmen);
    await pumpFrames(tester);
    await warteAufServer(tester);
  }

  /// Laesst die Timer (die Meldung, die entprellten Syncs) ablaufen -
  /// sonst steht am Testende ein offener Timer.
  Future<void> lassTimerLaufen(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Die Standort-Erkennung in der Ersteinrichtung', () {
    testWidgets('der Standort wird gerastert und das Bundesland gespeichert', (
      tester,
    ) async {
      final geocoder = _Geocoder('Hamburg');
      final ortDienst = attrappen.FakeOrtService(position: _position());
      final pruefung = attrappen.FakeStandortPruefung(SupabaseService.client);

      final container = await zeigeEinrichtung(
        tester,
        ortDienst: ortDienst,
        geocoder: geocoder,
        pruefung: pruefung,
      );

      await tippeOrtErkennung(tester);

      expect(tester.takeException(), isNull);

      // DAS RASTER: der Standort darf nicht der exakte Punkt sein.
      final erwartet = LocationPrivacy.snapToGrid(53.5511, 9.9937);
      expect(
        erwartet.lat,
        isNot(53.5511),
        reason: 'Das Raster muss den Standort wirklich verschieben.',
      );

      // Der Geocoder wurde mit den GERUNDETEN Koordinaten gefragt - so
      // soll es sein (das Bundesland des Rasterpunkts).
      expect(
        geocoder.anfragen,
        isNotEmpty,
        reason: 'Das Bundesland muss ermittelt werden.',
      );
      expect(geocoder.anfragen.last.lat, erwartet.lat);
      expect(geocoder.anfragen.last.lng, erwartet.lng);

      // Das Profil traegt das Bundesland und die gerasterten Koordinaten.
      final profil = container.read(profileProvider);
      expect(profil.state, 'Hamburg');
      expect(
        profil.locationLat,
        erwartet.lat,
        reason:
            'Der Standort muss auf dem Raster liegen - sonst speichert die '
            'App genauer, als sie verspricht.',
      );
      expect(profil.locationLng, erwartet.lng);

      // DIE KOORDINATEN: sie gehen in profile_locations - die einzige
      // Tabelle, in der die genauen Werte liegen und die nur der
      // Eigentuemer lesen darf.
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
      expect(orte.last['lng'], erwartet.lng);
      expect(orte.last['user_id'], 'ich');

      // DAS BUNDESLAND: der Server muss es kennen - sonst ueberschreibt
      // ein spaeterer Profil-Sync den Wert wieder mit leer.
      final profilWrites = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profiles' && v.containsKey('state'))
          .toList();
      expect(
        profilWrites,
        isNotEmpty,
        reason: 'Das Bundesland muss zum Server.',
      );
      expect(profilWrites.last['state'], 'Hamburg');

      // DIE SERVERSEITIGE PRUEFUNG: sie findet Massen-Konten.
      expect(
        pruefung.aufrufe,
        isNotEmpty,
        reason:
            'Der Standort muss auch serverseitig geprueft werden - sonst '
            'faellt eine Massen-Anmeldung mit demselben Standort nicht auf.',
      );
      expect(pruefung.aufrufe.last['userId'], 'ich');
      expect(pruefung.aufrufe.last['newLatitude'], erwartet.lat);
      expect(pruefung.aufrufe.last['newLongitude'], erwartet.lng);

      // UND DER NUTZER BEKOMMT DIE BESTAETIGUNG.
      expect(
        find.text(L10n.tWithoutContext('setup.locationDone')),
        findsOneWidget,
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('ohne Treffer wird kein Bundesland geraten', (tester) async {
      final geocoder = _Geocoder(null);
      final ortDienst = attrappen.FakeOrtService(position: _position());
      final pruefung = attrappen.FakeStandortPruefung(SupabaseService.client);

      final container = await zeigeEinrichtung(
        tester,
        ortDienst: ortDienst,
        geocoder: geocoder,
        pruefung: pruefung,
      );

      await tippeOrtErkennung(tester);

      expect(tester.takeException(), isNull);

      // NICHTS RATEN: ein erfundenes Bundesland waere schlimmer als
      // keines - der Nutzer waehlt es selbst.
      final profil = container.read(profileProvider);
      expect(
        profil.state,
        isNull,
        reason: 'Ohne Treffer darf kein Bundesland erfunden werden.',
      );

      // Der Server bekommt "kein Bundesland" - nicht einen erfundenen Wert.
      final profilWrites = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profiles' && v.containsKey('state'))
          .toList();
      expect(profilWrites, isNotEmpty);
      expect(profilWrites.last['state'], isNull);

      // Der Standort selbst wird trotzdem gespeichert - nur das
      // Bundesland fehlt.
      final orte = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profile_locations')
          .toList();
      expect(orte, isNotEmpty);

      // UND DER NUTZER WEISS ES: er soll das Bundesland selbst waehlen.
      expect(
        find.text(L10n.tWithoutContext('setup.locationStateUnknown')),
        findsOneWidget,
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('ein Serverfehler blockiert die Erkennung nicht', (
      tester,
    ) async {
      // DER SERVER SCHWEIGT - aber nur bei der Tabelle mit den
      // Koordinaten. Das Profil (das Bundesland) geht noch durch.
      server.fehlerAntworten['/rest/v1/profile_locations'] = (
        status: 500,
        body: '{"message":"Serverfehler"}',
      );

      final geocoder = _Geocoder('Hamburg');
      final ortDienst = attrappen.FakeOrtService(position: _position());
      final pruefung = attrappen.FakeStandortPruefung(SupabaseService.client);

      final container = await zeigeEinrichtung(
        tester,
        ortDienst: ortDienst,
        geocoder: geocoder,
        pruefung: pruefung,
      );

      await tippeOrtErkennung(tester);

      expect(tester.takeException(), isNull);

      // Das Profil traegt den Standort - lokal ist er gesichert.
      final profil = container.read(profileProvider);
      expect(profil.state, 'Hamburg');
      expect(profil.locationLat, isNotNull);

      // Und der Nutzer bekommt die Bestaetigung: ein Serverfehler darf
      // den Ablauf nicht stoppen (der Standort-Sync ist Best-Effort).
      expect(
        find.text(L10n.tWithoutContext('setup.locationDone')),
        findsOneWidget,
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('ein Fehler bei der Ortung kommt beim Nutzer an', (
      tester,
    ) async {
      final geocoder = _Geocoder('Hamburg');
      final ortDienst = _FehlerOrtDienst();
      final pruefung = attrappen.FakeStandortPruefung(SupabaseService.client);

      await zeigeEinrichtung(
        tester,
        ortDienst: ortDienst,
        geocoder: geocoder,
        pruefung: pruefung,
      );

      await tippeOrtErkennung(tester);

      expect(tester.takeException(), isNull);

      expect(
        find.textContaining('Fehler bei der Standortermittlung'),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass die Ortung fehlgeschlagen ist - '
            'sonst bleibt der Screen still.',
      );

      // Und es wurde nichts gespeichert - ein Fehler darf keine
      // halbfertigen Daten hinterlassen.
      final orte = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profile_locations')
          .toList();
      expect(orte, isEmpty);

      await lassTimerLaufen(tester);
    });
  });

  group('Der Abschluss der Ersteinrichtung', () {
    testWidgets('"2FA einrichten" springt zur 2FA-Seite', (tester) async {
      await zeigeEinrichtung(tester);
      await geheBisZumLetztenSchritt(tester);

      await tippeAbschluss(tester);

      // DER HINWEIS: ohne Passkey und ohne 2FA fragt die App nach - das
      // muss sie DEUTLICH sagen, statt es zu verschweigen.
      expect(
        find.text(L10n.tWithoutContext('setup.nudgeTitle')),
        findsOneWidget,
      );

      // Der Weg zur 2FA-Seite ist offen - der Nutzer soll sie direkt
      // erreichen koennen.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('setup.nudgeMfa')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Schritt 9 von 10'),
        findsOneWidget,
        reason: 'Der Nutzer muss auf der 2FA-Seite landen.',
      );
      expect(
        find.text('Startseite'),
        findsNothing,
        reason: 'Die Einrichtung ist noch nicht abgeschlossen.',
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('mit 2FA wird die Einrichtung direkt abgeschlossen', (
      tester,
    ) async {
      final container = await zeigeEinrichtung(tester, mitMfa: true);
      await geheBisZumLetztenSchritt(tester);

      await tippeAbschluss(tester);

      // MIT EINEM ZWEITEN FAKTOR fragt die App nicht mehr nach - der
      // Abschluss laeuft direkt.
      expect(
        find.text(L10n.tWithoutContext('setup.nudgeTitle')),
        findsNothing,
        reason:
            'Mit einem eingerichteten zweiten Faktor gibt es nichts mehr '
            'nachzufragen.',
      );

      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      // DER STAND DER EINRICHTUNG: er muss beim Server stehen - sonst
      // erscheint die Einrichtung nach der naechsten Anmeldung wieder.
      final flagWrites = server.schreibvorgaenge
          .where(
            (v) =>
                v['tabelle'] == 'profiles' &&
                v.containsKey('one_time_settings_completed'),
          )
          .toList();
      expect(
        flagWrites,
        isNotEmpty,
        reason: 'Der Stand der Einrichtung muss beim Server stehen.',
      );
      expect(flagWrites.last['one_time_settings_completed'], isTrue);
      expect(flagWrites.last['community_guidelines_accepted'], isTrue);

      // DIE PRAEFERENZEN: sie stehen auch am Server - sonst waeren sie
      // nach der Neuinstallation weg.
      final prefWrites = server.schreibvorgaenge
          .where(
            (v) =>
                v['tabelle'] == 'profiles' && v.containsKey('max_distance_km'),
          )
          .toList();
      expect(
        prefWrites,
        isNotEmpty,
        reason:
            'Die Praeferenzen muessen zum Server - "Nichts geht verloren" '
            'gilt auch fuer den Suchradius.',
      );

      // Lokal ist die Einrichtung als erledigt markiert.
      expect(container.read(settingsProvider).oneTimeSettingsCompleted, isTrue);

      // UND DIE APP LANDET AUF DER STARTSEITE.
      expect(find.text('Startseite'), findsOneWidget);

      await lassTimerLaufen(tester);
    });

    testWidgets('ein Serverfehler beim Sichern der Flags wird gemeldet', (
      tester,
    ) async {
      // DER SERVER SCHWEIGT: alle Schreibvorgaenge auf "profiles" gehen
      // ins Leere. Das ist der Fall, der frueher still passierte - der
      // Nutzer sah nichts und die Einrichtung kam beim naechsten Login
      // wieder.
      server.fehlerAntworten['/rest/v1/profiles'] = (
        status: 500,
        body: '{"message":"Serverfehler"}',
      );

      await zeigeEinrichtung(tester, mitMfa: true);
      await geheBisZumLetztenSchritt(tester);

      await tippeAbschluss(tester);

      // DER ABSCHLUSS VERSUCHT ES MEHRMALS: zwischen den Versuchen
      // liegen Wartezeiten (1 s, 2 s). Die Meldung erscheint erst
      // danach - der Test wartet darauf (und faengt sie ab, bevor sie
      // von selbst wieder verschwindet).
      var gemeldet = false;
      for (var i = 0; i < 40 && !gemeldet; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 250));
        gemeldet = find
            .text(L10n.tWithoutContext('setup.flagsWarn'))
            .evaluate()
            .isNotEmpty;
      }

      expect(tester.takeException(), isNull);

      expect(
        gemeldet,
        isTrue,
        reason:
            'Der Nutzer muss erfahren, dass der Stand der Einrichtung nicht '
            'gesichert wurde - sonst kommt die Einrichtung unerwartet '
            'wieder.',
      );

      // Und die Einrichtung ist trotzdem beendet - der Nutzer landet auf
      // der Startseite.
      await pumpFrames(tester);
      expect(find.text('Startseite'), findsOneWidget);

      await lassTimerLaufen(tester);
    });
  });
}
