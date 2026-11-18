// Der Router: die Umleitungen - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/routing/app_router.dart 236 offene Zeilen. Genau hier entscheidet
// die App, was der Nutzer zu sehen bekommt: Willkommen oder Login, die
// E-Mail-Bestaetigung, die Einrichtung, der Admin-Bereich, die
// Verifikationssperre. Ein Fehler hier faellt niemandem auf - der Nutzer
// landet einfach auf dem falschen Bildschirm.
//
// WIE GETESTET WIRD: Die Umleitungs-Logik steckt jetzt in der eigenen
// Funktion `umleitung` (lib/routing/app_router.dart). Der Test ruft sie
// mit den Werten auf, die der Router vom Provider bekommt, und prueft,
// WOHIN der Nutzer geschickt wird (null = er bleibt, wo er ist).
//
// DER AUFBAU: Der Test setzt die Werte erst unmittelbar vor der
// Umleitung - so kann kein Hintergrundlauf (z. B. der Server-Sync nach
// dem Login) das Ergebnis ueberholen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/app_settings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/app_auth_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Die Anmeldung, die auf die E-Mail-Bestaetigung wartet.
typedef _Anmeldung = ({
  String email,
  String password,
  DateTime createdAt,
  String name,
  String? gender,
  DateTime birthDate,
});

/// Der Aufruf der Umleitung mit dem Ref des Containers.
///
/// DER WEG: Die Funktion `umleitung` braucht einen [Ref] - den gibt es
/// nur innerhalb eines Providers. Dieser Provider reicht sie als
/// Funktion weiter, damit der Test sie aufrufen kann.
final umleitungsAnbieter = Provider<Future<String?> Function(String)>((ref) {
  return (pfad) => umleitung(ref, pfad);
});

/// Der Speicher im RAM (nichts wird auf der Platte gespeichert).
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
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
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

/// Der Auth-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt die Session vom Server. Fuer den
/// Test ist nur wichtig, OB jemand eingeloggt ist - und das entscheidet
/// der Test selbst, nicht der Server.
class _Auth implements AppAuthService {
  @override
  Future<bool> restoreSession() async {
    // DER WEG: Die Wiederherstellung antwortet erst nach einem kleinen
    // Augenblick. Sonst wuerde sie den Auth-Status UEBERSCHreiben, bevor
    // der Router ihn liest - und der Server-Sync, der nach der Anmeldung
    // laeuft, wuerde die Test-Werte zerstoeren.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return false;
  }

  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    // Der Test meldet sich nicht an - der Zustand wird gesetzt.
  }

  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {
    // Der Test meldet sich nicht an - der Zustand wird gesetzt.
  }

  @override
  Future<void> logout() async {
    // Der Test meldet sich nicht ab - der Zustand wird gesetzt.
  }

  @override
  Future<void> deleteAccount() async {
    // Der Test loescht kein Konto.
  }

  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async {
    throw UnimplementedError('Der Test registriert niemanden.');
  }
}

/// Die Einstellungen als Ersatz (der Test gibt sie direkt vor).
class _Einstellungen extends SettingsNotifier {
  _Einstellungen(Ref ref) : super(_Speicher(), ref);
}

/// Das Profil als Ersatz (der Test gibt den Verifikationsstand vor).
class _Profil extends ProfileNotifier {
  _Profil() : super(_Speicher(), _Keystore());
}

/// Ein Testfall: der Container und die Lage, in der der Router
/// entscheidet.
class _Testfall {
  _Testfall({
    required this.container,
    required this.eingeloggt,
    required this.settings,
    this.verifikation = VerificationState.verified,
    this.settingsGeladen = true,
    this.syncFertig = true,
    this.flagsBekannt = true,
    this.passwortZuruecksetzen = false,
    this.emailAusstehend,
    this.registrierungAusstehend,
    this.mfa = const MfaStatus.initial(),
  });

  /// Der Container mit den Anbietern.
  final ProviderContainer container;

  /// Ist der Nutzer angemeldet?
  final bool eingeloggt;

  /// Die Einstellungen des Kontos.
  final AppSettings settings;

  /// Der Verifikationsstand des Profils.
  final VerificationState verifikation;

  /// Sind die Einstellungen aus dem Speicher geladen?
  final bool settingsGeladen;

  /// Ist der Server-Sync nach dem Login fertig?
  final bool syncFertig;

  /// Ist der Server-Stand der Setup-Flags bekannt?
  final bool flagsBekannt;

  /// Steht ein Passwort-Reset aus?
  final bool passwortZuruecksetzen;

  /// Die E-Mail-Adresse einer frischen Registrierung.
  final String? emailAusstehend;

  /// Die Anmeldung einer frischen Registrierung.
  final _Anmeldung? registrierungAusstehend;

