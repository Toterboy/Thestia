// Der Bestaetigungs-Screen: was passiert, wenn der Registrierungs-
// nachweis abgelaufen ist.
//
// ANLASS (19.11.2026): `lib/screens/auth/email_verification_screen.dart`
// war nur zu 62 % abgedeckt. Der stille Auto-Login darf nach 15
// Minuten nicht mehr greifen (der Nachweis der Inhaberschaft ist dann
// weg) - der Nutzer muss stattdessen normal anmelden koennen.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein abgelaufener Nachweis fuehrt zur Anmeldung (mit Hinweis),
//   * der Dialog "Registrierung abbrechen" laesst sich abbrechen -
//     dann wird nichts geloescht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/email_verification_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM (der Screen liest den Nachweis daraus).
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

/// Der Router fuer den Test.
GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.emailVerification,
    routes: [
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Anmeldung'))),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Startseite'))),
      ),
    ],
  );
}

void main() {
  final server = FakeSupabaseServer(userId: 'neu');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    server.pfade.clear();
    server.funktionsAufrufe.clear();
  });

  /// Baut den Screen. [alterNachweis] setzt den Registrierungsnachweis
  /// auf ein Alter von [minuten] (der Nachweis gilt 15 Minuten).
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    int? alterNachweisMinuten,
  }) async {
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        autoRefreshToken: false,
      ),
    );
    await tester.pump();

    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );

    container.read(pendingVerificationEmailProvider.notifier).state =
        'neu@example.de';
    container.read(pendingVerificationCredentialsProvider.notifier).state = (
      email: 'neu@example.de',
      password: 'Passwort123!',
      createdAt: alterNachweisMinuten == null
          ? DateTime.now()
          : DateTime.now().subtract(Duration(minutes: alterNachweisMinuten)),
      name: 'Lena',
      gender: 'female',
      birthDate: DateTime(1996, 6, 15),
    );

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  /// Raeumt den Screen ab - er hat Timer (Auto-Login, Cooldown).
  ///
  /// Ohne das bleibt ein Timer stehen und der Test scheitert an
  /// "A Timer is still pending". DER CONTAINER GEHOERT DABEI: Der
  /// E-Mail-Bestaetigungs-Notifier pollt alle 3 Sekunden.
  Future<void> aufraeumen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Wartet, BIS ein Text da ist (das Screen-Update laeuft asynchron).
  Future<bool> warteAufText(
    WidgetTester tester,
    String text, {
    int sekunden = 10,
  }) async {
    for (var i = 0; i < sekunden * 10; i++) {
      if (find.text(text).evaluate().isNotEmpty) return true;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
    return find.text(text).evaluate().isNotEmpty;
  }

  group('Der abgelaufene Registrierungsnachweis', () {
    testWidgets('der Nutzer wird zur Anmeldung geschickt', (tester) async {
      // DER GRUND: Der stille Auto-Login darf nur mit einem FRISCHEN
      // Nachweis laufen (der Nachweis ist der Beweis der Inhaberschaft).
      // Nach 15 Minuten muss der Nutzer normal anmelden.
      final container = await zeigeScreen(tester, alterNachweisMinuten: 30);

      final weiter = find.text(L10n.tWithoutContext('email.continueBtn'));
      await tester.scrollUntilVisible(
        weiter,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(weiter);
      await tester.pump();

      final gemeldet = await warteAufText(
        tester,
        'Bitte melde dich jetzt mit E-Mail und Passwort an. '
        'Deine E-Mail-Adresse ist bereits bestätigt.',
      );
      expect(
        gemeldet,
        isTrue,
        reason:
            'Der Nutzer muss wissen, dass er sich jetzt anmelden muss - '
            'sonst wartet er auf eine Bestätigung, die nie kommt.',
      );

      await warteAufText(tester, 'Anmeldung');
      expect(
        find.text('Anmeldung'),
        findsOneWidget,
        reason: 'Ohne Nachweis gibt es nur noch die normale Anmeldung.',
      );

      // Die Meldung (SnackBar) muss verschwinden - ihr Timer wuerde sonst
      // noch laufen, wenn der Test endet.
      await tester.pump(const Duration(seconds: 5));
      await aufraeumen(tester, container);
    });
  });

  group('Der Dialog "Registrierung abbrechen"', () {
    testWidgets('laesst sich abbrechen - dann passiert nichts', (tester) async {
      final container = await zeigeScreen(tester);

      final knopf = find.text(L10n.tWithoutContext('email.cancel'));
      await tester.scrollUntilVisible(
        knopf,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(
          TextButton,
          L10n.tWithoutContext('email.cancelKeep'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        server.funktionsAufrufe.any(
          (c) => c['funktion'] == 'cancel-registration',
        ),
        isFalse,
        reason: 'Wer sich im Dialog umentscheidet, darf kein Konto loeschen.',
      );
      expect(
        find.text('Anmeldung'),
        findsNothing,
        reason: 'Der Bildschirm bleibt stehen - es ist nichts passiert.',
      );
      await aufraeumen(tester, container);
    });
  });
}
