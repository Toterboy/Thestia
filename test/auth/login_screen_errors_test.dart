// Die Fehlertexte der Anmeldung - ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/login_screen.dart 190 offene Zeilen. Der groesste
// Block davon ist die Uebersetzung der Server-Fehler: der Nutzer soll
// "Email oder Passwort ist falsch" lesen - nicht "Invalid login
// credentials" und schon gar nicht einen SQL-Fehler.
//
// WAS HIER GEPRUEFT WIRD:
//   * falsche Zugangsdaten -> "Email oder Passwort ist falsch",
//   * unbestaetigte E-Mail -> der Hinweis auf die Bestaetigung,
//   * zu viele Versuche -> der Hinweis auf das Warten,
//   * ein schwaches Passwort -> der Hinweis auf die Passwort-Regeln,
//   * ein abgelehntes CAPTCHA -> der Hinweis darauf.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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
  Future<void> write(String value) async {
    // Der Test speichert kein Profil im Keystore.
  }

  @override
  Future<void> delete() async {
    // Der Test loescht kein Profil im Keystore.
  }
}

void main() {
  /// Der Ersatz-Server (der die Fehlermeldung liefert).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockZeitzone();
    // DER SPEICHER: der Verschluesselungs-Dienst des Auth-Clients
    // oeffnet beim Start seine Box.
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
  });

  setUp(() {
    server.fehlerAntworten.clear();
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Scrollt bis zum Knopf (die Seite ist eine Liste).
  Future<void> scrolleZumKnopf(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      if (find.text(L10n.tWithoutContext('auth.login')).evaluate().isNotEmpty) {
        return;
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Meldet sich an - mit der eingestellten Server-Fehlermeldung.
  Future<void> meldeAn(WidgetTester tester, String serverMeldung) async {
    server.fehlerAntworten['/auth/v1/token'] = (
      status: 400,
      body: '{"error":"invalid_grant","error_description":"$serverMeldung"}',
    );

    await zeigeScreen(tester);

    final felder = find.byType(TextFormField);
    await tester.enterText(felder.at(0), 'lena@example.com');
    await tester.enterText(felder.at(1), 'SicheresPasswort7');
    await tester.pump();

    await scrolleZumKnopf(tester);
    final knopf = find.text(L10n.tWithoutContext('auth.login'));
    await tester.ensureVisible(knopf);
    await tester.tap(knopf);
    await tester.pump();
    // Die Anfrage geht an den Server (echte Schleife).
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Die Fehlertexte der Anmeldung', () {
    testWidgets('falsche Zugangsdaten', (tester) async {
      await meldeAn(tester, 'Invalid login credentials');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('error.invalidCredentials')),
        findsOneWidget,
        reason:
            'Der Nutzer soll "Email oder Passwort ist falsch" lesen - nicht '
            'den Servertext.',
      );
    });

    testWidgets('unbestaetigte E-Mail', (tester) async {
      await meldeAn(tester, 'Email not confirmed');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('error.notConfirmed')),
        findsOneWidget,
      );
    });

    // DIE UEBERSETZUNGEN: Der Server spricht Englisch, die App zeigt
    // deutsche Saetze. Jede Uebersetzung wird einzeln geprueft - sonst
    // sieht der Nutzer bei einem seltenen Fehler den rohen Servertext.
    group('die Servertexte werden uebersetzt', () {
      Future<void> pruefe(
        WidgetTester tester,
        String serverText,
        String l10nKey,
      ) async {
        await meldeAn(tester, serverText);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext(l10nKey)),
          findsOneWidget,
          reason:
              'Der Servertext "$serverText" muss uebersetzt werden - der '
              'Nutzer soll nicht "invalid login credentials" lesen.',
        );
      }

      testWidgets('die Adresse ist schon vergeben', (tester) async {
        await pruefe(
          tester,
          'User already registered',
          'error.alreadyRegistered',
        );
      });

      testWidgets('es gab zu viele Versuche', (tester) async {
        await pruefe(tester, 'Too many requests', 'error.rateLimited');
      });

      testWidgets('das Passwort ist zu schwach', (tester) async {
        await pruefe(tester, 'Weak password', 'error.weakPassword');
      });

      testWidgets('die Mindestlaenge des Passworts kommt durch', (
        tester,
      ) async {
        // DER GRUND: Die Mindestlaenge steht im Server-Dashboard (nicht
        // in der App) - deshalb muss der Servertext durchgereicht werden.
        await meldeAn(tester, 'Password should be at least 12 characters');

        expect(tester.takeException(), isNull);
        expect(
          find.text('Password should be at least 12 characters'),
          findsOneWidget,
          reason:
              'Die Mindestlaenge steht im Dashboard - der Text muss '
              'durchgereicht werden, sonst weiss der Nutzer nicht, '
              'wie lang sein Passwort sein muss.',
        );
      });

      testWidgets('die Sicherheitsabfrage wurde abgelehnt', (tester) async {
        await pruefe(
          tester,
          'captcha verification failed',
          'error.captchaRejected',
        );
      });

      testWidgets('der Server hat einen Datenbankfehler', (tester) async {
        await pruefe(
          tester,
          'Database error saving new user',
          'error.signupFailed',
        );
      });

      testWidgets('ein unbekannter Fehler wird allgemein gemeldet', (
        tester,
      ) async {
        await meldeAn(tester, 'irgendein seltsamer Fehler');

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(L10n.tWithoutContext('error.loginFailed')),
          findsOneWidget,
          reason:
              'Ein unbekannter Fehler darf nicht als Servertext kommen - '
              'der Nutzer kann damit nichts anfangen.',
        );
      });
    });

    testWidgets('zu viele Versuche', (tester) async {
      await meldeAn(tester, 'Too many requests');

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Zu viele'),
        findsOneWidget,
        reason: 'Der Nutzer muss wissen, dass er warten muss.',
      );
    });

    testWidgets('ein schwaches Passwort', (tester) async {
      await meldeAn(tester, 'Weak password');

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Passwort'),
        findsWidgets,
        reason:
            'Der Hinweis auf die Passwort-Regeln muss den Passwort-Server '
            'erklaeren.',
      );
    });
  });
}
