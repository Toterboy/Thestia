// Das Aendern der E-Mail-Adresse auf dem Bestaetigungs-Screen.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/email_verification_screen.dart 83 offene Zeilen. Der
// Weg "Adresse aendern" (NUTZERWUNSCH 01.11.2026: "Bei Email bestaetigen
// soll die Emailadresse nochmal angezeigt werden. Falls man einen Fehler
// bemerkt, soll man an dieser Stelle die Emailadresse nochmal aendern")
// war gar nicht getestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Dialog nimmt eine neue Adresse an,
//   * das alte, unbestätigte Konto wird GELÖSCHT (sonst schlaegt die
//     Neuregistrierung mit "bereits registriert" fehl),
//   * die neue Adresse steht danach im Bildschirm.
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

/// Der Sitzungs-Speicher des Auth-Clients im RAM.
class _SitzungImRam implements supabase.LocalStorage {
  String? _session;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> persistSession(String persistSessionString) async {
    _session = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    _session = null;
  }
}

/// In-Memory-Speicher fuer die lokalen Einstellungen.
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
    server.funktionsAntworten.clear();
    // DER CLIENT: Er wird nur EINMAL initialisiert (das ist ein
    // Singleton) - deshalb hier und nicht im Test.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        autoRefreshToken: false,
        localStorage: _SitzungImRam(),
      ),
    );
  });

  /// Baut den Screen mit einem frischen Registrierungsnachweis.
  Future<ProviderContainer> zeigeScreen(WidgetTester tester) async {
    await tester.pump();

    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(_Speicher()),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(pendingVerificationEmailProvider.notifier).state =
        'neu@example.de';
    container.read(pendingVerificationCredentialsProvider.notifier).state = (
      email: 'neu@example.de',
      password: 'Passwort123!',
      createdAt: DateTime.now(),
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
  Future<void> aufraeumen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Laesst die echte Ereignisschleife laufen (die Serverantworten
  /// kommen nur dort an).
  Future<void> lassServerArbeiten(
    WidgetTester tester, {
    int runden = 12,
  }) async {
    for (var i = 0; i < runden; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('Das Aendern der Adresse', () {
    testWidgets('der Dialog nimmt die neue Adresse an', (tester) async {
      // DER SERVER ANTWORTET: Das alte Konto wird geloescht.
      server.funktionsAntworten['cancel-registration'] = <String, dynamic>{
        'deleted': true,
      };

      final container = await zeigeScreen(tester);
      // DER KNOPF: Die Adresse steht auf der Karte - daneben liegt der
      // Knopf zum Aendern.
      final knopf = find.widgetWithText(
        TextButton,
        L10n.tWithoutContext('email.changeAddress'),
      );
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
      expect(
        find.text(L10n.tWithoutContext('email.changeAddressTitle')),
        findsOneWidget,
        reason:
            'Der Dialog muss erklaeren, was passiert - sonst glaubt der '
            'Nutzer, die Adresse waere direkt geaendert.',
      );

      await aufraeumen(tester, container);
    });

    testWidgets('das alte Konto wird geloescht', (tester) async {
      server.funktionsAntworten['cancel-registration'] = <String, dynamic>{
        'deleted': true,
      };

      final container = await zeigeScreen(tester);

      final knopf = find.widgetWithText(
        TextButton,
        L10n.tWithoutContext('email.changeAddress'),
      );
      await tester.scrollUntilVisible(
        knopf,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // DIE NEUE ADRESSE: Das Feld steht im Dialog.
      await tester.enterText(find.byType(TextField).first, 'neu2@example.de');
      await tester.pump(const Duration(milliseconds: 200));

      // Der Dialog braucht einen ruhigen Frame - sonst geht der Klick
      // ins Leere.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('email.changeAddress'),
        ),
      );
      await tester.pump();

      await lassServerArbeiten(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe.any(
          (c) =>
              c['funktion'] == 'cancel-registration' &&
              c['email'] == 'neu@example.de',
        ),
        isTrue,
        reason:
            'Das alte Konto muss wirklich geloescht werden - sonst '
            'scheitert die Neuregistrierung mit "bereits registriert" und '
            'der Nutzer kommt nie aus dem Bildschirm heraus.',
      );

      await tester.pump(const Duration(seconds: 5));
      await aufraeumen(tester, container);
    });
  });
}
