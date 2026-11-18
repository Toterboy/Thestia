import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/routing/route_restore.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/services/app_auth_service.dart';
import 'package:thestia/services/auth_service.dart';
import 'package:thestia/services/crash_journal.dart';
import 'package:thestia/services/device_session_service.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/prekey_service.dart';
import 'package:thestia/services/p2p_chat_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/services/secure_location_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_auth_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/transit_encounter_service.dart';
import 'package:thestia/services/verification_service.dart';
import 'package:thestia/services/webrtc_service.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/utils/demo_mode.dart';
import 'package:thestia/utils/temp_cleanup.dart';
import 'package:thestia/utils/best_effort.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'parts/authserversync.dart';

/// Verwaltet den Auth-Status. Unterstützt drei Modi:
/// 1. Demo-Modus (kein Backend)
/// 2. Supabase Auth (Supabase RLS-Datenbank)
/// 3. Eigenes API-Backend (Signaling-Server + SQLite)
class AuthNotifier extends StateNotifier<AsyncValue<bool>> {
  AuthNotifier(this._auth, this._profileNotifier, this._ref)
    : super(const AsyncValue.loading()) {
    _restore();
    _listenToSupabaseAuth();
  }

  final AppAuthService _auth;
  final ProfileNotifier _profileNotifier;
  final Ref _ref;

  StreamSubscription<AuthState>? _authStateSub;

  /// Nach dem allerersten _syncFromServer Aufruf true.
  /// Selbstheilung laeuft NUR danach – so werden lokale Restwerte
  /// (von einem frueheren Test/Install) nicht faelschlich zum Server
  /// gepusht und die Einrichtung bei der ersten Registrierung nicht
  /// uebersprungen.
  bool _initialServerSyncDone = false;

