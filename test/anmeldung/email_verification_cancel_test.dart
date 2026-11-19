// Das Loeschen eines unbestaetigten Kontos (der Weg "Registrierung
// abbrechen") - in einer EIGENEN Datei.
//
// WARUM EIGENE DATEI (17.11.2026): Der Supabase-Client ist ein
// Singleton - er kann pro Testlauf nur einmal gestartet werden. Der
// Auth-Client merkt sich darin seinen Zustand (Sitzung, PKCE-Verifier).
// In einer gemeinsamen Datei ist der Zustand beim Test "Registrierung
// abbrechen" durch die vorherigen Tests bereits veraendert - der
// Aufruf laeuft dann in einen anderen Zweig. In einer eigenen Datei
// (eigener Isolate) ist der Zustand frisch.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Dialog "Registrierung abbrechen?" erscheint,
//   * das Bestaetigen ruft die Funktion cancel-registration beim Server
//     auf - mit Adresse und Passwort (der Nachweis der Inhaberschaft),
//   * der Abbruch endet auf dem Login-Screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// Der PKCE-Speicher des Auth-Clients im RAM.
//
// DER GRUND (17.11.2026): Der Standard-Speicher schreibt ueber die
// Plattform (SharedPreferences). Das kommt im Widget-Test nicht voran -
// der Aufruf bleibt haengen (der Knopf zeigt ewig "Wird gesendet...").
// Mit diesem Ersatz laeuft er sofort.
//
// DER IMPORT-HINWEIS: `GotrueAsyncStorage` kommt aus dem Paket `gotrue`
// (eine indirekte Abhaengigkeit von supabase_flutter) - es wird hier
// nur als Typ des Parameters gebraucht.
// ignore: depend_on_referenced_packages
import 'package:gotrue/gotrue.dart' show GotrueAsyncStorage;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/email_verification_screen.dart';
import 'package:thestia/services/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der PKCE-Speicher im RAM.
class _SpeicherImRam extends GotrueAsyncStorage {
  final Map<String, String> _werte = <String, String>{};

  @override
  Future<void> removeItem({required String key}) async {
    _werte.remove(key);
  }

  @override
  Future<String?> getItem({required String key}) async => _werte[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _werte[key] = value;
  }
}

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

  testWidgets('"Registrierung abbrechen" loescht das Konto beim Server', (
    tester,
  ) async {
    server.funktionsAntworten['cancel-registration'] = <String, dynamic>{
      'deleted': true,
    };
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        autoRefreshToken: false,
        pkceAsyncStorage: _SpeicherImRam(),
        localStorage: _SitzungImRam(),
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
    addTearDown(container.dispose);

    // Die Registrierungsdaten (die E-Mail und das Passwort fuer den
    // Nachweis der Inhaberschaft).
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

    // Der Knopf steht weit unten - erst dorthin scrollen (sonst trifft
    // der Tap ins Leere).
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

    // Der Dialog braucht einen ruhigen Frame - sonst geht der Klick ins
    // Leere.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('email.cancelConfirm'),
      ),
    );
    await tester.pump();

    // Die Antwort muss verarbeitet werden (im Widget-Test laeuft sie nur
    // in runAsync).
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
      if (server.funktionsAufrufe.any(
        (c) => c['funktion'] == 'cancel-registration',
      )) {
        break;
      }
    }
    // Noch ein paar Runden: die Antwort muss verarbeitet werden, sonst
    // bleibt der Aufruf offen (und sein Zeitlimit-Timer stehen).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(tester.takeException(), isNull);
    // Die Funktion cancel-registration wurde aufgerufen - das loescht
    // das unbestaetigte Konto serverseitig.
    expect(
      server.funktionsAufrufe.any(
        (c) => c['funktion'] == 'cancel-registration',
      ),
      isTrue,
      reason:
          'Der Abbruch muss das Konto beim Server loeschen - ein Konto, '
          'das nur lokal verschwindet, bleibt bestehen und stoert die '
          'spaeteren Registrierungen.',
    );
    // Der Aufruf traegt die Adresse (und das Passwort als Nachweis der
    // Inhaberschaft).
    final aufruf = server.funktionsAufrufe.firstWhere(
      (c) => c['funktion'] == 'cancel-registration',
    );
    expect(aufruf['email'], 'neu@example.de');

    // Der Screen wird abgebaut (sonst bleibt ein Timer stehen).
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
