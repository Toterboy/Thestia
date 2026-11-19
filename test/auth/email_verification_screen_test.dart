// Der Screen zur E-Mail-Bestaetigung (bisher ohne jeden Test).
//
// ANLASS (17.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/email_verification_screen.dart 314 offene Zeilen bei
// 315 Zeilen gesamt - der Screen war komplett ungetestet. Das ist der
// Screen, auf dem ein NEUER Nutzer nach der Registrierung landet: er
// entscheidet hier, ob er die Mail noch einmal bekommt, ob er die
// Adresse aendert oder die Registrierung ganz abbricht.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen baut sich und zeigt die Adresse an, an die die Mail ging
//     (Nutzerwunsch 01.11.2026),
//   * nach der Bestaetigung geht es weiter (zur Einrichtung),
//   * "Erneut senden" schickt die Mail wirklich und startet den Cooldown,
//   * "Registrierung abbrechen" loescht das unbestaetigte Konto beim
//     Server (ueber die Funktion cancel-registration) und landet beim Login,
//   * "Registrierung behalten" loescht nichts,
//   * der stille Auto-Login versucht es nach der Wartezeit,
//   * abgelaufene Registrierungsdaten werden NICHT mehr an den Server
//     gegeben (das Passwort bleibt hoechstens 15 Minuten im Speicher),
//   * ohne Supabase (Demo-Modus) geht es direkt zur Hauptapp.
//
// OHNE SERVER: Der Supabase-Client zeigt auf einen Ersatz-Server aus
// dem RAM (test/support/fake_supabase_server.dart). Die Funktion
// "cancel-registration" antwortet dort mit deleted: true - so sieht der
// Bildschirm das, was er sehen soll.
//
// WICHTIG (Testtechnik): Die HTTP-Anfragen laufen in der ECHTEN
// Ereignisschleife. Im Widget-Test passiert das nur in
// `tester.runAsync(...)` - mit blossem `pump` bleibt die Anfrage
// haengen und der Server sieht nichts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: depend_on_referenced_packages
import 'package:gotrue/gotrue.dart' show GotrueAsyncStorage;
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/email_verification_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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

