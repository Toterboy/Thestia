// Der Ablauf auf dem E-Mail-Bestätigungs-Screen: der Cooldown nach
// "Erneut senden", der Fehler beim Versand und das Ende des Abbruchs.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/screens/auth/email_verification_screen.dart 76 offene Zeilen. Der
// Weg nach dem Abbruch der Registrierung (der Hinweis und der Sprung
// zum Login) und der Cooldown nach dem erneuten Versand waren nicht
// getestet - genau die Stellen, an denen der Nutzer den Erfolg oder
// den Fehler sieht.
//
// WARUM EIGENE DATEI: Der Supabase-Client ist ein Singleton - pro
// Testlauf kann er nur einmal gestartet werden. Der Auth-Client merkt
// sich darin seinen Zustand (Sitzung, PKCE-Verifier). In einer eigenen
// Datei (eigener Isolate) ist der Zustand frisch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// Der PKCE-Speicher des Auth-Clients im RAM (siehe unten).
// ignore_for_file: depend_on_referenced_packages
import 'package:gotrue/gotrue.dart' show GotrueAsyncStorage;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/email_verification_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der PKCE-Speicher des Auth-Clients im RAM.
///
/// DER GRUND: Der Standard-Speicher schreibt über die Plattform
/// (SharedPreferences). Im Widget-Test kommt das nicht voran - der
/// Aufruf bleibt hängen. Mit diesem Ersatz läuft er sofort.
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

/// In-Memory-Speicher für die lokalen Einstellungen.
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

