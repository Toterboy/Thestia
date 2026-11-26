// Die Registrierung im Login-Screen: die Pflichten vor dem Absenden.
//
// ANLASS (19.11.2026): `lib/screens/auth/login_screen.dart` war nur zu
// 62 % abgedeckt. Genau die beiden Wächter waren ungetestet:
// das Geburtsdatum (Pflicht) und die Alters-Wahrheit (das Alter muss
// ausdrücklich bestätigt werden). Beide sind Jugendschutz - ohne sie
// käme eine Person unter 16 in die App.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Geburtsdatum geht die Registrierung nicht (mit Hinweis),
//   * ohne Alters-Bestätigung geht sie auch nicht (mit Hinweis),
//   * die Pflichtfelder werden geprüft (Name, E-Mail, Passwort).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

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

void main() {
  /// Der Ersatz-Server: an ihm sieht der Test, OB eine Registrierung
  /// überhaupt hinausgegangen ist.
  late FakeSupabaseServer server;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    // DER KEYSTORE: der sichere Speicher der Anmeldung - ohne den
    // Ersatz ruft der Test auf dem CI-Runner das echte Plugin.
    mockKeystore();
    // HIVE: der Verschlüsselungs-Dienst öffnet beim Registrieren seine
    // Boxen - ohne initialisierten Hive scheitert der Aufruf.
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
    TestWidgetsFlutterBinding.ensureInitialized();
    server.pfade.clear();
  });

  /// Ist eine Registrierung an den Server gegangen?
  bool gingRaus() => server.pfade.any(
    (p) => p.contains('/auth/v1/signup') || p.contains('/auth/v1/token'),
  );

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Ohne den Ersatz würde die Registrierung am Schreiben in
          // den lokalen Speicher scheitern (der Provider wirft
          // absichtlich, wenn er nicht gesetzt ist).
          localStorageProvider.overrideWithValue(_Speicher()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Wechselt in den Registrierungs-Modus.
  Future<void> wechsleZurRegistrierung(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.toRegister'));
    await tester.scrollUntilVisible(
      knopf,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Scrollt, bis [anzahl] Eingabefelder gebaut sind (die Liste baut
  /// nur die sichtbaren Einträge).
  Future<void> scrolleZuFeldern(WidgetTester tester, int anzahl) async {
    for (var i = 0; i < 14; i++) {
      if (tester.widgetList<TextFormField>(find.byType(TextFormField)).length >=
          anzahl) {
        return;
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Füllt die Felder der Registrierung (Name, E-Mail, Passwort).
  Future<void> fuelleFelder(WidgetTester tester) async {
    await scrolleZuFeldern(tester, 3);
    await tester.enterText(find.byType(TextFormField).at(0), 'Lena');
    await tester.enterText(find.byType(TextFormField).at(1), 'lena@example.de');
    // Das Passwort muss die Server-Regel erfüllen (8 Zeichen, Buchstabe,
    // Zahl UND Sonderzeichen) - sonst stoppt die Formularprüfung vorher.
    await tester.enterText(find.byType(TextFormField).at(2), 'Passwort123!');
    await tester.pump();
  }

  /// Tippt den Registrieren-Knopf.
  Future<void> tippeRegistrieren(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('auth.register'));
    await tester.scrollUntilVisible(
      knopf,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Die Registrierung', () {
    testWidgets('ohne Geburtsdatum geht sie nicht', (tester) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFelder(tester);
      await tippeRegistrieren(tester);

      expect(
        find.text(L10n.tWithoutContext('validation.birthEmpty')),
        findsWidgets,
        reason:
            'Ohne Geburtsdatum kann das Alter nicht geprueft werden - die '
            'Registrierung muss hier stoppen (Jugendschutz).',
      );
      // DIE EIGENTLICHE ZUSICHERUNG: Es darf gar nichts beim Server
      // ankommen. Ein Hinweis reicht nicht - es muss auch nichts
      // registriert werden.
      expect(
        gingRaus(),
        isFalse,
        reason:
            'Ohne Geburtsdatum darf sich niemand registrieren - sonst '
            'kaeme eine Person unter 16 ohne Alterspruefung in die App.',
      );
    });

    testWidgets('ohne Alters-Bestaetigung geht sie auch nicht', (tester) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);
      await fuelleFelder(tester);

      // Das Geburtsdatum wählen (der Vorschlag ist 18 Jahre zurück).
      // Das Geburtsdatum-Feld ist das VIERTE TextFormField (Name,
      // E-Mail, Passwort, Geburtsdatum).
      // Das Geburtsdatum-Feld ist ein InkWell mit dem Text
      // "Geburtsdatum wählen" (es ist kein Eingabefeld).
      final datum = find.text(L10n.tWithoutContext('auth.birthDatePick'));
      await tester.scrollUntilVisible(
        datum,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(datum);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Der Vorschlag bestätigen (18 Jahre alt - genau an der Grenze).
      final ok = find.text('OK');
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tippeRegistrieren(tester);

      expect(
        find.text(L10n.tWithoutContext('auth.ageConfirmRequired')),
        findsWidgets,
        reason:
            'Das Alter muss ausdruecklich bestaetigt werden - der Nutzer '
            'muss bestaetigen, dass er die Wahrheit sagt.',
      );
      // DIE EIGENTLICHE ZUSICHERUNG: Ohne die Bestätigung darf sich
      // niemand registrieren.
      expect(
        gingRaus(),
        isFalse,
        reason:
            'Ohne Alters-Bestaetigung darf sich niemand registrieren - '
            'das Alter muss bestaetigt werden (Jugendschutz).',
      );
    });

    testWidgets('die Pflichtfelder werden geprueft', (tester) async {
      await zeigeScreen(tester);
      await wechsleZurRegistrierung(tester);

      // Ohne Eingaben: Die Formularprüfung meldet die leeren Felder.
      await tippeRegistrieren(tester);

      expect(tester.takeException(), isNull);
      // Die Meldungen der Pflichtfelder (aus den Validatoren).
      for (final schluessel in const [
        'validation.nameEmpty',
        'validation.emailEmpty',
        'validation.passwordEmpty',
      ]) {
        expect(
          find.text(L10n.tWithoutContext(schluessel)),
          findsWidgets,
          reason: '"$schluessel" muss gemeldet werden.',
        );
      }
    });
  });
}
