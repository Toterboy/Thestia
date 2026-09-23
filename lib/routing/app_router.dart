import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/app_settings.dart';
import 'package:wisp/routing/route_restore.dart';

import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/screens/auth/login_screen.dart';
import 'package:wisp/screens/auth/forgot_password_screen.dart';
import 'package:wisp/screens/auth/reset_password_screen.dart';
import 'package:wisp/screens/auth/unban_request_screen.dart';
import 'package:wisp/screens/auth/email_verification_screen.dart';
import 'package:wisp/screens/auth/mfa_setup_screen.dart';
import 'package:wisp/screens/auth/mfa_challenge_screen.dart';
import 'package:wisp/screens/core/loading_screen.dart';
import 'package:wisp/screens/welcome/welcome_screen.dart';
import 'package:wisp/screens/core/error_screen.dart';
import 'package:wisp/screens/home/home_screen.dart';
import 'package:wisp/screens/core/main_navigation.dart';
import 'package:wisp/screens/interests/interessen_screen.dart';
import 'package:wisp/screens/onboarding/onboarding_screen.dart';
import 'package:wisp/screens/onboarding/personality_test_screen.dart';
import 'package:wisp/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:wisp/screens/mood/mood_picker_screen.dart';
import 'package:wisp/screens/core/whats_new_screen.dart';
import 'package:wisp/services/whats_new_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/screens/privacy/privacy_screen.dart';
import 'package:wisp/screens/settings/devices_screen.dart';
import 'package:wisp/screens/profile/profile_edit_screen.dart';
import 'package:wisp/screens/profile/profile_screen.dart';
import 'package:wisp/screens/settings/settings_screen.dart';
import 'package:wisp/screens/admin/admin_screen.dart';
import 'package:wisp/screens/swipe/swipe_mode_selection_screen.dart';
import 'package:wisp/screens/swipe/find_your_match_screen.dart';
import 'package:wisp/screens/quiz/quiz_screen.dart';
import 'package:wisp/screens/spice/spice_questions_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_chat_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_event_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_how_it_works_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_preferences_screen.dart';
import 'package:wisp/screens/dating_hour/dating_hour_rules_screen.dart';
import 'package:wisp/screens/verification/verification_flow.dart';
import 'package:wisp/screens/safety/safety_center_screen.dart';
import 'package:wisp/screens/chat/chat_detail_screen.dart';
import 'package:wisp/screens/profile/profile_detail_screen.dart';
import 'package:wisp/screens/swipe/random_chat_screen.dart';
import 'package:wisp/screens/swipe/transit_radar_screen.dart';
import 'package:wisp/screens/bug_report/bug_report_screen.dart';
import 'package:wisp/screens/qr/qr_profile_screen.dart';
import 'package:wisp/screens/qr/qr_scan_screen.dart';
import 'package:wisp/screens/legal/community_guidelines_screen.dart';
import 'package:wisp/widgets/back_to_route_scope.dart';

/// Zentrale Routen der App.
class AppRoutes {
  AppRoutes._();

