// Die Anmeldung mit Sicherheitscheck.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/screens/auth/login_screen.dart 98 offene Zeilen - darunter der
// ganze CAPTCHA-Weg (das Fenster, der Abbruch, das Token).
//
// DER WEG IN DER APP: Klick auf "Anmelden" -> Validierung -> der
// Sicherheitscheck (nur wenn ein Sitekey hinterlegt ist) -> erst dann
// geht die Anmeldung an den Server. Bricht der Nutzer im Fenster ab,
// geht NICHTS an den Server - das ist der Punkt dieses Tests.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';
import '../support/webview_fake.dart';

/// Der Sitekey, den der Test setzt.
const String _sitekey = '0x4AAAAAAFDhMgIL_nrpUokM';

void main() {
  late FakeSupabaseServer server;
  late FakeWebViewPlattform webview;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: der Verschlüsselungs-Dienst öffnet beim Anmelden seine Boxen.
    await mockHive();

    // DER SERVER EINMAL: Der Supabase-Client ist ein Singleton - ein
    // zweites "initialize" im selben Testlauf zeigt weiter auf den
    // ersten Server. Deshalb gibt es hier nur einen, und die Tests
    // räumen seine Liste in setUp leer.
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
  });

  setUp(() async {
    server.pfade.clear();
    server.funktionsAufrufe.clear();
    webview = FakeWebViewPlattform();
    // DAS CAPTCHA EIN: Ohne Sitekey würde der Weg nicht betreten.
    dotenv.loadFromString(envString: 'CAPTCHA_SITEKEY=$_sitekey');
  });

  tearDown(() {
    dotenv.clean();
  });

  /// Baut den Anmelde-Screen (mit Router - der Screen navigiert).
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
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
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
        child: ProviderScope(
          overrides: [
            // DER SPEICHER: Die App verlangt im Test einen Ersatz
            // (sonst wirft der Anmelde-Versuch).
            localStorageProvider.overrideWithValue(TestSpeicher()),
            secureProfileStoreProvider.overrideWithValue(TestKeystore()),
          ],
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Füllt E-Mail und Passwort und schickt das Formular ab.
  Future<void> anmelden(WidgetTester tester) async {
    final felder = find.byType(TextFormField);
    await tester.enterText(felder.at(0), 'ich@example.de');
    await tester.enterText(felder.at(1), 'Passwort123!');
    await tester.pump();
    await tester.tap(find.text(L10n.tWithoutContext('auth.login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('die Anmeldung fragt zuerst nach dem Sicherheitscheck', (
    tester,
  ) async {
    await zeigeScreen(tester);

    await anmelden(tester);

    expect(
      find.text(L10n.tWithoutContext('auth.captcha')),
      findsOneWidget,
      reason:
          'Vor der Anmeldung kommt der Sicherheitscheck - der Server '
          'verlangt das Token.',
    );
    expect(
      server.pfade.where((p) => p.contains('/auth/v1/token')),
      isEmpty,
      reason:
          'Ohne Token geht keine Anmeldung an den Server - das ist der '
          'Sinn des Bot-Schutzes.',
    );
  });

  testWidgets('mit dem Token geht die Anmeldung raus', (tester) async {
    await zeigeScreen(tester);

    await anmelden(tester);
    // DIE SEITE MELDET DAS TOKEN.
    webview.sendeAusDerSeite('1.lAbV5RcI1e_abcdef.0123456789');
    await tester.pump();
    // DAS NETZ: Die Anmeldung läuft in der echten Ereignisschleife -
    // im Widget-Test passiert das nur in runAsync.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      server.pfade.any((p) => p.contains('/auth/v1/token')),
      isTrue,
      reason: 'Nach dem Token geht die Anmeldung an den Server - vorher nicht.',
    );
  });

  testWidgets('bricht der Nutzer ab, geht keine Anmeldung raus', (
    tester,
  ) async {
    await zeigeScreen(tester);

    await anmelden(tester);
    await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.text(L10n.tWithoutContext('auth.captchaLogin')),
      findsOneWidget,
      reason:
          'Der Nutzer muss wissen, dass die Anmeldung nicht stattgefunden '
          'hat - sonst wartet er auf eine Mail, die nie kommt.',
    );
    expect(
      server.pfade.where((p) => p.contains('/auth/v1/token')),
      isEmpty,
      reason: 'Ohne Token keine Anmeldung.',
    );
  });
}
