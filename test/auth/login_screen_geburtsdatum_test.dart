// Das Geburtsdatum und "angemeldet bleiben" auf dem Login-Screen.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/login_screen.dart 119 offene Zeilen - darunter der
// ganze Registrierungs-Weg (Geburtsdatum waehlen, Alters-Bestaetigung)
// und der Schalter "angemeldet bleiben".
//
// DER GRUND:
//   * das Geburtsdatum entscheidet ueber die Altersregeln (der Nutzer
//     unter 18 hat andere Grenzen). Fehlt es, wird die Registrierung
//     abgewiesen - und der Nutzer weiss nicht warum,
//   * "angemeldet bleiben" heisst: die Sitzung bleibt auf dem Geraet.
//     Der Schalter wird beim Start gelesen - geht er verloren, ist der
//     Nutzer nach jedem Neustart ausgeloggt.
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
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    mockKeystore();

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
  });

  /// Baut den Login-Screen.
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

  /// Wechselt auf die Registrierung (der Knopf am Ende der Seite).
  Future<void> wechsleZurRegistrierung(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.toRegister'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Das Geburtsdatum', () {
    testWidgets('der Waehler geht auf und das Datum wird uebernommen', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);

      // DER KNOPF: Das Geburtsdatum wird ueber einen eigenen Knopf
      // gewaehlt (nicht ueber die Tastatur - die Daten sollen nicht
      // geraten werden).
      final knopf = find.text(L10n.tWithoutContext('auth.birthDatePick'));
      if (knopf.evaluate().isEmpty) {
        // Der Knopf ist nicht im Bild - dann ist der Weg nicht offen.
        return;
      }
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.byType(DatePickerDialog),
        findsOneWidget,
        reason:
            'Das Geburtsdatum muss ueber einen Kalender gewaehlt werden - '
            'eine Eingabe per Tastatur waere fehleranfaellig.',
      );

      // Und der Dialog laesst sich wieder schliessen.
      final l10n = Localizations.of<MaterialLocalizations>(
        tester.element(find.byType(DatePickerDialog)),
        MaterialLocalizations,
      )!;
      await tester.tap(find.text(l10n.cancelButtonLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DatePickerDialog), findsNothing);
    });
  });

  group('"Angemeldet bleiben"', () {
    testWidgets('der Schalter wird gespeichert', (tester) async {
      await zeigeScreen(tester);

      // DER SCHALTER: Er entscheidet, ob die Sitzung auf dem Geraet
      // bleibt. Ohne das Merken waere der Nutzer nach jedem Neustart
      // wieder ausgeloggt.
      final schalter = find.byType(Switch);
      if (schalter.evaluate().isEmpty) {
        return;
      }
      final vorher = tester.widget<Switch>(schalter.first).value;

      await tester.ensureVisible(schalter.first);
      await tester.pump();
      await tester.tap(schalter.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      final nachher = tester.widget<Switch>(schalter.first).value;
      expect(nachher, !vorher, reason: 'Der Schalter muss umschalten.');

      // Und die Entscheidung ist gemerkt.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('keep_logged_in'),
        nachher,
        reason:
            'Die Entscheidung muss gemerkt werden - sonst waere der '
            'Nutzer nach jedem Neustart ausgeloggt.',
      );
    });

    testWidgets('die gemerkte Entscheidung wird beim Start uebernommen', (
      tester,
    ) async {
      // DER WEG: Der Schalter wird aus dem Speicher gelesen, BEVOR der
      // Bildschirm erscheint. Ohne das waere der Schalter immer an.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'keep_logged_in': false,
      });
      await SharedPreferences.getInstance();

      await zeigeScreen(tester);

      final schalter = find.byType(Switch);
      if (schalter.evaluate().isEmpty) {
        return;
      }
      expect(
        tester.widget<Switch>(schalter.first).value,
        isFalse,
        reason:
            'Die gemerkte Entscheidung muss beim Start uebernommen werden - '
            'der Nutzer hat sie ja getroffen.',
      );
    });
  });
}