/// Der Router für den Test.
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    // DER CLIENT EINMAL: Supabase ist ein Singleton - ein zweites
    // "initialize" im selben Testlauf bringt den Router durcheinander
    // (der Test landet auf einer unbekannten Adresse).
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
  });

  setUp(() async {
    server.pfade.clear();
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
    server.fehlerAntworten.clear();
    // DER STILLE LOGIN SCHLÄGT IMMER FEHL: Sonst meldet der
    // Fake-Server jede Anmeldung als Erfolg - der Bildschirm würde
    // dann zur Startseite navigieren, während der Test noch den
    // Bestätigungs-Screen prüft.
    server.fehlerAntworten['/auth/v1/token'] = (
      status: 400,
      body: '{"error":"invalid_grant","msg":"Invalid login credentials"}',
    );
  });

  /// Baut den Screen (mit den Registrierungsdaten im Speicher).
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    bool mitRegistrierung = true,
  }) async {
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

    if (mitRegistrierung) {
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
    }

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

  /// Räumt den Screen ab - er hat Timer (Auto-Login, Cooldown, "gesendet").
  ///
  /// Ohne das bleibt ein Timer stehen und der Test scheitert an
  /// "A Timer is still pending".
  Future<void> aufraeumen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Lässt die echte Ereignisschleife laufen (im Widget-Test passiert
  /// das nur in runAsync).
  Future<void> lassNetzLaufen(
    WidgetTester tester, {
    bool Function()? fertig,
  }) async {
    var treffer = false;
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
      if (fertig != null && fertig()) {
        treffer = true;
        break;
      }
    }
    if (treffer) {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }
    }
  }

  /// Scrollt zu einem Text (der Screen ist lang).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    await tester.scrollUntilVisible(
      ziel,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Lässt die echte Ereignisschleife laufen (im Widget-Test passiert
  /// das nur in runAsync) - in kleinen Schritten, damit der stille
  /// Login (nach fünf Sekunden) nicht dazwischenfunkt.
  Future<void> netzSchritte(WidgetTester tester, {int schritte = 20}) async {
    for (var i = 0; i < schritte; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
  }

  group('Der Cooldown nach "Erneut senden"', () {
    testWidgets('der Knopf zaehlt herunter und wird wieder frei', (
      tester,
    ) async {
      final container = await zeigeScreen(tester);

      // DER TAP IM TEST-KREIS: Der PKCE-Speicher liegt im RAM (keine
      // Plattform-Kommunikation) - damit läuft der ganze Versand im
      // Test-Kreis und seine Timer (die Erfolgs-Animation, der Cooldown)
      // sind die des Test-Kreises: der Test kann sie vorspulen.
      await tester.tap(find.text(L10n.tWithoutContext('email.resend')));
      await tester.pump();
      await lassNetzLaufen(
        tester,
        fertig: () => server.pfade.any((p) => p.contains('/auth/v1/resend')),
      );

      expect(tester.takeException(), isNull);
      // Die Erfolgs-Animation steht da ("E-Mail gesendet").
      expect(find.text(L10n.tWithoutContext('email.sent')), findsOneWidget);

      // ZWEI SEKUNDEN SPÄTER: Der Knopf zählt die Wartezeit herunter.
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.textContaining('Erneut senden in'),
        findsOneWidget,
        reason:
            'Nach dem Versand muss der Knopf die Wartezeit zeigen - sonst '
            'klickt der Nutzer weiter und der Server blockt ihn.',
      );

      // UND NACH DER WARTEZEIT: Der Knopf ist wieder frei.
      await tester.pump(const Duration(seconds: 61));
      expect(
        find.text(L10n.tWithoutContext('email.resend')),
        findsOneWidget,
        reason: 'Nach der Wartezeit muss der Knopf wieder "senden" anbieten.',
      );

      await aufraeumen(tester, container);
    });

    testWidgets('schlaegt der Versand fehl, steht der Fehler da', (
      tester,
    ) async {
      // DER SERVER SAGT NEIN: Die Supabase-Drosselung antwortet mit
      // "rate_limit" - das ist der Fall, den der Bildschirm gesondert
      // nennen soll.
      server.fehlerAntworten['/auth/v1/resend'] = (
        status: 429,
        body: '{"msg":"rate_limit exceeded"}',
      );
      final container = await zeigeScreen(tester);

      await tester.runAsync(() async {
        await tester.tap(find.text(L10n.tWithoutContext('email.resend')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await lassNetzLaufen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('email.rateLimited')),
        findsOneWidget,
        reason:
            'Bei zu vielen Anfragen muss der Nutzer das erfahren - er soll '
            'nicht denken, die Mail sei unterwegs.',
      );

      await aufraeumen(tester, container);
    });
  });

  group('Das Ende des Abbruchs', () {
    // ANMERKUNG: Der ERFOLGREICHE Abbruch (Konto gelöscht, Abmeldung,
    // Sprung zum Login) lässt sich im Widget-Test nicht bis zum Ende
    // durchspielen: die Abmeldung räumt Hunderte Dateien und Dienste
    // ab (Hive, Schlüssel, Chatverlauf) - das dauert im Test länger als
    // der Test laufen darf. Der Weg bis zum Aufruf der Server-Funktion
    // ist in test/auth/email_verification_cancel_test.dart getestet, der
    // Fehlerweg hier.

    testWidgets('schlaegt das Loeschen fehl, steht der Fehler da', (
      tester,
    ) async {
      // DER SERVER SAGT NEIN: Das Konto existiert nicht (oder der
      // Nachweis war falsch) - das muss der Nutzer erfahren.
      server.funktionsAntworten['cancel-registration'] = <String, dynamic>{
        'deleted': false,
        'error': 'Nachweis fehlgeschlagen',
      };
      final container = await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('email.cancel'));
      await tester.tap(find.text(L10n.tWithoutContext('email.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('email.cancelConfirm'),
        ),
      );
      await tester.pump();
      await netzSchritte(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Nachweis fehlgeschlagen'),
        findsOneWidget,
        reason:
            'Der Fehler muss im Klartext dastehen - der Nutzer soll '
            'wissen, dass sein Konto noch da ist.',
      );
      expect(
        find.text('Anmeldung'),
        findsNothing,
        reason:
            'Das Konto ist noch nicht geloescht - der Nutzer darf nicht '
            'als abgemeldet dastehen.',
      );

      await aufraeumen(tester, container);
    });
  });
}
