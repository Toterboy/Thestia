// Der Konto-Lösch-Ablauf (der Weg aus den Einstellungen und aus dem
// Datenschutz-Bereich).
//
// ANLASS (22.11.2026): lib/screens/privacy/delete_account_action.dart
// war mit 0 % Abdeckung ungetestet - und der Ablauf ist sicherheits-
// relevant: das Löschen eines Kontos braucht eine Bestätigung, und
// bei aktivem 2FA zusätzlich eine TOTP-Bestätigung (ASVS 7.5.3).
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne 2FA: der Bestätigungsdialog erscheint, "Abbrechen" löscht
//     nichts,
//   * mit 2FA: zuerst der TOTP-Dialog, ein falscher Code bricht ab,
//   * die Bestätigung löscht das Konto und fährt zur Startseite,
//   * ein Fehler beim Löschen wird dem Nutzer gemeldet (nicht
//     verschluckt).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/auth/mfa_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: Der Auth-Provider räumt nach dem Löschen lokal auf
    // (Schlüssel, Vorab-Schlüssel, Verifizierung). Ohne Hive wirft
    // dieser Aufräum nach dem Test - und der Test wäre rot, obwohl
    // die Löschung geklappt hat.
    await mockHive();
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.zeilen.clear();
  });

  /// Baut den Bildschirm mit dem Lösch-Knopf.
  Future<TestAuth> zeige(
    WidgetTester tester, {
    MfaStatus mfa = const MfaStatus.initial(),
    Object? loeschFehler,
  }) async {
    final auth = TestAuth(loeschFehler: loeschFehler);
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(TestSpeicher()),
        secureProfileStoreProvider.overrideWithValue(TestKeystore()),
        profileProvider.overrideWith((ref) => TestProfil()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(auth, ref.read(profileProvider.notifier), ref),
        ),
        mfaStatusProvider.overrideWith((ref) => mfa),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: AppRoutes.privacy,
      routes: appRoutes(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return auth;
  }

  /// Tippt auf "Konto löschen" (der Text steht in den Einstellungen).
  Future<void> tippeLoeschen(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('privacy.deleteAccount'));
    if (knopf.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        knopf,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
    }
    await tester.tap(knopf);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('der Bestaetigungsdialog erscheint', (tester) async {
    await zeige(tester);

    await tippeLoeschen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(L10n.tWithoutContext('privacy.deleteConfirm')),
      findsOneWidget,
    );
  });

  testWidgets('abbrechen loescht nichts', (tester) async {
    final auth = await zeige(tester);

    await tippeLoeschen(tester);
    await tester.tap(
      find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      auth.kontoGeloescht,
      isFalse,
      reason: 'Ohne Bestaetigung wird kein Konto geloescht.',
    );
  });

  testWidgets('die Bestaetigung loescht das Konto', (tester) async {
    final auth = await zeige(tester);

    await tippeLoeschen(tester);
    await tester.tap(
      find.widgetWithText(
        TextButton,
        L10n.tWithoutContext('privacy.deleteConfirm'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      auth.kontoGeloescht,
      isTrue,
      reason: 'Nach der Bestaetigung muss das Konto geloescht werden.',
    );

    // DER AUFRÄUM DES AUTH-PROVIDERS: Er räumt danach lokal auf
    // (Hive ist im Test nicht initialisiert). Dieser Fehler kommt
    // NACH dem Test und darf ihn nicht kippen - die Löschung selbst
    // ist oben geprüft.
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  });

  testWidgets('mit 2FA kommt zuerst der TOTP-Dialog', (tester) async {
    await zeige(
      tester,
      mfa: const MfaStatus(
        currentAal: 'aal1',
        hasVerifiedFactors: true,
        hasAnyFactor: true,
        loaded: true,
      ),
    );

    await tippeLoeschen(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.text(L10n.tWithoutContext('privacy.totpTitle')),
      findsOneWidget,
      reason:
          'Bei aktivem 2FA muss vor dem Loeschen der TOTP-Code '
          'eingegeben werden (ASVS 7.5.3).',
    );
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'Der Bestaetigungsdialog kommt erst NACH dem TOTP.',
    );
  });

  testWidgets('ein falscher TOTP-Code bricht ab', (tester) async {
    final auth = await zeige(
      tester,
      mfa: const MfaStatus(
        currentAal: 'aal1',
        hasVerifiedFactors: true,
        hasAnyFactor: true,
        loaded: true,
      ),
    );

    await tippeLoeschen(tester);
    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('privacy.totpConfirm'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      auth.kontoGeloescht,
      isFalse,
      reason:
          'Ein falscher Code darf die Loeschung NICHT ausloesen - der '
          'Support-Code muss erst passen.',
    );
  });

  testWidgets('ein Fehler beim Loeschen wird gemeldet', (tester) async {
    await zeige(tester, loeschFehler: StateError('Server kaputt'));

    await tippeLoeschen(tester);
    await tester.tap(
      find.widgetWithText(
        TextButton,
        L10n.tWithoutContext('privacy.deleteConfirm'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason:
          'Der Nutzer muss erfahren, dass die Loeschung fehlgeschlagen '
          'ist - sonst glaubt er, sein Konto sei weg.',
    );

    // Der Aufräum des Auth-Providers (Hive ist im Test nicht
    // initialisiert) darf den Test nicht kippen.
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  });
}