  static const String welcome = '/welcome';
  static const String loading = '/loading';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  // Passwort-Reset (Ziel des Recovery-Deep-Links wisp://reset-password)
  static const String resetPassword = '/reset-password';
  // Entsperrungsantrag für gesperrte E-Mail-Adressen (öffentlich)
  static const String unbanRequest = '/unban-request';
  static const String home = '/';
  static const String findYourMatch = '/find-your-match';
  static const String interessen = '/interessen';
  static const String quiz = '/quiz/:matchId';
  // Spice Questions (Eisbrecher-Fragen, Feature A)
  static const String spiceQuestions = '/spice/:matchId';
  static const String chatDetail = '/chat/:matchId';
  static const String profile = '/profile';
  static const String profileEdit = '/profile/edit';
  static const String profileDetail = '/profile/:userId';
  static const String settings = '/settings';
  static const String personalityTest = '/personality-test';
  static const String settingsPrivacyOnce = '/settings-privacy-once';
  static const String swipeModeSelection = '/swipe-mode-selection';
  static const String randomChat = '/random-chat';
  // Transit Spark (v0.9.0)
  static const String transitRadar = '/transit/radar';
  static const String bugReport = '/bug-report';
  // QR-Code (Profil teilen + Scannen)
  static const String qrProfile = '/qr/profile';
  static const String qrScan = '/qr/scan';
  // Mood of the Day
  static const String moodPicker = '/mood/picker';
  // "Neu in dieser Version" (App-Update-Popup für Registrierte).
  static const String whatsNew = '/whats-new';
  // Datenschutz & Account (DSGVO)
  static const String privacy = '/privacy';
  static const String safetyCenter = '/safety-center';
  // Geräte & Sitzungen ("Wo bin ich eingeloggt?")
  static const String devices = '/devices';
  // Dating Hour (Event-Modus)
  static const String datingHourEvent = '/dating-hour';
  static const String datingHourPreferences = '/dating-hour/preferences';
  static const String datingHourChat = '/dating-hour/chat/:sessionId';
  static const String datingHourRules = '/dating-hour/rules';
  static const String datingHourHowItWorks = '/dating-hour/how-it-works';
  // Verifizierung
  static const String verificationVideo = '/verification/video';
  static const String verificationComplete = '/verification/complete';
  static const String verificationInfo = '/verification/info';
  static const String emailVerification = '/email-verification';
  // Zwei-Faktor-Schutz (TOTP/Authenticator-App)
  static const String mfaSetup = '/mfa-setup';
  static const String mfaChallenge = '/mfa-challenge';
  // Community-Regeln
  static const String communityGuidelines = '/community-guidelines';

  // Geschuetzter Admin-Bereich (nur ueber versteckten Zugang, nur fuer Admin-ID)
  static const String admin = '/admin';

  /// Baut die konkrete Chat-Detail-URL für ein Match (ersetzt den
  /// Platzhalter `:matchId` durch die tatsächliche ID). Verhindert
  /// fehleranfälliges manuelles Zusammensetzen der URL.
  static String chatDetailPath(String matchId) => '/chat/$matchId';

  /// Baut die Quiz-URL für ein Match.
  static String quizPath(int matchId) => '/quiz/$matchId';

  /// Baut die Spice-Questions-URL für ein Match.
  static String spiceQuestionsPath(int matchId) => '/spice/$matchId';

  /// Baut die konkrete Profil-Detail-URL für ein fremdes Profil.
  static String profileDetailPath(String userId) => '/profile/$userId';

  /// Baut die Dating Hour Chat URL.
  static String datingHourChatPath(String sessionId) =>
      '/dating-hour/chat/$sessionId';

  /// Baut die Verifizierungs-Info URL mit Code-Parameter.
  static String verificationInfoPath(String code) =>
      '/verification/info?code=$code';
}

/// Benachrichtigt den [GoRouter], sobald sich der Auth-Status ODER die
/// App-Einstellungen (z. B. `introSeen`, `onboardingCompleted`, ⬦) ändern.
///
/// Ohne dieses [Listenable] würde der `redirect`-Callback nur bei einer
/// echten Navigation neu ausgewertet - asynchrone Zustandsänderungen
/// (Session-Wiederherstellung, Laden der gespeicherten Einstellungen,
/// Abschluss eines Setup-Schritts) blieben dann unbemerkt und der Nutzer
/// könnte auf einem Zwischenscreen "hängen" oder auf der Fehlerseite landen.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    // Auf alle relevanten Provider hören und bei jeder Änderung neu
    // evaluieren lassen.
    ref.listen<AsyncValue<bool>>(authProvider, (_, _) => notifyListeners());
    ref.listen<AppSettings>(settingsProvider, (_, _) => notifyListeners());
    // Auch auf das Settings-Lade-Flag hören: Erst wenn Auth UND Settings
    // geladen sind, wird die initiale Route bestimmt.
    ref.listen<bool>(settingsLoadedProvider, (_, _) => notifyListeners());
    // Server-Sync (Setup-Flags nach Login) ebenfalls abwarten.
    ref.listen<bool>(serverSyncDoneProvider, (_, _) => notifyListeners());
    ref.listen<bool?>(emailConfirmedProvider, (_, _) => notifyListeners());
    // MFA-Status (Challenge nötig / Setup-Prompt) ebenfalls beobachten.
    ref.listen<MfaStatus>(mfaStatusProvider, (_, _) => notifyListeners());
  }
}

