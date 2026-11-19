// Die Modus-Auswahl ("Entdecken") - bisher voellig ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/swipe_mode_selection_screen.dart 175 offene Zeilen
// bei 176 Zeilen gesamt - der Bildschirm, ueber den die Nutzer ihre
// Entdeckungs-Modi waehlen, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm zeigt alle Modi (in Gruppen),
//   * ein Modus laesst sich oeffnen,
//   * Transit Spark ist ohne Verifizierung gesperrt - und der Dialog
//     bietet den Weg zur Verifizierung an (statt den Modus zu
//     verstecken: sonst weiss der Nutzer nicht, dass es ihn gibt),
//   * mit Verifizierung ist Transit Spark frei,
//   * Transit Spark ist unter 18 gesperrt (Altersgrenze).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/swipe_mode_selection_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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

/// Der Keystore ohne Plugin (das Profil liegt nur im RAM).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut den Bildschirm mit einem Profil.
  ///
  /// [verifiziert] = true heisst: die Identitaet ist geprueft (der
  /// Modus "Transit Spark" ist dann frei).
  /// [geburtsdatum] entscheidet ueber die Altersgrenze.
  Future<GoRouter> zeigeScreen(
    WidgetTester tester, {
    bool verifiziert = false,
    DateTime? geburtsdatum,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/entdecken',
      routes: [
        GoRoute(
          path: '/entdecken',
          builder: (context, state) => const SwipeModeSelectionScreen(),
        ),
        GoRoute(
          path: AppRoutes.findYourMatch,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Ziel Find your Spark'))),
        ),
        GoRoute(
          path: AppRoutes.datingHourEvent,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Ziel Dating Hour'))),
        ),
        GoRoute(
          path: AppRoutes.randomChat,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Ziel Zufallschat'))),
        ),
        GoRoute(
          path: AppRoutes.qrScan,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Ziel QR-Scan'))),
        ),
        GoRoute(
          path: AppRoutes.transitRadar,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Ziel Transit Spark'))),
        ),
        GoRoute(
          path: AppRoutes.verificationInfo,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Verifizierung'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _FakeLocalStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
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
                birthDate:
                    geburtsdatum ?? DateTime(DateTime.now().year - 30, 5, 4),
                verificationState: verifiziert
                    ? VerificationState.verified
                    : VerificationState.unverified,
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
    await tester.pump(const Duration(milliseconds: 300));
    return router;
  }

  group('Die Modus-Auswahl', () {
    testWidgets('alle Modi stehen da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Die drei Gruppen (nach Zweck sortiert).
      expect(find.text(L10n.tWithoutContext('dm.groupMeet')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('dm.groupDirect')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dm.groupOnTheGo')),
        findsOneWidget,
      );
      // Und die fuenf Modi.
      for (final modus in [
        'findMatch',
        'datingHour',
        'randomChat',
        'qrScan',
        'transitSpark',
      ]) {
        expect(
          find.byKey(ValueKey('mode-tile-$modus')),
          findsOneWidget,
          reason: 'Der Modus $modus muss erreichbar sein.',
        );
      }
    });

    testWidgets('ein Modus laesst sich oeffnen', (tester) async {
      // VERIFIZIERT: Find your Spark ist gesperrt, solange das Alter
      // nicht mit einem Video bestaetigt ist (v0.10.0).
      await zeigeScreen(tester, verifiziert: true);

      await tester.tap(find.byKey(const ValueKey('mode-tile-findMatch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Ziel Find your Spark'), findsOneWidget);
    });

    testWidgets('ohne Verifizierung ist Find your Spark gesperrt', (
      tester,
    ) async {
      await zeigeScreen(tester, verifiziert: false);

      await tester.tap(find.byKey(const ValueKey('mode-tile-findMatch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Dialog sagt, warum - und bietet den Weg zur Verifizierung.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('dm.lockedTitle')), findsOneWidget);
    });

    testWidgets('Transit Spark ist ohne Verifizierung gesperrt', (
      tester,
    ) async {
      await zeigeScreen(tester, verifiziert: false);

      // Die Kachel ist da (der Modus existiert) - aber gesperrt.
      expect(
        find.byKey(const ValueKey('mode-tile-transitSpark')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mode-tile-transitSpark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Dialog sagt, warum - und bietet den Weg zur Verifizierung.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('dm.lockedTitle')), findsOneWidget);
      // Der Weg zur Verifizierung.
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('dm.lockedAction'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Verifizierung'), findsOneWidget);
    });

    testWidgets('mit Verifizierung ist Transit Spark frei', (tester) async {
      await zeigeScreen(tester, verifiziert: true);

      await tester.tap(find.byKey(const ValueKey('mode-tile-transitSpark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Kein Sperr-Dialog - der Modus geht auf.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Ziel Transit Spark'), findsOneWidget);
    });

    testWidgets('Transit Spark ist unter 18 gesperrt', (tester) async {
      await zeigeScreen(
        tester,
        verifiziert: true,
        geburtsdatum: DateTime(DateTime.now().year - 16, 5, 4),
      );

      await tester.tap(find.byKey(const ValueKey('mode-tile-transitSpark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Alters-Hinweis steht da.
      expect(find.byType(AlertDialog), findsOneWidget);
      // Und der Modus geht NICHT auf.
      expect(find.text('Ziel Transit Spark'), findsNothing);
    });
  });
}