  /// Der Stand der Zwei-Faktor-Absicherung.
  final MfaStatus mfa;

  /// Setzt die Lage und fragt die Umleitung fuer [pfad].
  ///
  /// DER WEG: Die Werte werden erst HIER gesetzt - ein Hintergrundlauf
  /// (z. B. der Server-Sync nach dem Login) kann das Ergebnis so nicht
  /// ueberholen.
  Future<String?> ziel(String pfad) async {
    container.read(authProvider.notifier).state = eingeloggt
        ? const AsyncValue.data(true)
        : const AsyncValue.data(false);
    container.read(profileProvider.notifier).state = UserProfile(
      id: 'ich',
      name: 'Lena',
      bio: '',
      verificationState: verifikation,
    );
    container.read(settingsProvider.notifier).state = settings;
    container.read(settingsLoadedProvider.notifier).state = settingsGeladen;
    container.read(serverSyncDoneProvider.notifier).state = syncFertig;
    container.read(setupFlagsKnownProvider.notifier).state = flagsBekannt;
    container.read(passwordRecoveryPendingProvider.notifier).state =
        passwortZuruecksetzen;
    container.read(pendingVerificationEmailProvider.notifier).state =
        emailAusstehend;
    container.read(pendingVerificationCredentialsProvider.notifier).state =
        registrierungAusstehend;
    container.read(mfaStatusProvider.notifier).state = mfa;

    final umleit = container.read(umleitungsAnbieter);
    return umleit(pfad);
  }
}