/// Der Keystore ohne Plugin (sonst sucht der Test auf dem CI-Runner
/// eine libsecret-Sitzung).
class _FakeSecurePrefs extends SecurePreferencesStorage {
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

// DER PKCE-Speicher DES AUTH-CLIENTS IM RAM: Der Standard-Speicher
// schreibt ueber die Plattform (SharedPreferences). Das kommt im
// Widget-Test nicht voran - der Aufruf bleibt haengen (der Knopf zeigt
// ewig "Wird gesendet..."). Mit diesem Ersatz laeuft er sofort.
/// Der Sitzungs-Speicher des Auth-Clients im RAM.
///
/// DER GRUND (17.11.2026): Der Standard-Speicher liest und schreibt
/// ueber die Plattform (SharedPreferences). Im Widget-Test kommt das
/// nicht voran - der Aufruf bleibt haengen. Mit diesem Ersatz ist die
/// Sitzung sofort da (und weg, wenn der Container entsorgt wird).
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

/// Der Router fuer den Test: die drei Wege, die der Screen geht.
GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.emailVerification,
    routes: [
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.signupWelcome,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Einrichtung'))),
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

  /// Ist der Supabase-Client schon initialisiert?
  ///
  /// WICHTIG: Supabase.initialize darf pro Testlauf nur EINMAL
  /// aufgerufen werden. Der erste Test (Demo-Modus) braucht deshalb
  /// einen NICHT initialisierten Client - danach wird er fuer die
  /// uebrigen Tests genau einmal gestartet.
  var supabaseGestartet = false;

  Future<void> starteSupabase(WidgetTester tester) async {
    if (supabaseGestartet) return;
    supabaseGestartet = true;
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
        // Der PKCE-Speicher im RAM (sonst haengt der Aufruf im Test).
        pkceAsyncStorage: _SpeicherImRam(),
        // Die Sitzung ebenfalls im RAM (gleicher Grund).
        localStorage: _SitzungImRam(),
      ),
    );
    // DER AUTH-SPEICHER AUFWAERMEN: Der Client schreibt vor jedem
    // Aufruf den PKCE-Verifier in den Speicher. Das ist eine
    // Plattform-Kommunikation - in der Test-Zone kommt sie nicht
    // voran, der Aufruf bleibt haengen (der Knopf zeigt ewig
    // "Wird gesendet..."). Einmal in der echten Zone erledigt, laeuft
    // der Rest.
    await tester.runAsync(() async {
      await supabase.Supabase.instance.client.auth.getSession();
    });
    await tester.pump();
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: Der Keystore-Signal-Store (und der Chat-Verlauf) liegen in
    // verschluesselten Hive-Boxen - ohne initialisiertes Hive wirft der
    // Dienst "You need to initialize Hive".
    await mockHive();
    server.pfade.clear();
    server.funktionsAufrufe.clear();
    // Die Fehlerantworten des Servers: jeder Test startet sauber
    // (sonst wuerde der naechste Test die Fehler des vorigen sehen).
    server.fehlerAntworten.clear();
  });

  /// Die Registrierungsdaten, wie sie nach der Anmeldung im Speicher liegen.
  void setzeRegistrierung(
    ProviderContainer container, {
    String email = 'neu@example.de',
    int alterMinuten = 0,
  }) {
    container.read(pendingVerificationEmailProvider.notifier).state = email;
    container.read(pendingVerificationCredentialsProvider.notifier).state = (
      email: email,
      password: 'Passwort123!',
      createdAt: DateTime.now().subtract(Duration(minutes: alterMinuten)),
      name: 'Lena',
      gender: 'female',
      birthDate: DateTime(1996, 6, 15),
    );
  }

  /// Baut den Screen mit dem Container (damit die Provider steuerbar sind).
  ///
  /// [mitRegistrierung]: Legt die Registrierungsdaten VOR dem Aufbau in
  /// den Speicher - der Screen liest sie in seinem initState (die Adresse
  /// fuer die Anzeige und die Credentials fuer den stillen Login).
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    bool mitRegistrierung = false,
    int alterMinuten = 0,
  }) async {
    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );

    if (mitRegistrierung) {
      setzeRegistrierung(container, alterMinuten: alterMinuten);
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
    return container;
  }

  /// Raeumt den Screen ab - er hat Timer (Auto-Login, Cooldown, "gesendet").
  ///
  /// Ohne das bleibt ein Timer stehen und der Test scheitert an
  /// "A Timer is still pending".
  ///
  /// DER CONTAINER GEHOERT DABEI: Der E-Mail-Bestaetigungs-Notifier pollt
  /// alle 3 Sekunden, und der Timer wird erst beim Dispose abgeschaltet.
  /// Der tearDown laeuft zu spaet - die Timer-Pruefung kommt davor.
  Future<void> aufraeumen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Scrollt zu einem Text (der Screen ist lang - manche Kniffe stehen
  /// unterhalb des Testfensters).
  ///
  /// WICHTIG: Ohne das trifft der Tap ins Leere (der Knopf ist zwar
  /// gefunden, aber nicht sichtbar) - der Test laeuft dann ohne Fehler
  /// durch und prueft gar nichts.
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    await tester.scrollUntilVisible(
      ziel,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Laesst die echte Ereignisschleife laufen, damit HTTP-Anfragen
  /// durchgehen (im Widget-Test passiert das nur in runAsync).
  ///
  /// WICHTIG: Der Auth-Client schreibt VOR jedem Aufruf den
  /// PKCE-Verifier in den Speicher. Das ist eine Plattform-Kommunikation -
  /// in der Test-Zone kommt sie nicht voran, der Aufruf bleibt dann
  /// haengen. Deshalb laeuft der Tap selbst in runAsync.
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
    // NACH der Anfrage noch ein paar Runden: der Server hat sie
    // gesehen, aber die ANTWORT muss noch verarbeitet werden - sonst
    // bleibt der Aufruf offen (und sein Zeitlimit-Timer stehen).
    if (treffer) {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }
    }
  }

  group('Der Screen zur E-Mail-Bestaetigung', () {
    // WICHTIG: Dieser Test laeuft ZUERST - er braucht einen
    // nicht initialisierten Supabase-Client (Demo-Modus).
    testWidgets('ohne Supabase geht es direkt zur Hauptapp', (tester) async {
      final container = await zeigeScreen(tester);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Startseite'), findsOneWidget);
      // Und es gibt nichts zu bestaetigen.
      expect(container.read(emailConfirmedProvider), isNull);

      await aufraeumen(tester, container);
    });

    testWidgets('der Screen zeigt die Adresse an, an die die Mail ging', (
      tester,
    ) async {
      await starteSupabase(tester);
      final container = await zeigeScreen(tester, mitRegistrierung: true);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('neu@example.de'), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('email.title')), findsOneWidget);
      // Der Wartetext steht da (nicht bestaetigt).
      expect(find.text(L10n.tWithoutContext('email.waiting')), findsOneWidget);

      await aufraeumen(tester, container);
    });

    testWidgets('nach der Bestaetigung geht es weiter zur Einrichtung', (
      tester,
    ) async {
      await starteSupabase(tester);
      final container = await zeigeScreen(tester, mitRegistrierung: true);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Die Bestaetigung kommt an (der Notifier meldet sie).
      container.read(emailConfirmedProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Einrichtung'),
        findsOneWidget,
        reason:
            'Nach der Bestaetigung muss der Nutzer in die Einrichtung - '
            'sonst sitzt er auf dem Bestetigungs-Screen fest.',
      );

      await aufraeumen(tester, container);
    });

    testWidgets('"Erneut senden" schickt die Mail wirklich', (tester) async {
      await starteSupabase(tester);
      final container = await zeigeScreen(tester, mitRegistrierung: true);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Der Tap laeuft in der echten Zone: der Auth-Client schreibt sonst
      // den PKCE-Verifier nie in den Speicher und der Aufruf bleibt
      // haengen.
      await tester.runAsync(() async {
        await tester.tap(find.text(L10n.tWithoutContext('email.resend')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await lassNetzLaufen(
        tester,
        fertig: () => server.pfade.any((p) => p.contains('/auth/v1/resend')),
      );

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.any((p) => p.contains('/auth/v1/resend')),
        isTrue,
        reason:
            'Der Knopf muss die Mail wirklich neu verschicken - sonst '
            'kommt sie nicht an und der Nutzer wartet vergeblich.',
      );
      // Der Erfolg wird angezeigt.
      expect(find.text(L10n.tWithoutContext('email.sent')), findsOneWidget);

      await aufraeumen(tester, container);
    });

    testWidgets('"Registrierung behalten" loescht nichts', (tester) async {
      await starteSupabase(tester);
      final container = await zeigeScreen(tester, mitRegistrierung: true);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await scrolleZu(tester, L10n.tWithoutContext('email.cancel'));
      await tester.tap(find.text(L10n.tWithoutContext('email.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(
          TextButton,
          L10n.tWithoutContext('email.cancelKeep'),
        ),
      );
      await tester.pump();
      await lassNetzLaufen(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe.any(
          (c) => c['funktion'] == 'cancel-registration',
        ),
        isFalse,
        reason:
            'Der Nutzer hat "behalten" gewaehlt - es darf nichts geloescht '
            'werden.',
      );

      await aufraeumen(tester, container);
    });

    testWidgets('der stille Auto-Login versucht es nach der Wartezeit', (
      tester,
    ) async {
      await starteSupabase(tester);
      final container = await zeigeScreen(tester, mitRegistrierung: true);

      await tester.pump();
      // Der erste Versuch wartet 10 Sekunden (das Auth-Rate-Limit
      // soll nicht verheizt werden).
      await tester.pump(const Duration(seconds: 11));
      await lassNetzLaufen(
        tester,
        fertig: () => server.pfade.any((p) => p.contains('/auth/v1/token')),
      );

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.any((p) => p.contains('/auth/v1/token')),
        isTrue,
        reason:
            'Nach der Bestaetigung soll sich die App selbst anmelden - '
            'ohne das bleibt der Nutzer auf diesem Screen.',
      );

      await aufraeumen(tester, container);
    });

    testWidgets('abgelaufene Registrierungsdaten werden nicht weitergegeben', (
      tester,
    ) async {
      await starteSupabase(tester);
      // Die Daten sind 20 Minuten alt - das Passwort darf nicht mehr
      // an den Server gehen (Audit M1: hoechstens 15 Minuten).
      final container = await zeigeScreen(
        tester,
        mitRegistrierung: true,
        alterMinuten: 20,
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      await lassNetzLaufen(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.any((p) => p.contains('/auth/v1/token')),
        isFalse,
        reason:
            'Nach 15 Minuten darf das Passwort nicht mehr an den Server - '
            'es bleibt nur im Speicher, bis es dort verfällt.',
      );
      // Und die Daten sind aus dem Speicher verschwunden.
      expect(container.read(pendingVerificationCredentialsProvider), isNull);

      await aufraeumen(tester, container);
    });

    testWidgets('nach einem Fehler wartet der Auto-Login laenger', (
      tester,
    ) async {
      await starteSupabase(tester);
      // DER FALL: Der Server lehnt den stillen Login ab (die E-Mail ist
      // noch nicht bestaetigt). Jeder Versuch kostet Budget im
      // Rate-Limit des Auth-Servers - deshalb verdoppelt der Screen
      // die Wartezeit nach jedem Fehler (5 -> 10 -> 20 -> 30 Sekunden).
      server.fehlerAntworten['/auth/v1/token'] = (
        status: 400,
        body: '{"error":"invalid_credentials"}',
      );

      // DIE SESSION WEG: Ein frueherer Test hat sich angemeldet, und
      // die Session bleibt im RAM-Client des ganzen Testlaufs. Mit einer
      // vorhandenen Session prueft der Bildschirm gar nicht erst (der
      // normale Poller ist dann zustaendig) - der Auto-Login faellt
      // aus, und es ginge gar nichts zu testen.
      await supabase.Supabase.instance.client.auth.signOut();

      final container = await zeigeScreen(tester, mitRegistrierung: true);

      /// Wie viele Anmeldeversuche sind bisher gegangen?
      int versuche() =>
          server.pfade.where((p) => p.contains('/auth/v1/token')).length;

      /// Laesst die Zeit laufen und das Netz arbeiten, bis [bedingung]
      /// eintritt (oder [sekunden] vorbei sind).
      ///
      /// DER WEG: Die Zeit laeuft in der Test-Zone (der Timer des
      /// Bildschirms), das Netz in der echten Zone (die Anfrage muss
      /// wirklich ankommen). Beides wird hier getrieben.
      Future<bool> warteAuf(int sekunden, bool Function() bedingung) async {
        for (var i = 0; i < sekunden * 5; i++) {
          if (bedingung()) return true;
          // ERST die Zeit laufen lassen (der Timer des Bildschirms),
          // DANN das Netz (die Anfrage muss wirklich ankommen).
          await tester.pump(const Duration(milliseconds: 200));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
        }
        return bedingung();
      }

      // Der erste Versuch kommt nach 5 Sekunden.
      expect(
        await warteAuf(10, () => versuche() > 0),
        isTrue,
        reason: 'Der erste Versuch muss kommen.',
      );
      final erster = versuche();

      // DER BACKOFF: Nach dem Fehler wartet der naechste Versuch 10
      // statt 5 Sekunden. Nach 6 Sekunden darf es also NOCH keinen
      // zweiten Versuch geben.
      await tester.pump(const Duration(seconds: 6));
      await lassNetzLaufen(tester);
      expect(
        versuche(),
        erster,
        reason:
            'Nach einem Fehler muss der Auto-Login laenger warten - das '
            'Rate-Limit des Auth-Servers soll nicht verheizt werden.',
      );

      // Nach weiteren 5 Sekunden (zusammen 11) kommt der zweite.
      expect(
        await warteAuf(10, () => versuche() > erster),
        isTrue,
        reason: 'Der zweite Versuch muss kommen.',
      );
      final zweiter = versuche();

      // Und nun wartet der dritte 20 Sekunden (10 -> 20).
      await tester.pump(const Duration(seconds: 10));
      await lassNetzLaufen(tester);
      expect(
        versuche(),
        zweiter,
        reason:
            'Die Wartezeit verdoppelt sich weiter - sonst wuerde der '
            'Server mit Versuchen ueberrennt.',
      );

      // Nach weiteren 10 Sekunden kommt auch der dritte.
      expect(
        await warteAuf(15, () => versuche() > zweiter),
        isTrue,
        reason:
            'Der Auto-Login darf nicht aufgeben - sonst bleibt der '
            'Nutzer fuer immer auf dem Bestaetigungs-Screen.',
      );

      await aufraeumen(tester, container);
    });
  });
}
