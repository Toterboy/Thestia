// Die Registrierung: Formular, Alters-Bestaetigung und Sicherheitscheck.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/login_screen.dart 85 offene Zeilen - darunter der
// ganze Registrierungs-Weg (die Pflichtfelder, das Geburtsdatum, die
// Alters-Bestaetigung und der Sicherheitscheck VOR der Registrierung).
//
// DER WEG: Fuer den Sicherheitscheck braucht es den WebView-Ersatz
// (test/support/webview_fake.dart) und einen Sitekey in der Umgebung
// (sonst ist der Bot-Schutz abgeschaltet und der Weg wird nie
// betreten).
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Alters-Bestaetigung geht die Registrierung nicht raus (und
//     der Nutzer weiss warum),
//   * ohne Geburtsdatum auch nicht,
//   * die Registrierung fragt ZUERST nach dem Sicherheitscheck,
//   * bricht der Nutzer ab, wird das gemeldet und es wird nichts
//     registriert,
//   * mit dem Token geht die Registrierung an den Server.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/webview_fake.dart';

/// Der Sitekey, den der Test setzt (ein oeffentlicher Schluessel).
const String _sitekey = '0x4AAAAAAFDhMgIL_nrpUokM';

/// Der Speicher im RAM.
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
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  late FakeSupabaseServer server;
  late FakeWebViewPlattform webview;
  late EncryptionService encryption;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: der Chat-Dienst liest beim Start seine Boxen. Die
    // Adapter des Verschluesselungs-Dienstes muessen registriert
    // sein - sonst kann er sie nicht oeffnen und die Registrierung
    // bleibt haengen.
    await mockHive();
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());

    // DER VERSCHLUESSELUNGS-DIENST: Die Registrierung wartet auf
    // seinen Schluessel (der aus dem Keystore abgeleitet wird). Der
    // Dienst startet seine Initialisierung selbst - im Test muss
    // man darauf warten, sonst wartet die Registrierung ewig.
    encryption = EncryptionService();
    await encryption.initialize();

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

  setUp(() {
    server.pfade.clear();
    server.fehlerAntworten.clear();
    webview = FakeWebViewPlattform();
    // DAS CAPTCHA EIN: Ohne Sitekey ist der Bot-Schutz abgeschaltet.
    dotenv.loadFromString(envString: 'CAPTCHA_SITEKEY=$_sitekey');
  });

  tearDown(() {
    dotenv.clean();
  });

  /// Baut den Login-Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // DER ROUTER: Nach der Registrierung geht der Screen zur
    // E-Mail-Bestaetigung - ohne Router wuerfe er.
    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.emailVerification,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('E-Mail bestaetigen'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          encryptionServiceProvider.overrideWithValue(encryption),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Wechselt auf die Registrierung.
  Future<void> wechsleZurRegistrierung(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.toRegister'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Fuellt das Formular (ohne Alters-Bestaetigung).
  Future<void> fuelleFormular(WidgetTester tester) async {
    final felder = find.byType(TextFormField);
    await tester.enterText(felder.at(0), 'Mira');
    await tester.pump();
    await tester.enterText(felder.at(1), 'mira@example.de');
    await tester.pump();
    await tester.enterText(felder.at(2), 'Passwort123!');
    await tester.pump();
  }

  /// Waehlt das Geburtsdatum ueber den Kalender.
  Future<void> waehleGeburtsdatum(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.birthDatePick'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final l10n = Localizations.of<MaterialLocalizations>(
      tester.element(find.byType(DatePickerDialog)),
      MaterialLocalizations,
    )!;
    await tester.tap(find.text(l10n.okButtonLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt auf "Registrieren".
  Future<void> tippeRegistrieren(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.register'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt die Alters-Bestaetigung an.
  Future<void> bestaetigeAlter(WidgetTester tester) async {
    final haken = find.byType(CheckboxListTile);
    await tester.ensureVisible(haken.first);
    await tester.pump();
    await tester.tap(haken.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Die Pflichtangaben', () {
    testWidgets('ohne Alters-Bestaetigung geht es nicht weiter', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFormular(tester);
      await waehleGeburtsdatum(tester);

      await tippeRegistrieren(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('auth.ageConfirmRequired')),
        findsWidgets,
        reason:
            'Das Alter muss bestaetigt werden - der Nutzer muss wissen, '
            'dass es der Grund war (sonst denkt er, die App haengt).',
      );
      expect(
        server.pfade.where((p) => p.contains('/signup')),
        isEmpty,
        reason: 'Ohne Bestaetigung wird nichts registriert.',
      );
    });
  });

  group('Der Sicherheitscheck', () {
    testWidgets('die Registrierung fragt zuerst danach', (tester) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFormular(tester);
      await waehleGeburtsdatum(tester);
      await bestaetigeAlter(tester);

      await tippeRegistrieren(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('auth.captcha')),
        findsOneWidget,
        reason:
            'Der Sicherheitscheck kommt VOR der Registrierung - sonst '
            'haette der Server schon einen Bot angelegt.',
      );
      expect(
        server.pfade.where((p) => p.contains('/signup')),
        isEmpty,
        reason: 'Ohne Token geht keine Registrierung an den Server.',
      );
    });

    testWidgets('bricht der Nutzer ab, wird das gemeldet', (tester) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFormular(tester);
      await waehleGeburtsdatum(tester);
      await bestaetigeAlter(tester);

      await tippeRegistrieren(tester);
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('auth.captchaRegister')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Registrierung nicht '
            'stattgefunden hat - sonst wartet er auf eine Mail, die nie '
            'kommt.',
      );
      expect(server.pfade.where((p) => p.contains('/signup')), isEmpty);
    });

    testWidgets('mit dem Token geht die Registrierung an den Server', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFormular(tester);
      await waehleGeburtsdatum(tester);
      await bestaetigeAlter(tester);

      await tippeRegistrieren(tester);
      // DIE SEITE MELDET DAS TOKEN (so, wie es die echte Turnstile-Seite
      // ueber den JavaScript-Bridge tut).
      webview.sendeAusDerSeite('1.lAbV5RcI1e_abcdef.0123456789');
      await tester.pump();
      // DIE REGISTRIERUNG WARTET: Der Auth-Dienst braucht 600 ms
      // (Demo-Modus) - die Test-Uhr muss das weiterdrehen.
      await tester.pump(const Duration(milliseconds: 800));
      // DER VERSCHLUESSELUNGS-DIENST: Er leitet beim Start seinen
      // Schluessel ab (PBKDF2, 600k Runden) - das dauert echte Zeit.
      // MEHRERE RUNDEN: Erst kommt die Sperrpruefung (ein Aufruf), dann
      // die Registrierung (ein weiterer) - dazwischen muss die Test-Uhr
      // jeweils weiterlaufen.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.where((p) => p.contains('/auth/v1/signup')),
        isNotEmpty,
        reason:
            'Mit dem Token muss die Registrierung beim Server ankommen - '
            'ohne Token haette der Server schon einen Bot angelegt.',
      );
      expect(
        find.text(L10n.tWithoutContext('auth.captchaRegister')),
        findsNothing,
        reason:
            'Der Nutzer hat den Sicherheitscheck geloest - er darf keine '
            'Abbruch-Meldung sehen.',
      );
    });
  });
}
