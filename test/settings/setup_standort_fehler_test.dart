// Die Standort-Erkennung in der Einrichtung.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/onboarding/parts/locationnotice.dart 0 % Abdeckung. Der
// Kasten sagt dem neuen Nutzer, warum kein Bundesland im Profil steht -
// ohne ihn bleibt der Screen still und der Nutzer wundert sich.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne GPS kommt der Hinweis "Standort nicht erkannt",
//   * ein Standort, der vom bisherigen Geraet abweicht, kommt mit dem
//     Verdachts-Hinweis.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:thestia/services/profile/location_verification_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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
class _Berechtigungen extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: PermissionStatus.granted};
}

/// Der Ort-Dienst im Test.
class _OrtDienst extends LocationVerificationService {
  _OrtDienst({this.position, this.verdaechtig = false});

  /// Die Position, die der Dienst meldet (null = kein Standort).
  final Position? position;

  /// Ist der Standort "verdaechtig"?
  final bool verdaechtig;

  @override
  Future<Position?> getCurrentLocation() async => position;

  @override
  Future<bool> isLocationSuspicious(
    Position newPosition, {
    double thresholdMeters = 100,
  }) async => verdaechtig;
}

/// Die Position, die der Test meldet.
Position _position() => Position(
  latitude: 53.5511,
  longitude: 9.9937,
  timestamp: DateTime(2026, 11, 22),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    mockAufnahme();
    PermissionHandlerPlatform.instance = _Berechtigungen();
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut die Einrichtung mit dem Ort-Dienst.
  Future<void> zeigeScreen(
    WidgetTester tester,
    LocationVerificationService ortDienst,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/setup',
      routes: [
        GoRoute(
          path: '/setup',
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          locationVerificationServiceProvider.overrideWithValue(ortDienst),
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
    await pumpFrames(tester);
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
    await tester.tap(
      find.text(L10n.tWithoutContext('location.disclosureAccept')),
    );
    await pumpFrames(tester);
  }

  group('Die Standort-Erkennung in der Einrichtung', () {
    testWidgets('ohne GPS kommt der Hinweis "nicht erkannt"', (tester) async {
      await zeigeScreen(tester, _OrtDienst());

      await tippeOrtErkennung(tester);

      expect(
        find.text(L10n.tWithoutContext('setup.locationDetectFail')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, warum kein Bundesland gefunden wurde - '
            'sonst bleibt der Screen still.',
      );
    });

    testWidgets('ein abweichender Standort wird als verdächtig gemeldet', (
      tester,
    ) async {
      await zeigeScreen(
        tester,
        _OrtDienst(position: _position(), verdaechtig: true),
      );

      await tippeOrtErkennung(tester);

      expect(
        find.text(L10n.tWithoutContext('setup.locationSuspicious')),
        findsOneWidget,
        reason:
            'Ein Standort weit vom bisherigen Geraet ist ein Muster von '
            'Massen-Konten - der Nutzer muss darauf hingewiesen werden.',
      );
    });
  });
}
