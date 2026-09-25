import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/app_auth_service.dart';
import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/passkey_auth.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Echte Authentifizierung über Supabase Auth (ersetzt den Mock [AuthService]).
///
/// Speichert Tokens zusätzlich im [SecureTokenStore] (Kompatibilität zum
/// bestehenden System), primär nutzt Supabase Auth aber seine eigene
/// persistente Session.
class SupabaseAuthService implements AppAuthService {
  SupabaseAuthService(this._supabase, this._tokens, this._encryption, this._database);

  final SupabaseClient _supabase;
  final SecureTokenStore _tokens;
  final EncryptionService _encryption;
  final SupabaseDatabaseService _database;

  /// True, wenn eine gültige Supabase-Session existiert und die E-Mail
  /// des Nutzers bestätigt ist.
  ///
  /// STARTUP-PERFORMANCE: Der Check ist bewusst SYNCHRON (nur lokale
  /// Session-Daten) und blockiert den App-Start nicht durch einen
  /// Netzwerk-Roundtrip. Die serverseitige Validierung läuft im Hintergrund
  /// ([_validateSession]): Existiert der Nutzer nicht mehr (Datenbank-Reset,
  /// Dashboard-Löschung, Session aus anderem Projekt), wird die Session
  /// verworfen; der damit ausgelöste `signedOut`-Event setzt den
  /// Auth-Status über [AuthNotifier] auf "ausgeloggt" - der Router schickt
  /// den Nutzer dann auf Login statt in den E-Mail-Bestätigungs-Screen.
  /// Netzwerkfehler behalten die Session (offline-tolerant).
  @override
  Future<bool> restoreSession() async {
    var session = _supabase.auth.currentSession;
    if (session == null) return false;
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    if (user.emailConfirmedAt == null) return false;

    // Auto-Logout-Härtung ("nach ein paar Stunden abgemeldet"): Der
    // Access-Token läuft nach ~1 h ab. War die App länger im Hintergrund,
    // ist der Token beim Start abgelaufen - schlägt dann der EINZIGE
    // Refresh-Versuch (z. B. kurzzeitig kein Netz), fliegt die Session.
    // Deshalb: Explizites Auffrischen mit bis zu 3 Versuchen, BEVOR wir
    // "angemeldet" melden. Schlägt es dauerhaft fehl (Token widerrufen),
    // ist die Abmeldung korrekt.
    final expiresAt = session.expiresAt ?? 0;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt - nowSec < 120) {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
        try {
          final refreshed = await _supabase.auth
              .refreshSession()
              .timeout(const Duration(seconds: 10));
          if (refreshed.session != null) {
            session = refreshed.session;
            lastError = null;
            break;
          }
        } catch (e) {
          lastError = e;
        }
      }
      if (lastError != null || session == null) {
        debugPrint('[AuthService] Session-Refresh nach Stunden '
            'fehlgeschlagen (Abmeldung): $lastError');
        return false;
      }
    }

    // Serverseitige Validierung NICHT abwarten (Startzeit!).
    unawaited(_validateSession());
    // Safety-Numbers (Signal-Fingerprint) ben�tigen die eigene User-ID.
    _encryption.localUserId = user.id;
    return true;
  }

  /// Prüft die lokale Session im Hintergrund gegen die Auth-API.
  Future<void> _validateSession() async {
    try {
      final userResponse = await _supabase.auth
          .getUser()
          .timeout(const Duration(seconds: 5));
      final serverUser = userResponse.user;
      if (serverUser == null || serverUser.emailConfirmedAt == null) {
        // E-Mail (noch) nicht bestätigt bzw. User weg: Session verwerfen.
        await _clearLocalSession();
      }
    } on TimeoutException {
      // Langsames Netz – lokale Session nicht verwerfen.
    } on AuthRetryableFetchException {
      // Netzwerk-/Serverfehler – lokale Session nicht verwerfen.
    } on AuthException catch (e) {
      // Nutzer existiert serverseitig nicht mehr oder Session ist
      // invalidiert: lokale Session und Tokens verwerfen, damit der
      // Nutzer sauber auf Login/Registrierung landet.
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] Session serverseitig ungültig: $e');
      }
      await _clearLocalSession();
    } catch (e) {
      // Unbekannter Fehler – Session behalten (offline-tolerant).
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] getUser()-Validierung fehlgeschlagen: $e');
      }
    }
  }

  /// Verwirft die lokale Session samt gespeicherter Tokens.
  ///
  /// [GoTrueClient.signOut] ist ohne Angabe rein lokal (scope: local) –
  /// es wird kein Netzwerk-Call unternommen, der hängen bleiben könnte.
  Future<void> _clearLocalSession() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort
    }
    await _tokens.clear();
  }

  /// Prüft, ob der eingeloggte Nutzer seine E-Mail bestätigt hat.
  bool isEmailConfirmed() {
    final user = _supabase.auth.currentUser;
    return user != null && user.emailConfirmedAt != null;
  }

  /// Registriert einen neuen Nutzer in Supabase Auth + Datenbank und loggt ihn ein.
  ///
  /// [captchaToken]: CAPTCHA-Token (hCaptcha/Turnstile) für den Bot-Schutz.
  /// Supabase validiert es serverseitig, wenn im Dashboard CAPTCHA aktiviert
  /// ist; ohne Dashboard-Aktivierung wird das Token ignoriert.
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
    await _encryption.initialized;

    // Audit H-5 (Betreiber-Entscheidung): Das Invite-Code-System wurde in
    // Migration 057 vollständig entfernt - Registrierung ist offen
    // (geschützt durch CAPTCHA im Dashboard + serverseitige Rate-Limits).

    // 0) Plattform-Sperre (Migration 045): Gesperrte E-Mail-Adressen
    //    dürfen sich nicht (neu) registrieren. Der serverseitige
    //    handle_new_user-Trigger erzwingt das zusätzlich (RAISE 'email_banned').
    //    Hier geht es um die UX: Der Nutzer bekommt sofort den
    //    Entsperrungs-Flow angeboten statt eines generischen Fehlers.
    final banStatus = await _database.checkEmailBanStatus(email);
    if (banStatus.banned) {
      throw EmailBannedException(email: email.trim(), reason: banStatus.reason);
    }

    final birth = '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';

    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] registriere: gender=$gender');
    }

    // 1) Auth-User anlegen.
    // raw_user_meta_data enthält ALLE bei der Registrierung erfassten
    // Nutzerdaten – der serverseitige handle_new_user-Trigger liest diese
    // Felder aus und legt das Profil mit SECURITY DEFINER an. Dadurch ist
    // kein clientseitiger INSERT nötig.
    //
    // WICHTIG: Das Passwort darf NIEMALS in raw_user_meta_data landen!
    // Nur unkritische Profilfelder: name, gender, birth_date.
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] signUp() wird aufgerufen: email=$email');
      debugPrint('[SupabaseAuthService] Supabase-URL: ${_supabase.rest.url}');
    }

    final User user;
    final AuthResponse authResponse;
    try {
      authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        captchaToken: captchaToken,
        data: {
          'name': name,
          'gender': gender ?? 'unknown',
          'birth_date': birth,
        },
      );
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] signUp() abgeschlossen.');
      }

      user = authResponse.user ?? (throw AppException('Registrierung fehlgeschlagen. Bitte versuche es erneut.'));
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] AuthException: ${e.message} (Code: ${e.statusCode})');
      }
      // Serverseitige Sperre (handle_new_user-Trigger, Migration 045):
      // auch dann den Entsperrungs-Flow anbieten, wenn der Vorab-Check
      // nicht griff (z. B. altes App-Build).
      if (e.message.toLowerCase().contains('email_banned')) {
        throw EmailBannedException(email: email.trim());
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] UNERWARTETER Fehler bei signUp(): $e');
        debugPrint('[SupabaseAuthService] StackTrace: $st');
      }
      rethrow;
    }

    // Duplikat-Schutz: Supabase meldet bei bereits existierender E-Mail
    // (bestätigungspflichtiger Anmeldeflow) KEINEN Fehler, sondern liefert
    // zum Schutz vor E-Mail-Enumeration den BESTEHENDEN Nutzer ohne Session
    // zurück - es geht keine Bestätigungs-Mail raus. Der Nutzer würde sonst
    // endlos am "E-Mail bestätigen"-Screen warten. Erkannt wird der Fall an:
    // - vorhandenem emailConfirmedAt (Account ist bereits bestätigt), oder
    // - einem created_at, das älter als 30 Minuten ist (verwaiste, nie
    //   bestätigte Registrierung; ein frisch angelegter Account ist
    //   Sekunden alt).
    if (authResponse.session == null) {
      final alreadyConfirmed =
          (user.emailConfirmedAt ?? '').trim().isNotEmpty;
      final createdAt = DateTime.tryParse(user.createdAt);
      final staleSignup = createdAt != null &&
          DateTime.now().toUtc().difference(createdAt) >
              const Duration(minutes: 30);
      if (alreadyConfirmed || staleSignup) {
        if (kDebugMode) {
          debugPrint('[SupabaseAuthService] Registrierung blockiert: '
              'E-Mail bereits registriert (confirmed=$alreadyConfirmed, '
              'stale=$staleSignup).');
        }
        throw AppException('EMAIL_ALREADY_REGISTERED');
      }
    }

    // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
    _encryption.localUserId = user.id;

    // 4) Profil-Erstellung:
    //    Der serverseitige handle_new_user-Trigger (SECURITY DEFINER) hat
    //    das Profil bereits in public.profiles angelegt. Kein clientseitiger
    //    INSERT nötig – wir konstruieren das UserProfile aus den lokal
    //    vorhandenen Daten. Der Trigger garantiert, dass das Profil in der
    //    DB existiert, sobald der Nutzer nach E-Mail-Bestätigung vollständig
    //    authentifiziert ist.
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] Registration erfolgreich: userId=${user.id}');
      debugPrint('[SupabaseAuthService] Profil wurde via handle_new_user-Trigger angelegt.');
      debugPrint('[SupabaseAuthService] Bestätigungs-E-Mail wurde versendet.');
    }

    // Token zusätzlich für Kompatibilität mit dem bestehenden SecureTokenStore sichern.
    final session = authResponse.session;
    if (session != null) {
      await _tokens.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        userId: user.id,
      );
    }

    // UserProfile aus den lokalen Registrierungsdaten konstruieren.
    // Nach E-Mail-Bestätigung wird das vollständige Profil via
    // fetchOwnProfile() aus der DB gelesen – dann inklusive aller
    // serverseitig gesetzten Felder.
    return UserProfile(
      id: user.id,
      name: name,
      bio: '',
      interests: const [],
      photos: const [],
      city: '',
      gender: gender,
      genderPreference: 'all',
      birthDate: birthDate,
    );
  }

  // ---------------------------------------------------------------------
  // Login-Lockout (Spam-/Bruteforce-Schutz, Betreiber-Anforderung):
  // Nach 10 fehlgeschlagenen Anmeldeversuchen wird die Anmeldung für
  // 10 Minuten blockiert. Persistiert in SharedPreferences (überlebt
  // App-Neustart; bewusst KEIN SecureStore - enthält kein Secret).
  // Serverseitig zusätzlich durch Supabase-Auth-Rate-Limits abgesichert.
  // ---------------------------------------------------------------------
  static const int _maxLoginAttempts = 10;
  static const Duration _loginLockDuration = Duration(minutes: 10);
  static const String _prefsFailedLogins = 'auth_failed_login_count';
  static const String _prefsLockedUntil = 'auth_login_locked_until';

  Future<int> _remainingLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedUntil = prefs.getInt(_prefsLockedUntil) ?? 0;
    final remainingMs = lockedUntil - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 60000).ceil();
  }

  /// Loggt einen Nutzer per E-Mail + Passwort in Supabase Auth ein.
  ///
  /// [captchaToken]: CAPTCHA-Token (hCaptcha/Turnstile) für den Bot-Schutz –
  /// Supabase validiert es serverseitig, wenn im Dashboard CAPTCHA
  /// aktiviert ist.
  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] login aufgerufen');
    }

    // Lockout prüfen (vor allen Server-Roundtrips: In der Sperre wird
    // bewusst gar nichts angefragt - auch keine Ban-Status-Abfrage).
    final lockedMinutes = await _remainingLockMinutes();
    if (lockedMinutes > 0) {
      throw AppException(
        'Zu viele fehlgeschlagene Anmeldeversuche. Bitte warte '
        '$lockedMinutes Minute(n) und versuche es erneut.',
        messageKey: 'auth.lockedOut',
        params: {'minutes': '$lockedMinutes'},
      );
    }

    // Plattform-Sperre (Migration 045): Auch der Login mit einer
    // gesperrten E-Mail-Adresse wird blockiert - der Nutzer soll nur
    // den Entsperrungs-Flow sehen.
    final banStatus = await _database.checkEmailBanStatus(email);
    if (banStatus.banned) {
      throw EmailBannedException(email: email.trim(), reason: banStatus.reason);
    }

    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
        captchaToken: captchaToken,
      );

      final session = authResponse.session;
      if (session != null) {
        await _tokens.saveTokens(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken ?? '',
          userId: authResponse.user!.id,
        );
      }
      // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
      _encryption.localUserId = authResponse.user!.id;

      // Erfolg: Fehlversuchs-Zähler zurücksetzen.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsFailedLogins);

      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] login erfolgreich.');
      }
    } on AuthException catch (e) {
      // Nur echte "falsche Zugangsdaten" zählen (GoTrue antwortet mit
      // HTTP 400; statusCode ist bei supabase-dart ein String).
      // Netzwerk-/Server-/Captcha-Fehler erhöhen den Zähler NICHT.
      final wrongCredentials = e.statusCode == '400';
      if (!wrongCredentials) rethrow;
      final prefs = await SharedPreferences.getInstance();
      final attempts = (prefs.getInt(_prefsFailedLogins) ?? 0) + 1;
      if (attempts >= _maxLoginAttempts) {
        await prefs.setInt(
          _prefsLockedUntil,
          DateTime.now().millisecondsSinceEpoch +
              _loginLockDuration.inMilliseconds,
        );
        await prefs.setInt(_prefsFailedLogins, 0);
        throw AppException(
          'Zu viele fehlgeschlagene Anmeldeversuche. Die Anmeldung ist für '
          '10 Minuten gesperrt.',
          messageKey: 'auth.lockedOut10',
          params: const {'minutes': '10'},
        );
      }
      await prefs.setInt(_prefsFailedLogins, attempts);
      rethrow;
    }
  }

  /// Loggt einen Nutzer per Passkey (WebAuthn) ein.
  ///
  /// Führt bewusst DIESELBEN Nachlauf-Effekte aus wie [login]: Token-
  /// Persistenz im [SecureTokenStore] und Setzen der Signal-User-ID. Der
  /// frühere Passkey-Pfad lief NUR über den GoTrue-Event-Listener - es
  /// fehlten diese Effekte, und der Profil-/Daten-Sync nach der Anmeldung
  /// lief nicht zuverlässig (Name & Co. blieben leer).
  ///
  /// [captchaToken]: Der Server verlangt es für den Passkey-Flow ebenfalls,
  /// wenn im Dashboard CAPTCHA aktiviert ist.
  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] loginWithPasskey aufgerufen');
    }

    // Zeremonie (Options holen -> Fingerprint/Gesicht -> Verify) inkl.
    // Concurrent-Guard über PasskeyAuth.
    await PasskeyAuth.signIn(captchaToken: captchaToken);

    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      throw AppException(
          'Passkey-Anmeldung fehlgeschlagen. Bitte erneut versuchen.');
    }

    await _tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
      userId: user.id,
    );
    // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
    _encryption.localUserId = user.id;

    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] loginWithPasskey erfolgreich.');
    }
  }

  /// Schickt eine E-Mail zur Bestätigung der Adresse (z.B. nach Login bei unbestätigtem Account).
  Future<void> sendEmailConfirmation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw AppException('Nicht eingeloggt.');
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: user.email ?? '',
    );
  }

  /// Loggt den Nutzer aus Supabase Auth aus und löscht lokale Tokens.
  ///
  /// ASVS 7.4.1: `SignOutScope.global` ruft den GoTrue-Logout-Endpoint mit
  /// dem Access-Token auf und widerruft die Session serverseitig (Refresh-
  /// Token invalidiert). Erst danach lokaler SignOut + Token-Löschung.
  /// Netzwerkfehler blockieren den Logout nicht (best-effort).
  @override
  Future<void> logout() async {
    try {
      await _supabase.auth
          .signOut(scope: SignOutScope.global)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline-Fallback: nur lokal ausloggen; die serverseitige Session
      // läuft bis zum Ablauf des Refresh-Tokens weiter.
      try {
        await _supabase.auth.signOut();
      } catch (_) {
        // Best-effort: lokales Löschen der Tokens erfolgt trotzdem.
      }
    }
    await _tokens.clear();
  }

  /// Löscht den Nutzer vollständig über die serverseitige Edge Function
  /// 'delete-account' (DSGVO Art. 17). Der Auth-User selbst wird mit dem
  /// service_role-Key gelöscht; der Client besitzt diesen Key nie.
  ///
  /// Audit M-12: Ein FEHLSCHLAG der Löschung wird nicht mehr verschluckt -
  /// vorher glaubte der Nutzer, sein Account sei gelöscht, während alle
  /// Server-Daten erhalten blieben. Bei Fehler wirft diese Methode und
  /// der Aufrufer ([AuthNotifier]) unterlässt den lokalen Reset.
  @override
  Future<void> deleteAccount() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        // Sitzung auffrischen: Ein abgelaufener Access-Token (Refresh
        // schlägt still fehl, z. B. nach langer Inaktivität) führt
        // serverseitig zu 401 - dann lieber klar zum Re-Login schicken,
        // statt kryptisch abzulehnen.
        try {
          await _supabase.auth.refreshSession().timeout(
                const Duration(seconds: 15),
              );
        } catch (_) {
          throw AppException(
            'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an '
            'und versuche das Löschen danach erneut.',
          );
        }
        // Timeout 60 s (statt 20 s): Kalte Edge-Function-Starts brauchen
        // beim ersten Aufruf deutlich länger - ein Timeout sieht sonst
        // exakt wie ein Netzwerkfehler aus ("konnte nicht übermittelt
        // werden"), obwohl der Server noch arbeitet.
        final response = await _supabase.functions
            .invoke('delete-account')
            .timeout(const Duration(seconds: 60));
        final data = response.data;
        if (response.status != 200 ||
            (data is Map && data['deleted'] != true)) {
          throw AppException(
            'Die Löschung konnte auf dem Server nicht abgeschlossen '
            'werden. Bitte prüfe deine Verbindung und versuche es erneut.',
          );
        }
      } on AppException {
        rethrow;
      } on FunctionException catch (e) {
        // Echte Server-Antwort statt Generik: details enthält den
        // JSON-Body der Function ({"error": "..."}). So wird aus
        // "konnte nicht übermittelt werden" eine Diagnose.
        final serverError =
            e.details is Map ? (e.details as Map)['error']?.toString() : null;
        if (serverError != null &&
            serverError.contains('mfa_required')) {
          throw AppException(
            'Für die Löschung ist ein aktueller MFA-Code nötig. Bitte '
            'schließe zuerst die 2FA-Abfrage ab und versuche es erneut.',
          );
        }
        if (serverError != null && serverError.isNotEmpty) {
          throw AppException('Löschung abgelehnt ($serverError).');
        }
        throw AppException(
          'Die Löschung konnte nicht an den Server übermittelt werden. '
          'Dein Account wurde NICHT gelöscht - bitte versuche es erneut.',
        );
      } catch (e) {
        throw AppException(
          'Die Löschung konnte nicht an den Server übermittelt werden. '
          'Dein Account wurde NICHT gelöscht - bitte versuche es erneut.',
        );
      }
    }
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort
    }
    await _tokens.clear();
  }
}