void main() {
  /// Der Ersatz-Server (die Session und das Profil kommen von dort).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockZeitzone();
    // DER SPEICHER: der Chat-Dienst oeffnet beim Start seine Box
    // (die Kontakte). Ohne den Ersatz schlaegt das im Test fehl.
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
    server.zeilen.clear();
    server.rpcAufrufe.clear();
  });

  /// Die Einstellungen eines fertig eingerichteten Kontos.
  AppSettings fertig() => AppSettings.defaults().copyWith(
    introSeen: true,
    onboardingDone: true,
    onboardingCompleted: true,
    oneTimeSettingsCompleted: true,
    communityGuidelinesAccepted: true,
    personalityTestCompleted: true,
    datingSafetyEducationCompleted: true,
    signupWelcomeSeen: true,
    datingHourIntroSeen: true,
  );

  /// Baut den Testfall.
  ///
  /// [session] entscheidet, ob der Server den Nutzer kennt. Ohne
  /// Session schickt der Router eingeloggte Nutzer zurueck zum Login
  /// ("Geister-Login" nach einem Datenbank-Reset).
  Future<_Testfall> baueTestfall({
    required bool eingeloggt,
    bool? session,
    AppSettings? settings,
    VerificationState verifikation = VerificationState.verified,
    bool settingsGeladen = true,
    bool syncFertig = true,
    bool flagsBekannt = true,
    bool passwortZuruecksetzen = false,
    String? emailAusstehend,
    _Anmeldung? registrierungAusstehend,
    MfaStatus mfa = const MfaStatus.initial(),
  }) async {
    // Die Session: der Server kennt den Nutzer (oder eben nicht).
    final mitSession = session ?? eingeloggt;
    if (mitSession) {
      await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    } else {
      await supabase.Supabase.instance.client.auth.signOut();
    }
    // Das Profil, das der Server meldet (der Verifikationsstand).
    server.zeilen['profiles'] = <String, dynamic>{
      'is_verified': verifikation == VerificationState.verified,
      'verification_status': verifikation == VerificationState.underReview
          ? 'pending'
          : 'unverified',
    };

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
        settingsProvider.overrideWith((ref) => _Einstellungen(ref)),
        profileProvider.overrideWith((ref) => _Profil()),
        authProvider.overrideWith(
          (ref) =>
              AuthNotifier(_Auth(), ref.read(profileProvider.notifier), ref),
        ),
      ],
    );
    // Der Auth-Status: er wird gleich gesetzt - die Wiederherstellung
    // (im Hintergrund) darf ihn nicht ueberschreiben. Ohne diese Reihen-
    // folge startet der Server-Sync nach der Anmeldung und zerstört die
    // Test-Werte.
    container.read(authProvider.notifier).state = eingeloggt
        ? const AsyncValue.data(true)
        : const AsyncValue.data(false);
    // Die Wiederherstellung laeuft im Hintergrund - der Test wartet sie
    // ab, damit sie nicht spaeter an einem abgebauten Container
    // scheitert.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _Testfall(
      container: container,
      eingeloggt: eingeloggt,
      settings: settings ?? fertig(),
      verifikation: verifikation,
      settingsGeladen: settingsGeladen,
      syncFertig: syncFertig,
      flagsBekannt: flagsBekannt,
      passwortZuruecksetzen: passwortZuruecksetzen,
      emailAusstehend: emailAusstehend,
      registrierungAusstehend: registrierungAusstehend,
      mfa: mfa,
    );
  }

  group('Der Router, wenn niemand eingeloggt ist', () {
    test('der Erststart zeigt die Willkommensseite', () async {
      final fall = await baueTestfall(
        eingeloggt: false,
        settings: AppSettings.defaults().copyWith(introSeen: false),
      );
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.loading), AppRoutes.welcome);
    });

    test('ab dem zweiten Start kommt der Login', () async {
      final fall = await baueTestfall(eingeloggt: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.loading), AppRoutes.login);
    });

    test('die Login-Seite bleibt, wo sie ist', () async {
      final fall = await baueTestfall(eingeloggt: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.login), isNull);
      expect(await fall.ziel(AppRoutes.forgotPassword), isNull);
      expect(await fall.ziel(AppRoutes.welcome), isNull);
    });

    test('ohne Anmeldung geht es nur zum Login', () async {
      final fall = await baueTestfall(eingeloggt: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel('/chat/7'), AppRoutes.login);
      expect(await fall.ziel(AppRoutes.profile), AppRoutes.login);
    });

    test('die Einrichtung ist ohne Anmeldung tabu', () async {
      final fall = await baueTestfall(eingeloggt: false);
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.settingsPrivacyOnce),
        AppRoutes.login,
        reason:
            'Ohne Anmeldung darf die Einrichtung nicht beginnen - '
            'sonst waere das Konto ungesichert.',
      );
      expect(await fall.ziel(AppRoutes.onboarding), AppRoutes.login);
    });

    test('eine frische Registrierung geht zur E-Mail-Bestaetigung', () async {
      final fall = await baueTestfall(
        eingeloggt: false,
        registrierungAusstehend: (
          email: 'lena@example.com',
          password: 'geheim',
          createdAt: DateTime.now(),
          name: 'Lena',
          gender: null,
          birthDate: DateTime(1995, 6, 1),
        ),
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.settingsPrivacyOnce),
        AppRoutes.emailVerification,
        reason:
            'Nach der Registrierung kommt die E-Mail-Bestaetigung - erst '
            'danach darf die Einrichtung beginnen.',
      );
      expect(
        await fall.ziel(AppRoutes.onboarding),
        AppRoutes.emailVerification,
      );
    });

    test('eine wartende E-Mail-Adresse reicht auch', () async {
      final fall = await baueTestfall(
        eingeloggt: false,
        emailAusstehend: 'lena@example.com',
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.personalityTest),
        AppRoutes.emailVerification,
      );
    });
  });

  group('Der Router, wenn der Nutzer eingeloggt ist', () {
    test('die Startseite bleibt, wo sie ist', () async {
      final fall = await baueTestfall(eingeloggt: true);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), isNull);
      expect(await fall.ziel(AppRoutes.profile), isNull);
    });

    test('der Lade-Screen fuehrt zur Startseite', () async {
      final fall = await baueTestfall(eingeloggt: true);
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.loading),
        AppRoutes.home,
        reason:
            'Nach dem Start soll die Startseite offen sein - nicht die '
            'zuletzt besuchte Seite.',
      );
    });

    test('die Anmelde-Seiten sind nach der Einrichtung tabu', () async {
      final fall = await baueTestfall(eingeloggt: true);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.welcome), AppRoutes.home);
      expect(await fall.ziel(AppRoutes.login), AppRoutes.home);
      expect(await fall.ziel(AppRoutes.forgotPassword), AppRoutes.home);
      expect(await fall.ziel(AppRoutes.settingsPrivacyOnce), AppRoutes.home);
    });

    test('der Admin-Bereich ist nur fuer den Admin', () async {
      final fall = await baueTestfall(eingeloggt: true);
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.admin),
        AppRoutes.home,
        reason:
            'Normale Nutzer duerfen den Admin-Bereich unter keinen '
            'Umstaenden erreichen - auch nicht ueber einen Deep-Link.',
      );
    });

    test('ohne Server-Session geht es zurueck zum Login', () async {
      // "Geister-Login": der Zustand sagt "eingeloggt", aber es gibt
      // keine Session mehr (z. B. nach einem Datenbank-Reset).
      final fall = await baueTestfall(eingeloggt: true, session: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.login);
    });

    test('waehrend des Server-Syncs bleibt der Lade-Screen', () async {
      final fall = await baueTestfall(eingeloggt: true, syncFertig: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.loading), isNull);
      expect(await fall.ziel(AppRoutes.home), AppRoutes.loading);
    });

    test('solange die Einstellungen kommen, wird nichts umgeleitet', () async {
      final fall = await baueTestfall(eingeloggt: true, settingsGeladen: false);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.welcome), isNull);
    });
  });

  group('Der Router und die Verifikationspflicht', () {
    test('ohne Verifikation geht es zur Modus-Auswahl', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        verifikation: VerificationState.unverified,
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.findYourMatch),
        AppRoutes.swipeModeSelection,
        reason:
            'Find your Spark vermittelt an Fremde - ohne Verifikation '
            'darf der Nutzer dort nicht hinein.',
      );
      expect(
        await fall.ziel(AppRoutes.transitRadar),
        AppRoutes.swipeModeSelection,
      );
      expect(
        await fall.ziel(AppRoutes.datingHourEvent),
        AppRoutes.swipeModeSelection,
      );
    });

    test('mit Verifikation bleibt der Nutzer auf der Seite', () async {
      final fall = await baueTestfall(eingeloggt: true);
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.findYourMatch), isNull);
      expect(await fall.ziel(AppRoutes.transitRadar), isNull);
    });
  });

  group('Der Router und die Einrichtung', () {
    /// Die Einstellungen eines Kontos, dessen Einrichtung offen ist.
    AppSettings offen() => AppSettings.defaults().copyWith(
      introSeen: true,
      onboardingDone: false,
      onboardingCompleted: false,
      oneTimeSettingsCompleted: false,
      communityGuidelinesAccepted: false,
      personalityTestCompleted: false,
      datingSafetyEducationCompleted: false,
      signupWelcomeSeen: true,
      datingHourIntroSeen: true,
    );

    test('zuerst kommt die Sicherheits-Aufklaerung', () async {
      final fall = await baueTestfall(eingeloggt: true, settings: offen());
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.datingSafetyEducation);
    });

    test('danach die Einstellungen und die Privatsphaere', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: offen().copyWith(datingSafetyEducationCompleted: true),
      );
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.settingsPrivacyOnce);
    });

    test('die Community-Regeln sind ein eigener Schritt', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: offen().copyWith(
          datingSafetyEducationCompleted: true,
          oneTimeSettingsCompleted: true,
        ),
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.home),
        AppRoutes.settingsPrivacyOnce,
        reason:
            'Die Community-Regeln werden auf derselben Seite bestaetigt - '
            'der Router darf den Nutzer nicht ueberspringen lassen.',
      );
    });

    test('zuletzt kommt der Persoenlichkeitstest', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: offen().copyWith(
          datingSafetyEducationCompleted: true,
          oneTimeSettingsCompleted: true,
          communityGuidelinesAccepted: true,
        ),
      );
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.personalityTest);
    });

    test('eine abgeschlossene Einrichtung wird nicht erzwungen', () async {
      // "NIEMALS-EINRICHTUNG"-GARANTIE: Ist der Server-Stand nicht
      // bekannt, wird die Einrichtung nicht erzwungen.
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: offen(),
        flagsBekannt: false,
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.home),
        isNull,
        reason:
            'Nach einer Neuinstallation darf die Einrichtung nicht wieder '
            'erscheinen - sonst ist die App unbenutzbar.',
      );
    });

    test('der Willkommensscreen nach der Registrierung kommt zuerst', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: offen().copyWith(signupWelcomeSeen: false),
      );
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.signupWelcome);
    });
  });

  group('Der Router und die Sonderfaelle', () {
    test('der Passwort-Reset hat Vorrang', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        passwortZuruecksetzen: true,
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.home),
        AppRoutes.resetPassword,
        reason:
            'Solange das Passwort zurueckgesetzt wird, ist nur der '
            'Reset-Screen erreichbar.',
      );
      expect(await fall.ziel(AppRoutes.resetPassword), isNull);
    });

    test('die 2FA-Abfrage kommt vor allen anderen Seiten', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        mfa: const MfaStatus(
          currentAal: 'aal1',
          hasVerifiedFactors: true,
          hasAnyFactor: true,
          loaded: true,
        ),
      );
      addTearDown(fall.container.dispose);

      expect(await fall.ziel(AppRoutes.home), AppRoutes.mfaChallenge);
      expect(await fall.ziel(AppRoutes.mfaChallenge), isNull);
    });

    test('die Dating Hour zeigt zuerst ihre Regeln', () async {
      final fall = await baueTestfall(
        eingeloggt: true,
        settings: AppSettings.defaults().copyWith(
          introSeen: true,
          onboardingDone: true,
          oneTimeSettingsCompleted: true,
          communityGuidelinesAccepted: true,
          personalityTestCompleted: true,
          datingSafetyEducationCompleted: true,
          signupWelcomeSeen: true,
          datingHourIntroSeen: false,
        ),
      );
      addTearDown(fall.container.dispose);

      expect(
        await fall.ziel(AppRoutes.datingHourEvent),
        AppRoutes.datingHourRules,
      );
    });
  });
}
