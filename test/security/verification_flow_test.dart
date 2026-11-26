// Die Video-Verifizierung (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/screens/verification/verification_flow.dart 456 offene Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Info-Screen baut sich (kein Absturz, kein Render-Overflow),
//   * er sagt dem Nutzer, was mit dem Video passiert - und dass die
//     Altersschätzung eine KI-Schätzung ist (kein Beweis),
//   * er nennt die einmalige Standortabfrage,
//   * der Start-Knopf bringt den Code mit zur Aufnahme,
//   * der Erfolgs-Screen unterscheidet automatische Freigabe und
//     manuelle Prüfung,
//   * nach der Verifizierung wird das Abschalten der Berechtigungen
//     angeboten.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/storage/local_storage.dart';

/// Der Speicher im RAM (die Einstellungen kommen daraus).
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

/// Die Route, auf der der Erfolgs-Screen im Test liegt.
const String _erfolgRoute = '/verification/erfolg';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut einen Router mit den drei Verifizierungs-Routen.
  ///
  /// [startOrt] ist die Route, auf der der Screen liegt (mit
  /// Query-Parametern, wenn der Screen sie liest).
  GoRouter router(String startOrt) {
    return GoRouter(
      initialLocation: startOrt,
      routes: [
        GoRoute(
          path: AppRoutes.verificationInfo,
          builder: (context, state) => const VerificationInfoScreen(),
        ),
        GoRoute(
          path: AppRoutes.verificationVideo,
          builder: (context, state) => const VerificationVideoScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
        GoRoute(
          path: _erfolgRoute,
          builder: (context, state) => const VerificationSuccessScreen(),
        ),
      ],
    );
  }

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('Verifizierung (Info)', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router('${AppRoutes.verificationInfo}?code=abc');
      addTearDown(r.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(VerificationInfoScreen), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('verify.title')), findsWidgets);
    });

    testWidgets('der Screen sagt, was mit dem Video passiert', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router(AppRoutes.verificationInfo);
      addTearDown(r.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(
        find.text(L10n.tWithoutContext('verify.infoCardTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, was mit seinem Video passiert - das '
            'ist der Kern der Verifizierung.',
      );
      // Die Altersschätzung ist eine KI-Schätzung, kein Beweis - das
      // muss ihm gesagt werden.
      expect(
        find.text(L10n.tWithoutContext('verify.infoAiLimits')),
        findsOneWidget,
      );
      // Und die Standortabfrage wird genannt.
      expect(
        find.text(L10n.tWithoutContext('verify.locationTitle')),
        findsOneWidget,
      );
    });

    testWidgets('der Start-Knopf bringt den Code mit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router('${AppRoutes.verificationInfo}?code=code-42');
      addTearDown(r.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await pumpFrames(tester);

      // Der Knopf kann unterhalb der Falz liegen - erst hinschieben.
      final knopf = find.text(L10n.tWithoutContext('verify.start'));
      await tester.ensureVisible(knopf);
      await pumpFrames(tester);
      await tester.tap(knopf);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die Aufnahme-Seite ist erreicht - und der Code ist angekommen.
      // (Der Bildschirm fragt zuerst nach der Kamera-Freigabe - das ist
      // die Pflicht von Google Play.)
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        r.routerDelegate.currentConfiguration.uri.queryParameters['code'],
        'code-42',
      );
    });
  });

  group('Verifizierung (Video)', () {
    testWidgets('die Kamera-Offenlegung kommt zuerst', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router(AppRoutes.verificationVideo);
      addTearDown(r.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Google Play verlangt die Offenlegung VOR dem Systemdialog - der
      // Nutzer muss wissen, warum die App filmen will.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('verify.cameraDisclosureTitle')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Freigabe sagt die App es ebenfalls', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router(AppRoutes.verificationVideo);
      addTearDown(r.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Die Offenlegung ablehnen.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          L10n.tWithoutContext('verify.cameraDeclined').split(' ').first,
        ),
        findsWidgets,
        reason:
            'Auch ein Ablehnen muss erklaert werden - sonst weiss der '
            'Nutzer nicht, warum die Aufnahme nicht startet.',
      );
    });
  });

  group('Verifizierung (Erfolg)', () {
    /// Baut den Erfolgs-Screen mit dem angegebenen Ergebnis.
    Future<ProviderContainer> zeigeErfolg(
      WidgetTester tester, {
      String? ergebnis,
      String? grund,
      double? abweichung,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final r = router(_erfolgRoute);
      addTearDown(r.dispose);

      final container = ProviderContainer(
        overrides: [
          verificationResultProvider.overrideWith((ref) => ergebnis),
          verificationPendingReasonProvider.overrideWith((ref) => grund),
          verificationDeviationProvider.overrideWith((ref) => abweichung),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: r,
          ),
        ),
      );
      await pumpFrames(tester);
      return container;
    }

    testWidgets('die automatische Freigabe steht da', (tester) async {
      await zeigeErfolg(tester, ergebnis: 'auto');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('verify.autoTitle')),
        findsOneWidget,
      );
      // Der Erfolgs-Screen sagt klar, dass es durch ist.
      expect(find.text(L10n.tWithoutContext('verify.toApp')), findsOneWidget);
    });

    testWidgets('die manuelle Pruefung steht da', (tester) async {
      await zeigeErfolg(
        tester,
        ergebnis: 'pending',
        grund: 'verify.pendingReasonDeviation',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('verify.pendingTitle')),
        findsOneWidget,
      );
    });

    testWidgets('das Abschalten der Berechtigungen wird angeboten', (
      tester,
    ) async {
      await zeigeErfolg(tester, ergebnis: 'auto');

      // Der Hinweis kommt nach 600 ms.
      await tester.pump(const Duration(milliseconds: 700));
      await pumpFrames(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('verify.cleanupTitle')),
        findsOneWidget,
      );

      // "Später" schließt den Dialog - und fasst nichts an.
      await tester.tap(find.text(L10n.tWithoutContext('verify.cleanupLater')));
      await pumpFrames(tester);

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