  /// Hält den Auth-Status synchron zu Supabase Auth.
  ///
  /// Verwirft Supabase die Session selbst (Refresh-Token invalide, Nutzer
  /// serverseitig gelöscht, Session aus einem anderen Projekt), bleibt der
  /// Status sonst auf "eingeloggt" kleben – der Nutzer landet dann ohne
  /// Session im E-Mail-Bestätigungs-Screen und hängt fest.
  void _listenToSupabaseAuth() {
    if (!SupabaseService.isInitialized) return;
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      final event = authState.event;
      if (event == AuthChangeEvent.signedOut) {
        state = const AsyncValue.data(false);
      } else if (event == AuthChangeEvent.passwordRecovery) {
        // Passwort-Reset (Recovery-Deep-Link aus der E-Mail, von
        // getSessionFromUrl via detectSessionInUriPredicate verarbeitet):
        // Der Router erzwingt jetzt den Reset-Screen, bis das neue
        // Passwort gesetzt ist (updateUser).
        _ref.read(passwordRecoveryPendingProvider.notifier).state = true;
        if (!state.hasValue || state.value != true) {
          state = const AsyncValue.data(true);
          unawaited(_syncFromServer());
        }
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        // Passkey-Login (oder andere stille Anmeldung) meldet sich hier
        // an, ohne dass login()/register() den State gesetzt hat.
        if (!state.hasValue || state.value != true) {
          state = const AsyncValue.data(true);
          unawaited(_syncFromServer());
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      // Globale Sicherheits-Wache: Falls restoreSession() (z. B. im
      // API-Backend-Modus bei nicht erreichbarem Server) HÄNGT und nie
      // zurückkehrt, würde der Router ewig auf dem Lade-Screen bleiben.
      // Nach dem Timeout wird sicher als "nicht eingeloggt" fortgefahren.
      final loggedIn = await _auth.restoreSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      state = AsyncValue.data(loggedIn);
      if (loggedIn) {
        // „Angemeldet bleiben"-Wunsch respektieren (Default: AN). Wenn der
        // Nutzer die Option im Login bewusst deaktiviert hat, wird die
        // Session beim Start still verworfen -> Login-Screen.
        final keepLoggedIn =
            await _ref.read(localStorageProvider).getBool('keep_logged_in') ??
            true;
        if (!keepLoggedIn) {
          await _auth.logout();
          state = const AsyncValue.data(false);
          return;
        }
        // Profil (Geburtsdatum/Alter!) und Setup-Flags vom Server nachladen.
        unawaited(_syncFromServer());
      }
    } catch (e, st) {
      // Fail-Safe gegen Deadlock beim Start: Bleibt der Zustand "loading",
      // würde der Router nie weiterleiten und die App hinge auf dem
      // Lade-Screen fest. Bei Fehler daher als "nicht eingeloggt"
      // fortfahren -> Nutzer landet auf Welcome/Login.
      debugPrint('[AuthNotifier] restoreSession fehlgeschlagen: $e');
      debugPrint('[AuthNotifier] StackTrace: $st');
      state = const AsyncValue.data(false);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      // PII (E-Mail, Name) nur im Debug-Modus loggen (Audit H4).
      debugPrint(
        '[AuthNotifier] register() aufgerufen: name=$name, '
        'email=$email, gender=$gender',
      );
    }
    state = const AsyncValue.loading();
    try {
      // Audit N-2: Der frühere GPS-Fix bei der Registrierung wurde entfernt
      // - die Werte wurden nie übertragen (tote Permission-Nutzung). Die
      // Fake-Account-Erkennung läuft serverseitig über den
      // process-location-check Flow bei Profil-Erstellung.

      final profile = await _auth.register(
        name: name,
        email: email,
        password: password,
        gender: gender,
        birthDate: birthDate,
        captchaToken: captchaToken,
      );
      if (kDebugMode) {
        debugPrint('[AuthNotifier] register() erfolgreich.');
      }
      // E-Mail für den Bestätigungs-Screen sichern. Bei aktivierter
      // E-Mail-Bestätigung liefert signUp KEINE Session (currentUser == null),
      // daher muss die Adresse aus dem Registrierungs-Formular kommen -
      // sonst schlägt "Bestätigungs-Mail erneut senden" fehl.
      _ref.read(pendingVerificationEmailProvider.notifier).state = email;
      // E-Mail + Passwort NUR IM SPEICHER für den stillen Auto-Login nach
      // der Bestätigung sichern (nie persistiert). Damit erkennt die App
      // die Bestätigung ohne Session und meldet den Nutzer automatisch an.
      _ref.read(pendingVerificationCredentialsProvider.notifier).state = (
        email: email,
        password: password,
        createdAt: DateTime.now(),
        name: name,
        gender: gender,
        birthDate: birthDate,
      );
      _profileNotifier.setProfile(profile);
      state = const AsyncValue.data(true);
      // Server-Sync auch NACH der Registrierung anstoßen: Er setzt
      // serverSyncDoneProvider und gibt damit den Router frei (sonst
      // bleibt die App auf dem Lade-Screen hängen). Zusätzlich wird das
      // FCM-Token registriert.
      unawaited(_syncFromServer());
    } catch (e, st) {
      debugPrint('[AuthNotifier] register() FEHLER: $e');
      debugPrint('[AuthNotifier] StackTrace: $st');
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Aufrufer durchreichen, damit die UI ihn anzeigen kann
    }
  }

  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      debugPrint('[AuthNotifier] login() aufgerufen: email=$email');
    }
    state = const AsyncValue.loading();
    try {
      await _auth.login(
        email: email,
        password: password,
        captchaToken: captchaToken,
      );
      debugPrint('[AuthNotifier] login erfolgreich');
      // Nach erfolgreichem Login sind die zwischengespeicherten
      // Registrierungs-Daten nicht mehr nötig.
      _ref.read(pendingVerificationEmailProvider.notifier).state = null;
      _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
      state = const AsyncValue.data(true);
      // Der E-Mail-Status wird sofort neu geprueft (statt auf den
      // 3-s-Poller zu warten) - das verhindert ein kurzes Aufblitzen
      // des Verifikations-Screens direkt nach dem Login.
      //
      // WICHTIG (06.11.2026): Hier darf NICHT
      // "invalidate(emailConfirmedProvider)" stehen. Der Erzeuger des
      // Providers hoert im Konstruktor auf den authProvider - eine
      // Invalidierung aus dem authProvider heraus ist ein Kreis, und
      // Riverpod wirft dann "CircularDependencyError". Live im Emulator
      // gesehen: die Anmeldung war erfolgreich, trotzdem blieb der
      // Login-Screen mit einer Fehlermeldung stehen.
      //
      // Der Notifier prueft selbst: sein Listener auf den authProvider
      // laeuft beim Anmelden ohnehin (siehe EmailConfirmedNotifier).
      unawaited(_syncFromServer());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] login() FEHLER: $e');
      }
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Aufrufer durchreichen
    }
  }

  /// Anmeldung per Passkey (WebAuthn) - Spiegel von [login], damit der
  /// Passkey-Pfad IDENTISCHE Nachläufe hat wie die Passwort-Anmeldung:
  /// Ladezustand (Ladekreis im Login-Screen), Aufräumen der Registrierungs-
  /// Zwischnspeicher und der Server-Sync (Profil, Präferenzen, Flags).
  /// Vorher lief der Passkey-Pfad nur über den Event-Listener ohne diese
  /// Schritte - Profildaten blieben nach der Anmeldung leer.
  Future<void> loginWithPasskey({String? captchaToken}) async {
    if (kDebugMode) {
      debugPrint('[AuthNotifier] loginWithPasskey() aufgerufen');
    }
    state = const AsyncValue.loading();
    try {
      await _auth.loginWithPasskey(captchaToken: captchaToken);
      _ref.read(pendingVerificationEmailProvider.notifier).state = null;
      _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
      state = const AsyncValue.data(true);
      // Wie im Passwort-Pfad: der E-Mail-Status wird sofort neu geprueft.
      // Das darf hier KEIN invalidate(emailConfirmedProvider) sein -
      // siehe die Begruendung im login()-Pfad (Riverpod-Zirkel).
      unawaited(_syncFromServer());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] loginWithPasskey() FEHLER: $e');
      }
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Login-Screen durchreichen
    }
  }

  Future<void> logout() async {
    // Server-Reste VOR dem Abmelden räumen (braucht die Session):
    // FCM-Token abmelden, damit Pushes des alten Kontos nicht auf
    // diesem Gerät landen, wenn sich danach ein anderes anmeldet.
    await bestEffort('SupabaseDatabaseService.updateOwnProfile', () async {
      if (SupabaseService.isInitialized &&
          SupabaseService.client.auth.currentUser != null) {
        await SupabaseDatabaseService(
          SupabaseService.client,
        ).updateOwnProfile({'fcm_token': null});
      }
    });
    // Eigenen Geräte-Eintrag entfernen (Best effort, VOR dem Abmelden -
    // danach gibt es keine gültige Session mehr für den Aufruf).
    await _ref.read(deviceSessionServiceProvider).deregisterCurrentDevice();
    await _auth.logout();
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    _ref.read(passwordRecoveryPendingProvider.notifier).state = false;
    _ref.read(serverSyncDoneProvider.notifier).state = false;
    _ref.read(setupFlagsKnownProvider.notifier).state = false;
    // MFA-Status zurücksetzen (keine Session -> keine Challenge/Setup).
    _ref.read(mfaStatusProvider.notifier).state = const MfaStatus.initial();
    // Lokale Nutzerdaten zurücksetzen (Audit: Kontowechsel auf demselben
    // Gerät). Ohne Reset sieht ein neu registrierter Account Badge und
    // Setup-Stand des Vorgängers ("verifiziert ohne Verifizierung",
    // keine Einrichtung). Der nächste Login lädt alles serverseitig
    // neu - lokale Reste sind danach überflüssig.
    await _ref.read(settingsProvider.notifier).resetToDefaults();
    await _ref.read(userPreferencesProvider.notifier).resetToDefaults();
    await _ref.read(profileProvider.notifier).resetToDefaults();
    await bestEffort('localStorageProvider.remove', () async {
      await _ref.read(localStorageProvider).remove(verificationSubmittedKey);
    });
    // Gleiches Geräte-Cleanup wie bei Löschung (keine fremden Reste für
    // den nächsten Account): Verlauf, Entwürfe, Crash-Journal,
    // Verifikations-Videos/Dateien, Temp-Dateien, Signal-Identität und
    // PreKey-Sessions (sonst würde der neue Account mit der Identität
    // des Vorgängers senden).
    await bestEffort('chatServiceProvider.clearLocalHistory', () async {
      await _ref.read(chatServiceProvider).clearLocalHistory();
    });
    await bestEffort('reportServiceProvider.clearDrafts', () async {
      await _ref.read(reportServiceProvider).clearDrafts();
    });
    await bestEffort('CrashJournal.clear', () async {
      await CrashJournal.clear();
    });
    await bestEffort(
      'verificationServiceProvider.deleteAllLocalData',
      () async {
        await _ref.read(verificationServiceProvider).deleteAllLocalData();
      },
    );
    unawaited(cleanupDecryptedTempFiles());
    await bestEffort('encryptionServiceProvider.clearAllData', () async {
      await _ref.read(encryptionServiceProvider).clearAllData();
    });
    // DER DIENST NEU BAUEN (BEFUND 18.11.2026, gefunden von einem Test):
    // Nach dem Leeren hat der Dienst keinen Identity-Key mehr (null) -
    // jeder Zugriff darauf waere ein Absturz ("Null check operator used
    // on a null value"). Die App liefe also nach dem Abmelden mit einem
    // kaputten Dienst weiter (bis zum naechsten App-Neustart).
    //
    // DER WEG: Der Provider wird verworfen - der naechste Zugriff baut
    // ihn neu auf (mit einem neuen Schluessel, wie nach einem Neustart).
    _ref.invalidate(encryptionServiceProvider);
    bestEffortSync('preKeyServiceProvider.reset', () {
      _ref.read(preKeyServiceProvider).reset();
    });
    // P2P-Outbox verwerfen + WebRTC-Verbindung schließen (keine
    // Vorgänger-Chiffre unter neuem Konto, kein offener Kanal).
    bestEffortSync('p2pChatServiceProvider.clearOutbox', () {
      _ref.read(p2pChatServiceProvider).clearOutbox();
    });
    await bestEffort('webRTCServiceProvider.close', () async {
      await _ref.read(webRTCServiceProvider).close();
    });
    await bestEffort('read.setOwner', () async {
      await _ref.read(chatProvider.notifier).setOwner(null);
    });
    // Gesicherte Route verwerfen (v0.9.1): Nach Logout kein Restore in
    // fremde/nicht mehr gültige Screens.
    await bestEffort('localStorageProvider.remove', () async {
      await _ref.read(localStorageProvider).remove(lastRoutePrefsKey);
    });
    setPendingRouteRestore(null);
    state = const AsyncValue.data(false);
  }

  /// Stiller Login für den Auto-Login nach der E-Mail-Bestätigung.
  ///
  /// Führt den Login durch, OHNE den öffentlichen Auth-Status auf
  /// loading/error zu setzen. Wichtiger Unterschied zu [login]: Ein
  /// fehlgeschlagener Versuch (E-Mail noch nicht bestätigt) würde sonst
  /// den Status auf AsyncError setzen, der Router würde den Nutzer als
  /// "ausgeloggt" behandeln und ihn vom Bestätigungs-Screen zum
  /// Login-Screen werfen. Nur bei ERFOLG wird der Status aktualisiert.
  Future<void> silentLogin({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    await _auth.login(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    state = const AsyncValue.data(true);
    // KRITISCH (Setup fehlte nach Bestätigung): Wie login()/register()
    // muss auch hier der Server-Sync laufen - sonst bleiben Profil,
    // Setup-Flags und FCM-Token leer, der Router kennt den Stand nicht
    // (flagsKnown false + keine Pending-Creds mehr = keine Einrichtung)
    // und die App hängt auf dem Lade-Screen bzw. landet auf Home.
    unawaited(_syncFromServer());
  }

  /// Löscht den Account serverseitig UND lokal vollständig.
  ///
  /// Audit M-12: Ein Server-Fehler wird NICHT mehr verschluckt - der
  /// lokale Reset erfolgt nur nach ERFOLGREICHER Löschung, damit der
  /// Nutzer nie glaubt, gelöscht zu sein, während die Daten weiter
  /// existieren. Der Fehler wird an den Aufrufer (UI) durchgereicht.
  ///
  /// Audit H-8: Nach erfolgreicher Löschung werden zusätzlich ALLE lokalen
  /// Reste entfernt: Signal-Keys/Sessions/Peer-Trust ([EncryptionService.
  /// clearAllData]) + PreKey-Session-Cache ([PreKeyService.reset]),
  /// GPS-Verifizierungsstandort ([SecureLocationStorage]),
  /// Verifikations-Videos + Dateien ([VerificationService]),
  /// Chat-Verlauf ([ChatService.clearLocalHistory]) + konto-namespaced
  /// Chat-Boxen ([ChatService.deleteOwnedData]), Melde-Entwürfe
  /// ([ReportService.clearDrafts]), Crash-Journal ([CrashJournal.clear]),
  /// entschlüsselte Voice-Note-Temp-Dateien und das FCM-Geräte-Token
  /// (Audit N-20).
  Future<void> deleteAccount() async {
    // User-ID VOR der Löschung sichern (danach keine Session mehr).
    final doomedId = SupabaseService.isInitialized
        ? SupabaseService.client.auth.currentUser?.id
        : null;
    // 1) Serverseitige Löschung FIRST - schlägt sie fehl, bleibt alles
    //    wie es ist und der Nutzer sieht den Fehler.
    await _auth.deleteAccount();

    // 2) Lokale Daten vollständig löschen (DSGVO Art. 17).
    // Best-effort: Token kann bereits ungültig sein.
    await bestEffort('deleteToken', () async {
      if (!AppConstants.fdroidBuild) {
        await FirebaseMessaging.instance.deleteToken();
      }
    });
    try {
      await _ref.read(encryptionServiceProvider).clearAllData();
    } catch (e) {
      debugPrint('[AuthNotifier] Encryption-Cleanup fehlgeschlagen: $e');
    }
    // DER DIENST NEU BAUEN: Nach dem Leeren hat er keinen Identity-Key
    // mehr (siehe die Erklaerung beim Abmelden).
    _ref.invalidate(encryptionServiceProvider);
    try {
      _ref.read(preKeyServiceProvider).reset();
    } catch (e) {
      debugPrint('[AuthNotifier] PreKey-Cleanup fehlgeschlagen: $e');
    }
    // P2P-Outbox + WebRTC wie beim Logout (Re-Registrierung im selben
    // Prozess darf keine Vorgänger-Chiffre/Kanäle erben).
    try {
      _ref.read(p2pChatServiceProvider).clearOutbox();
    } catch (e) {
      debugPrint('[AuthNotifier] P2P-Cleanup fehlgeschlagen: $e');
    }
    try {
      await _ref.read(webRTCServiceProvider).close();
    } catch (e) {
      debugPrint('[AuthNotifier] WebRTC-Cleanup fehlgeschlagen: $e');
    }
    // SECURITY (Audit 2026-09-26): Transit-Encounter-Cache (Begehnachweise
    // fremder Geraete per BLE) war bis hierher NICHT in der Loeschkette - die
    // Daten ueberlebten die Kontoloeschung im lokalen Speicher.
    try {
      await TransitEncounterService(SecurePreferencesStorage()).clear();
    } catch (e) {
      debugPrint('[AuthNotifier] Transit-Encounter-Cleanup fehlgeschlagen: $e');
    }
    try {
      await SecureLocationStorage.instance.clear();
    } catch (e) {
      debugPrint('[AuthNotifier] Standort-Cleanup fehlgeschlagen: $e');
    }
    try {
      await _ref.read(verificationServiceProvider).deleteAllLocalData();
    } catch (e) {
      debugPrint('[AuthNotifier] Video-Cleanup fehlgeschlagen: $e');
    }
    // DSGVO-Vollständigkeit: lokaler Chat-Verlauf (Opt-in-Box),
    // Melde-Entwürfe und Crash-Journal enthalten Nutzerdaten und
    // werden mitgelöscht (best-effort, blockiert nie). Zusätzlich die
    // konto-namespaced Chat-Boxen vom Gerät entfernen.
    try {
      await _ref.read(chatServiceProvider).clearLocalHistory();
    } catch (e) {
      debugPrint('[AuthNotifier] Verlauf-Cleanup fehlgeschlagen: $e');
    }
    if (doomedId != null) {
      try {
        await _ref.read(chatProvider.notifier).deleteOwnedData(doomedId);
      } catch (e) {
        debugPrint('[AuthNotifier] ChatBox-Cleanup fehlgeschlagen: $e');
      }
    }
    try {
      await _ref.read(reportServiceProvider).clearDrafts();
    } catch (e) {
      debugPrint('[AuthNotifier] Draft-Cleanup fehlgeschlagen: $e');
    }
    try {
      await CrashJournal.clear();
    } catch (e) {
      debugPrint('[AuthNotifier] Journal-Cleanup fehlgeschlagen: $e');
    }
    unawaited(cleanupDecryptedTempFiles());

    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    _ref.read(mfaStatusProvider.notifier).state = const MfaStatus.initial();
    await _ref.read(settingsProvider.notifier).resetToDefaults();
    await _ref.read(userPreferencesProvider.notifier).resetToDefaults();
    await _ref.read(profileProvider.notifier).resetToDefaults();
    state = const AsyncValue.data(false);
  }

  /// Setzt den Auth-Status - aufrufbar auch aus der Erweiterung.
  ///
  /// DER GRUND: In einer Erweiterung darf `state` nicht gesetzt
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern des
  /// Notifiers). Diese Methode gehoert zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeWert(AsyncValue<bool> wert) => state = wert;
}

/// Prüft, ob der Demo-Modus (lokaler Mock) aktiv ist.
///
/// Entscheidung delegiert an die reine, testbare Funktion
/// [resolveDemoMode] (lib/utils/demo_mode.dart). Ohne Legacy-ApiConfig
/// gibt es keine Backend-URL mehr -> leerer String aktiviert die
/// URL-Heuristik nicht; ohne Supabase und ohne Flag bleibt der Modus
/// aus (fail-closed).
bool _isDemoMode() => resolveDemoMode(
  isReleaseMode: kReleaseMode,
  isSupabaseInitialized: SupabaseService.isInitialized,
  demoModeFlag: AppConstants.demoMode,
  baseUrl: '',
);

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<bool>>((
  ref,
) {
  final tokens = ref.watch(secureTokenStoreProvider);
  final encryption = ref.watch(encryptionServiceProvider);
  final storage = ref.watch(localStorageProvider);

  final AppAuthService auth;

  if (SupabaseService.isInitialized) {
    final database = SupabaseDatabaseService(SupabaseService.client);
    auth = SupabaseAuthService(
      SupabaseService.client,
      tokens,
      encryption,
      database,
    );
  } else if (_isDemoMode()) {
    final prefs = storage is SharedPreferencesStorage ? storage.raw : null;
    // Legacy-Aufräum: alte (ungesalzene) Credential-Hashes aus
    // SharedPreferences entfernen (Audit H6/M10).
    unawaited(
      prefs?.remove(AppConstants.prefsCredentialsKey) ?? Future.value(),
    );
    // Demo-Credentials (gesalzener Hash) liegen im Keystore/Keychain,
    // NICHT in SharedPreferences (Audit M10/H6).
    final secureStore = ref.watch(secureTokenStoreProvider);
    auth = AuthService(
      () async => prefs?.getString(AppConstants.prefsAuthKey),
      (String v) async => await prefs?.setString(AppConstants.prefsAuthKey, v),
      secureStore.readDemoCredentials,
      secureStore.writeDemoCredentials,
    );
  } else {
    // Weder Supabase noch Demo-Modus: Es gibt bewusst KEIN Legacy-Backend
    // mehr (der fruehere ApiClient mit Platzhalter-URL ist entfernt).
    // Fail-closed mit klarer Meldung statt garantiert fehlschlagender
    // Netzwerk-Calls.
    throw StateError(
      'Kein Auth-Backend verf\u00fcgbar: Supabase nicht initialisiert '
      'und Demo-Modus deaktiviert. Pr\u00fcfe .env / DEMO_MODE Build-Flag.',
    );
  }

  return AuthNotifier(auth, ref.watch(profileProvider.notifier), ref);
});

/// E-Mail-Adresse aus der Registrierung für den Bestätigungs-Screen.
///
/// Nach signUp mit aktivierter E-Mail-Bestätigung existiert KEINE Session
/// (currentUser == null). Der Bestätigungs-Screen braucht die Adresse aber
/// für "Erneut senden" - daher wird sie hier zwischengespeichert.
final pendingVerificationEmailProvider = StateProvider<String?>((ref) => null);

/// E-Mail + Passwort der letzten Registrierung - NUR IM SPEICHER, nie
/// persistiert.
///
/// Der Bestätigungs-Screen versucht damit im Hintergrund einen stillen
/// Login. Solange die E-Mail unbestätigt ist, schlägt er fehl; nach der
/// Bestätigung baut er automatisch die Session auf und die App geht weiter.
/// Wird bei erfolgreichem Login/Logout geleert; App-Neustart löscht den
/// Wert ebenfalls (Speicher-only). ABLAUF (Audit M1): [createdAt] begrenzt
/// die Lebensdauer auf 15 Minuten – danach verweigert der Auto-Login das
/// Passwort weiterzureichen (das Passwort bleibt nie unbegrenzt im Speicher).
final pendingVerificationCredentialsProvider =
    StateProvider<
      ({
        String email,
        String password,
        DateTime createdAt,
        // NUTZERWUNSCH (01.11.2026): "Falls man einen Fehler bemerkt,
        // soll man an dieser Stelle die E-Mail-Adresse nochmal ändern."
        //
        // Das Ändern der Adresse heißt: das unbestätigte Konto löschen
        // und mit der neuen Adresse neu registrieren. Dafür braucht es
        // die Angaben aus dem Registrierungsformular - ohne sie
        // entstünde ein Profil ohne Name und ohne Geburtsdatum.
        //
        // Alles NUR IM SPEICHER, nie persistiert.
        String name,
        String? gender,
        DateTime birthDate,
      })?
    >((ref) => null);

/// Zeigt an, ob ein Passwort-Reset (Recovery-Deep-Link) aussteht. Solange
/// true ist, erzwingt der Router den Reset-Screen; nach erfolgreichem
/// `updateUser` wird der Wert geleert.
final passwordRecoveryPendingProvider = StateProvider<bool>((ref) => false);

/// Zeigt an, ob der Server-Sync nach Login/Session-Restore abgeschlossen
/// ist (Profil + Setup-Flags). Der Router wartet darauf, damit nach einer
/// App-Neuinstallation die Einrichtung NICHT kurz aufblitzt, bevor die
/// serverseitigen Setup-Flags geladen sind.
final serverSyncDoneProvider = StateProvider<bool>((ref) => false);

/// True, sobald der Server-Stand der Setup-Flags ERFOLGREICH geladen wurde.
///
/// "Niemals-Einrichtung"-Garantie: Ist der Stand NICHT bekannt (Sync
/// insgesamt fehlgeschlagen), erzwingt der Router die Einrichtung nicht -
/// sonst würde sie nach einer Neuinstallation bei reinen Netzproblemen
/// erneut erscheinen. Eine frische REGISTRIERUNG (pendingVerification)
/// ist von dieser Ausnahme ausgenommen: Dort ist die Einrichtung gewollt.
final setupFlagsKnownProvider = StateProvider<bool>((ref) => false);

/// Prüft, ob die E-Mail des aktuellen Supabase-Nutzers bestaetigt ist.
///
/// Pollt den Auth-Status alle 3 Sekunden, damit der Nutzer nach Klick auf
/// den Bestätigungslink in der E-Mail automatisch weiterkommt, ohne die
/// App neu starten zu müssen. Das Polling wird im Hintergrund pausiert,
/// um Akku und Daten zu schonen.
///
/// Liefert:
/// - `true`, wenn E-Mail bestaetigt ist
/// - `false`, wenn E-Mail noch nicht bestaetigt ist
/// - `null`, wenn kein Supabase-Modus aktiv ist oder keine Session existiert
class EmailConfirmedNotifier extends StateNotifier<bool?>
    with WidgetsBindingObserver {
  EmailConfirmedNotifier(this._ref) : super(null) {
    WidgetsBinding.instance.addObserver(this);

    // BEFUND (01.11.2026): Der Poller wurde beim ersten "nicht
    // angemeldet" endgueltig gestoppt - und die Registrierung laeuft
    // OHNE Session (bei aktivierter E-Mail-Bestaetigung liefert
    // signUp keine). Damit blieb der Wert dauerhaft null, der
    // Bildschirm bekam die Bestaetigung nie gemeldet, und der
    // einzige Weg weiter war der stille Auto-Login.
    //
    // Ausserdem blieb ein "true" aus einem VORHERIGEN Konto stehen:
    // der Wert wurde beim Abmelden nie zurueckgesetzt. Danach
    // umging das Router-Gate die E-Mail-Bestaetigung vollstaendig -
    // der Nutzer kam direkt zum Willkommens-Screen.
    //
    // Der Anmeldestatus ist deshalb jetzt die Quelle: bei der
    // Anmeldung laeuft der Poller wieder an, beim Abmelden wird der
    // Wert zurueckgesetzt.
    _ref.listen(authProvider, (prev, next) {
      final angemeldet = next.valueOrNull ?? false;
      if (angemeldet) {
        if (_timer == null) {
          _startPolling();
        } else {
          // Der Poller laeuft schon: trotzdem sofort pruefen. Vorher
          // wurde das ueber "invalidate(emailConfirmedProvider)" vom
          // authProvider aus erledigt - das war der Kreis (siehe
          // auth_provider.dart, login()).
          unawaited(_check());
        }
      } else {
        if (state != null) state = null;
        _stopPolling();
      }
    });

    _startPolling();
  }

  final Ref _ref;
  Timer? _timer;

  void _startPolling() {
    _timer?.cancel();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Polling im Hintergrund pausieren, um Akku zu schonen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _startPolling();
    }
  }

  Future<void> _check() async {
    try {
      if (!SupabaseService.isInitialized) {
        if (state != null) state = null;
        _stopPolling();
        return;
      }

      // WICHTIG: valueOrNull statt value verwenden – bei einem AsyncError
      // (z. B. fehlgeschlagener Auto-Login) würde .value die gespeicherte
      // Exception erneut werfen (Unhandled Exception im Polling-Timer).
      final auth = _ref.read(authProvider);
      final loggedIn = auth.valueOrNull ?? false;
      if (!loggedIn) {
        if (state != null) state = null;
        // Ohne eingeloggten Nutzer gibt es nichts zu bestaetigen. Vorher lief
        // der 3-s-Timer trotzdem die gesamte App-Lebenszeit weiter (20
        // Aufrufe/Minute, auch im Welcome-/Login-Screen) - das war einer der
        // groessten Dauer-Verbraucher im Vordergrund.
        _stopPolling();
        return;
      }

      final session = SupabaseService.client.auth.currentSession;
      final user = session?.user;
      final confirmed = user?.emailConfirmedAt != null;
      if (state != confirmed) {
        log('[EmailConfirmedNotifier] emailConfirmed=$confirmed');
        state = confirmed;
      }
      // Batterie/Netz schonen: Nach Bestätigung ist Polling unnötig.
      if (confirmed) {
        _stopPolling();
      }
    } catch (e) {
      log('[EmailConfirmedNotifier] Polling error: $e');
      // Bei Fehler aktuellen Zustand behalten, um Flackern zu vermeiden.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }
}

final emailConfirmedProvider =
    StateNotifierProvider<EmailConfirmedNotifier, bool?>((ref) {
      return EmailConfirmedNotifier(ref);
    });