/// Globaler RouteObserver (v0.9.1): Screens laden neu, wenn man per
/// Zurück-Geste von einem gepushten Screen zurückkehrt (z. B. Funken nach
/// Chat-Besuch) oder die App aus dem Hintergrund kommt.
final routeObserver = RouteObserver<ModalRoute<void>>();

/// Erstellt den [GoRouter] mit Redirect-Logik basierend auf
/// Auth-Status und Onboarding-Fortschritt.
GoRouter createRouter(Ref ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    observers: [routeObserver],
    // Neutraler Lade-Screen als Start-Route. Während Auth- und Settings-Check
    // laufen, bleibt die App hier (optisch identisch zum nativen Splash).
    // Die finale Start-Route wird erst nach Abschluss beider Checks im
    // redirect bestimmt - so erscheint beim Erststart garantiert zuerst
    // der Willkommens-Screen statt des "Konto erstellen"-Screens.
    initialLocation: AppRoutes.loading,
    // Router bei Auth-/Settings-Änderungen neu evaluieren.
    refreshListenable: refresh,
    // Fallback bei unbekannten Routen: freundliche Fehlerseite mit
    // funktionierendem Button zurück zum sinnvollen Ausgangspunkt.
    errorBuilder: (context, state) => const ErrorScreen(),
    redirect: (context, state) async {
      final auth = ref.read(authProvider);
      final settingsReady = ref.read(settingsLoadedProvider);

      // Solange der Auth-Status ODER die Einstellungen noch geladen werden,
      // keine Redirects auslösen - auf dem Lade-Screen bleiben. Sonst würde
      // die falsche Default-Route (Login/"Konto erstellen") vor den
      // Willkommensscreens aufblitzen. Der refreshListenable stööt die
      // Auswertung erneut an, sobald beide Zustände feststehen.
      if (auth.isLoading || !settingsReady) return null;

      // Passwort-Reset (Recovery-Deep-Link aus der E-Mail): Solange der
      // Reset aussteht, ist ausschließlich der Reset-Screen erreichbar –
      // auch während des Server-Syncs und unabhängig vom Setup-Stand.
      if (ref.read(passwordRecoveryPendingProvider)) {
        return state.matchedLocation == AppRoutes.resetPassword
            ? null
            : AppRoutes.resetPassword;
      }

      final settings = ref.read(settingsProvider);
      final loggedIn = auth.valueOrNull ?? false;
      final introSeen = settings.introSeen;

      // Server-Sync (Profil + Setup-Flags) nach Login abwarten: Sonst
      // blitzt nach einer App-Neuinstallation die Einrichtung auf, bevor
      // die serverseitigen Flags geladen sind. Solange der Sync läuft,
      // auf dem Lade-Screen bleiben.
      final syncDone = ref.read(serverSyncDoneProvider);
      if (loggedIn && !syncDone) {
        return state.matchedLocation == AppRoutes.loading
            ? null
            : AppRoutes.loading;
      }

      final goingToLoading = state.matchedLocation == AppRoutes.loading;
      final goingToWelcome = state.matchedLocation == AppRoutes.welcome;
      final goingToLogin = state.matchedLocation == AppRoutes.login;
      final goingToForgotPassword =
          state.matchedLocation == AppRoutes.forgotPassword;
      final goingToResetPassword =
          state.matchedLocation == AppRoutes.resetPassword;
      final goingToUnbanRequest =
          state.matchedLocation == AppRoutes.unbanRequest;
      final goingToSettingsPrivacyOnce =
          state.matchedLocation == AppRoutes.settingsPrivacyOnce;
      final goingToOnboarding = state.matchedLocation == AppRoutes.onboarding;
      final goingToPersonalityTest =
          state.matchedLocation == AppRoutes.personalityTest;
      final goingToDatingHour =
          state.matchedLocation == AppRoutes.datingHourEvent;
      final goingToWhatsNew = state.matchedLocation == AppRoutes.whatsNew;

      // -- Admin-Bereich: NUR fuer die konfigurierte Admin-ID --
      // Normale Nutzer duerfen diesen Screen unter keinen Umstaenden
      // erreichen. Direkter URL-Aufruf wird zur Startseite umgeleitet.
      if (state.matchedLocation == AppRoutes.admin && !isCurrentUserAdmin()) {
        return AppRoutes.home;
      }
      if (!loggedIn) {
        // Vom Lade-Screen direkt auf die korrekte Start-Screen leiten:
        // Erststart -> Willkommen, sonst -> Login.
        if (goingToLoading) {
          return introSeen ? AppRoutes.login : AppRoutes.welcome;
        }
        // HARTES E-Mail-Gate (Nutzer-Regel: erst bestätigen, dann
        // einrichten): Ohne Session ist die Einrichtung tabu – auch
        // mit laufender Registrierung. Frische Registrierungen gehen
        // zur E-Mail-Bestätigung, alle anderen zum Login. So kann kein
        // Navigationspfad (auch kein verfrühter Sprung aus dem
        // Login-Screen) mehr Setup ohne bestätigte E-Mail erreichen.
        final goingToSetup =
            goingToSettingsPrivacyOnce ||
            goingToOnboarding ||
            goingToPersonalityTest;
        if (goingToSetup) {
          final freshRegistration =
              ref.read(pendingVerificationCredentialsProvider) != null ||
              ref.read(pendingVerificationEmailProvider) != null;
          return freshRegistration
              ? AppRoutes.emailVerification
              : AppRoutes.login;
        }
        // Einführung nur beim allerersten Start zeigen: Der Welcome-Screen
        // setzt introSeen bereits beim ANZEIGEN (initState) – deshalb darf
        // der Router einen Nicht-Eingeloggten auf /welcome NICHT mehr
        // wegredirecten, sobald introSeen true ist (sonst wirft er den
        // Nutzer direkt nach dem ersten Frame wieder runter).
        // KEIN Login->Welcome-Redirect mehr: Dieser warf den Nutzer nach
        // einer FEHLGESCHLAGENEN Registrierung (introSeen noch false,
        // keine pendingVerification) auf den Welcome-Screen – deshalb
        // kam "Willkommen" scheinbar erst NACH der Registrierung. Der
        // Erststart läuft ausschließlich über den Lade-Screen-Pfad
        // (loading -> welcome, siehe oben).
        final pendingRegistration =
            ref.read(pendingVerificationCredentialsProvider) != null;
        if (pendingRegistration) {
          // Mitten im Registrierungs-Flow (E-Mail-Bestätigung ausstehend)
          // auf dem Login-Screen bleiben.
          return null;
        }
        if (goingToLogin ||
            goingToForgotPassword ||
            goingToResetPassword ||
            goingToUnbanRequest ||
            goingToWelcome) {
          return null;
        }
        return AppRoutes.login;
      }

      // -- Eingeloggt --
      // Einrichtungs-Reihenfolge (strikt sequenziell, sonst Schleife!):
      //   0) E-Mail-Bestätigung (direkt nach der Registrierung – BEVOR der
      //      Nutzer weitere Angaben machen muss)
      //   1) Einrichtung (Einstellungen & Privatsphäre)
      //   2) Onboarding-Daten (Bio, Interessen, Stadt, etc.)
      //   3) Persönlichkeitstest (LETZTER Schritt der Einrichtung)
      // Jeder Setup-Screen navigiert am Ende einfach zu AppRoutes.home;
      // die Redirect-Logik holt den Nutzer automatisch zum nächsten
      // offenen Schritt - so entstehen keine Sprünge oder Schleifen.
      //
      // WICHTIG: Die Schritte dürfen NICHT unabhängig geprüft werden, da
      // sonst Schleifen entstehen (z. B. /settings-privacy-once -> /onboarding
      // -> /settings-privacy-once -> ⬦). Stattdessen wird jeder Schritt nur
      // geprüft, wenn die vorherigen bereits erledigt sind.

      // Sicherheitsnetz gegen "Geister-Login": Zustand "eingeloggt" OHNE
      // aktive Supabase-Session und ohne laufende Registrierung (z. B.
      // invalidierte Alt-Session nach Datenbank-Reset) darf den Nutzer
      // nicht im E-Mail-Bestätigungs-Screen einsperren – ohne User gibt es
      // nichts zu bestätigen und "Erneut senden" schlägt fehl. Zurück zum
      // Login, wo eine neue Registrierung möglich ist.
      final supabaseActive = SupabaseService.isInitialized;
      if (supabaseActive &&
          SupabaseService.client.auth.currentUser == null &&
          ref.read(pendingVerificationCredentialsProvider) == null &&
          ref.read(pendingVerificationEmailProvider) == null) {
        return state.matchedLocation == AppRoutes.login
            ? null
            : AppRoutes.login;
      }

      // Schritt 0: E-Mail-Bestaetigung fuer eingeloggte Nutzer erzwingen –
      // VOR der Einrichtung. So kommt nach der Registrierung zuerst die
      // Bestätigung und erst danach Settings/Privacy, Persönlichkeitstest etc.
      // Ausnahmen: Bug-Report und andere Utility-Seiten brauchen keine
      // bestätigte E-Mail.
      //
      // Fast-Path: Ist in der Session bereits eine bestätigte E-Mail
      // hinterlegt (z. B. direkt nach dem Login), gilt der Nutzer sofort als
      // bestätigt – sonst blitzt der E-Mail-Verify-Screen kurz auf, bis der
      // 3-Sekunden-Poller das feststellt.
      final emailConfirmed = ref.read(emailConfirmedProvider);
      final sessionConfirmed =
          supabaseActive &&
          SupabaseService.client.auth.currentUser?.emailConfirmedAt != null;
      if (supabaseActive && emailConfirmed != true && !sessionConfirmed) {
        final location = state.matchedLocation;
        // Seiten die OHNE E-Mail-Bestätigung erreichbar sein müssen:
        final exempt =
            location == AppRoutes.emailVerification ||
            location == AppRoutes.bugReport;
        if (!exempt) {
          return AppRoutes.emailVerification;
        }
        return null;
      }

      // Schritt 0.5: Zwei-Faktor-Schutz (TOTP/Authenticator-App).
      //
      // Verifizierte Faktoren vorhanden, Session aber nur AAL1
      // (Passwort-Login) -> Code-Abfrage VOR jedem anderen Screen.
      // Die EINRICHTUNG selbst ist bewusst KEIN Router-Zwang mehr: Sie
      // läuft als überspringbarer Schritt in der Erst-Einrichtung
      // (SettingsPrivacyOnceScreen) und jederzeit über die Einstellungen.
      final mfa = ref.read(mfaStatusProvider);
      if (mfa.loaded) {
        final location = state.matchedLocation;
        final mfaExempt =
            location == AppRoutes.mfaChallenge ||
            location == AppRoutes.mfaSetup ||
            location == AppRoutes.emailVerification ||
            location == AppRoutes.bugReport;
        if (mfa.needsChallenge && !mfaExempt) {
          return AppRoutes.mfaChallenge;
        }
      }

      // Während der Einrichtung dürfen Hilfs-Screens (2FA-Einrichtung,
      // 2FA-Challenge, Bug-Report) erreicht werden, ohne dass der Router
      // zur ersten Einrichtungsseite zurückschmeißt. Sonst landet man nach
      // "Jetzt einrichten" (2FA) wieder auf Seite 1 der Einrichtung.
      final setupExempt =
          goingToSettingsPrivacyOnce ||
          state.matchedLocation == AppRoutes.mfaSetup ||
          state.matchedLocation == AppRoutes.mfaChallenge ||
          state.matchedLocation == AppRoutes.bugReport;

      // "NIEMALS-EINRICHTUNG"-GARANTIE:
      // Die Einrichtung / der Persönlichkeitstest werden NIE wieder
      // erzwungen, sobald onboardingDone true ist (mindestens einmal
      // abgeschlossen, serverseitig gespiegelt als profiles.onboarding_done,
      // Migration 065) - unabhängig von Einzelflag-Ständen und übersprungenen
      // Punkten.
      //
      // Zusätzliche Absicherung gegen "Einrichtung erscheint nach
      // Neuinstallation erneut": Ist der Server-Stand NICHT bekannt
      // (Setup-Flags-Sync insgesamt fehlgeschlagen), wird ebenfalls NICHT
      // erzwungen - außer bei einer frischen REGISTRIERUNG, wo die
      // Einrichtung ja gerade zum ersten Mal laufen soll.
      final flagsKnown = ref.read(setupFlagsKnownProvider);
      final freshRegistration =
          ref.read(pendingVerificationCredentialsProvider) != null;
      final enforceSetup =
          !settings.onboardingDone && (flagsKnown || freshRegistration);

      if (enforceSetup && !settings.oneTimeSettingsCompleted) {
        if (!setupExempt) return AppRoutes.settingsPrivacyOnce;
        return null;
      }
      if (enforceSetup && !settings.communityGuidelinesAccepted) {
        if (!setupExempt) return AppRoutes.settingsPrivacyOnce;
        return null;
      }
      if (enforceSetup && !settings.personalityTestCompleted) {
        if (!goingToPersonalityTest) return AppRoutes.personalityTest;
        return null;
      }

      // Verifizierungs-Flow per Feature-Flag gesperrt (Betreiber-Entscheidung):
      // Routen sind nicht erreichbar und leiten auf Home um.
      // Reaktivierung: --dart-define=VERIFICATION_ENABLED=true.
      if (!AppConstants.verificationEnabled) {
        final location = state.matchedLocation;
        if (location == AppRoutes.verificationVideo ||
            location == AppRoutes.verificationComplete ||
            location == AppRoutes.verificationInfo) {
          return AppRoutes.home;
        }
      }

      // -- "Neu in dieser Version" (NUTZERWUNSCH): Nach einem App-Update
      // (Build gestiegen) bekommen bereits eingerichtete Konten EINMALIG
      // die Änderungs-Kurzfassung + Nachfragen zu neuen Angaben (z. B.
      // Geburtstags-Stil). Bewusst als EIGENE Route (kein Overlay-Dialog):
      // Der Router bleibt Single-Source-of-Truth, und der Screen navigiert
      // sich selbst zu Home ab. Fail-open: Bei Fehlern (z. B. Storage)
      // wird der Screen übersprungen, nie blockiert.
      if (!goingToWhatsNew) {
        try {
          final currentBuild = await WhatsNewService.currentBuild();
          final shown = await WhatsNewService.shownBuild(
            ref.read(localStorageProvider),
          );
          final show = WhatsNewService.shouldShow(
            currentBuild: currentBuild,
            shownBuild: shown,
            registered: true,
            onboardingDone: settings.onboardingDone,
          );
          if (show) {
            // Sofort markieren (Kill-Schutz: kein Endlos-Popup, siehe
            // WhatsNewService-Doku).
            await WhatsNewService.markShown(
              ref.read(localStorageProvider),
              currentBuild,
            );
            return AppRoutes.whatsNew;
          }
        } catch (_) {
          // Fail-open: Gate überspringen statt App zu blockieren.
        }
      }

      // Ab hier ist die Einrichtung vollständig abgeschlossen.
      //
      // Intro/Auth-Screens und die EINMALIGEN Setup-Screens
      // (Einstellungen & Privatsphäre, Onboarding) ergeben jetzt keinen Sinn
      // mehr -> zurück zur Startseite.
      //
      // WICHTIG: Der Persönlichkeitstest ist bewusst NICHT dabei, damit er
      // aus den Einstellungen heraus jederzeit wiederholt werden kann
      // ("Test wiederholen"). Sonst würde der Router den Nutzer sofort wieder
      // nach Home werfen und der Button hätte keine Wirkung.
      if (goingToWelcome ||
          goingToLogin ||
          goingToForgotPassword ||
          goingToResetPassword ||
          goingToSettingsPrivacyOnce ||
          goingToOnboarding) {
        return AppRoutes.home;
      }

      // Dating Hour Intro: Beim ersten Besuch zuerst Regeln und Erklärung zeigen.
      if (!settings.datingHourIntroSeen) {
        if (goingToDatingHour) return AppRoutes.datingHourRules;
        if (state.matchedLocation == AppRoutes.datingHourHowItWorks) {
          return null;
        }
      }

      // Eingeloggter Nutzer, der noch auf dem Lade-Screen steht: Einrichtung
      // ist offenbar vollständig abgeschlossen -> IMMER zur Startseite
      // ("Aktuelles"). Betreiber-Entscheidung: Der App-Start soll die
      // Startseite öffnen, nicht die zuletzt offene Seite; das Route-
      // Restore (v0.9.1) wird daher nicht mehr angewendet (der gespeicherte
      // Wert wird nur konsumiert, damit er nicht stehen bleibt).
      if (goingToLoading) {
        consumePendingRouteRestore();
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.unbanRequest,
        builder: (context, state) => UnbanRequestScreen(
          initialEmail: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsPrivacyOnce,
        builder: (context, state) => const SettingsPrivacyOnceScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      // Verifizierungs-Flow
      GoRoute(
        path: AppRoutes.verificationVideo,
        builder: (context, state) => const VerificationVideoScreen(),
      ),
      GoRoute(
        path: AppRoutes.verificationComplete,
        builder: (context, state) => const VerificationSuccessScreen(),
      ),
      GoRoute(
        path: AppRoutes.verificationInfo,
        builder: (context, state) => const VerificationInfoScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.mfaSetup,
        builder: (context, state) => const MfaSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.mfaChallenge,
        builder: (context, state) => const MfaChallengeScreen(),
      ),
      GoRoute(
        path: AppRoutes.communityGuidelines,
        builder: (context, state) => const CommunityGuidelinesScreen(),
      ),
      // Geschuetzter Admin-Bereich (nur ueber verstecketen Zugang erreichbar,
      // Zugriff nur fuer AppConstants.adminUserId). Der redirect unten
      // blockt den Aufruf fuer alle anderen Nutzer.
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminScreen(),
      ),
      // Bug-Report (erreichbar von überall, kein Bottom-Nav)
      GoRoute(
        path: AppRoutes.bugReport,
        builder: (context, state) => const BugReportScreen(),
      ),
      // QR-Code (Profil teilen + Scannen)
      GoRoute(
        path: AppRoutes.qrProfile,
        builder: (context, state) => const QrProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.qrScan,
        builder: (context, state) => const QrScanScreen(),
      ),
      // Mood of the Day
      GoRoute(
        path: AppRoutes.moodPicker,
        builder: (context, state) => const MoodPickerScreen(),
      ),
      // "Neu in dieser Version" (App-Update-Popup für Registrierte).
      GoRoute(
        path: AppRoutes.whatsNew,
        builder: (context, state) => const WhatsNewScreen(),
      ),
      // Datenschutz & Account (DSGVO)
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      // Safety Center: Hilfe bei Belästigung/Stalking + In-App-Maßnahmen
      GoRoute(
        path: AppRoutes.safetyCenter,
        builder: (context, state) => const SafetyCenterScreen(),
      ),
      // Geräte & Sitzungen ("Wo bin ich eingeloggt?" + Überall-Abmelden)
      GoRoute(
        path: AppRoutes.devices,
        builder: (context, state) => const DevicesScreen(),
      ),
      // Dating Hour (Event-Modus) - Vollbild-Routen ohne Navigator-Stack:
      // Zurück-Geste führt jeweils zur Seite davor statt App-Exit.
      GoRoute(
        path: AppRoutes.datingHourRules,
        builder: (context, state) => const BackToRouteScope(
          route: AppRoutes.datingHourEvent,
          child: DatingHourRulesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.datingHourHowItWorks,
        builder: (context, state) => const BackToRouteScope(
          route: AppRoutes.datingHourEvent,
          child: DatingHourHowItWorksScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.datingHourEvent,
        builder: (context, state) => const BackToRouteScope(
          route: AppRoutes.swipeModeSelection,
          child: DatingHourEventScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.datingHourPreferences,
        builder: (context, state) => const BackToRouteScope(
          route: AppRoutes.datingHourEvent,
          child: DatingHourPreferencesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.datingHourChat,
        builder: (context, state) => BackToRouteScope(
          route: AppRoutes.datingHourEvent,
          child: DatingHourChatScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
      ),
      // Legacy-Pfade des alten "Matches"/"Likes"-Reiters: Weiterleitung
      // auf den neuen Interessen-Reiter.
      GoRoute(
        path: '/matches',
        redirect: (context, state) => AppRoutes.interessen,
      ),
      GoRoute(
        path: '/likes',
        redirect: (context, state) => AppRoutes.interessen,
      ),
      ShellRoute(
        builder: (context, state, child) => MainNavigation(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.findYourMatch,
            builder: (context, state) => const FindYourMatchScreen(),
          ),
          GoRoute(
            path: AppRoutes.interessen,
            builder: (context, state) => const InteressenScreen(),
          ),
          GoRoute(
            path: AppRoutes.quiz,
            builder: (context, state) => QuizScreen(
              matchId: int.parse(state.pathParameters['matchId']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.spiceQuestions,
            builder: (context, state) => SpiceQuestionsScreen(
              matchId: int.parse(state.pathParameters['matchId']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.personalityTest,
            builder: (context, state) => const PersonalityTestScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.profileEdit,
            builder: (context, state) => const ProfileEditScreen(),
          ),
          GoRoute(
            path: AppRoutes.chatDetail,
            builder: (context, state) =>
                ChatDetailScreen(matchId: state.pathParameters['matchId']!),
          ),
          GoRoute(
            path: AppRoutes.profileDetail,
            builder: (context, state) =>
                ProfileDetailScreen(userId: state.pathParameters['userId']!),
          ),
          GoRoute(
            path: AppRoutes.randomChat,
            builder: (context, state) => const RandomChatScreen(),
          ),
          GoRoute(
            path: AppRoutes.transitRadar,
            builder: (context, state) => const TransitRadarScreen(),
          ),
          // T: Entdeckungs-Modus-Auswahl MUSS Teil des Bottom-Navigation-Shells
          // sein (nicht eigenständiger Vollbild-Screen), damit die untere
          // Navigationsleiste sichtbar bleibt und der "Entdecken"-Tab korrekt
          // hervorgehoben wird. Kein Zurück-Pfeil - siehe swipe_mode_selection_screen.
          GoRoute(
            path: AppRoutes.swipeModeSelection,
            builder: (context, state) => const SwipeModeSelectionScreen(),
          ),
        ],
      ),
    ],
  );
}

/// Provider für den Router (abhängig von auth/settings via Ref).
final routerProvider = Provider<GoRouter>((ref) {
  return createRouter(ref);
});
