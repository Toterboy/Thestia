// Die Passkey-API von GoTrue ist als @experimental markiert (Supabase
// Beta-Feature) - bewusst genutzt, Ignorieren der Warnung projectweit.
// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/thestia_passkey_authenticator.dart';

/// Kapselt die native Passkey-Anmeldung/-Registrierung.
///
/// Nutzt den [ThestiaPasskeyAuthenticator] für die Plattform-Prompts
/// (FaceID/TouchID/Biometrie) und Supabase Auth für die WebAuthn-Ceremony
/// (Server-Seite).
///
/// Voraussetzungen (sonst schlägt der Dialog/Login fehl):
///  - Supabase Dashboard: Passkeys aktiv, RP-ID = `auth.thestia.de`
///  - Android: `assetlinks.json` + `<meta-data asset_statements>` (Manifest)
///  - iOS: Associated-Domains-Entitlement (`webcredentials:auth.thestia.de`)
///  - Gerät: Sperrbildschirm (PIN/Muster/Biometrie) + aktuelle Google Play
///    Services (Credential Manager).
class PasskeyAuth {
  PasskeyAuth._();

  static final ThestiaPasskeyAuthenticator _authenticator =
      ThestiaPasskeyAuthenticator();

  /// Busy-Guard: Nur EINE Zeremonie gleichzeitig. Ein Doppel-Tap auf
  /// "Passkey erstellen" startete sonst zwei Registrierungen parallel -
  /// die zweite brach die erste ab ("Anfrage abgebrochen von Thestia") und
  /// die Challenge-Verrechnung endete in "credential verification failed".
  static bool _ceremonyRunning = false;

  static Future<T> _runSingle<T>(Future<T> Function() action) async {
    if (_ceremonyRunning) {
      throw AppException(
        'Eine Passkey-Anfrage läuft bereits. Bitte warte einen Moment '
        'und bestätige den Dialog auf dem Bildschirm.',
      );
    }
    _ceremonyRunning = true;
    try {
      return await action();
    } finally {
      _ceremonyRunning = false;
    }
  }

  /// Meldet den Nutzer mit einem vorhandenen Passkey an.
  ///
  /// Wirft bei Abbruch (Nutzer) oder Fehler (kein Passkey, Domain-Link
  /// fehlt). Der Aufrufer zeigt eine passende Meldung an.
  ///
  /// [captchaToken]: Bei aktivierter Dashboard-CAPTCHA verlangt der Server
  /// auch für den Passkey-Login ein Token (`/passkeys/authentication/
  /// options` prüft `gotrue_meta_security`) – ohne Token lehnt er mit
  /// `captcha_verification_failed` ab, bevor der native Dialog erscheint
  /// ("Server hat die Passkey-Anfrage abgelehnt").
  static Future<void> signIn({String? captchaToken}) {
    return _runSingle(() async {
      if (!SupabaseService.isInitialized) {
        throw AppException('Passkey-Login ist derzeit nicht verfügbar.');
      }
      try {
        await SupabaseService.client.auth.signInWithPasskey(
          _authenticator,
          captchaToken: captchaToken,
        );
      } catch (e) {
        throw _explain(e, login: true);
      }
    });
  }

  /// Registriert ein neues Passkey für den bereits eingeloggten Nutzer.
  static Future<void> register() {
    return _runSingle(() async {
      if (!SupabaseService.isInitialized) {
        throw AppException('Passkey-Setup ist derzeit nicht verfügbar.');
      }
      try {
        await SupabaseService.client.auth.registerPasskey(_authenticator);
      } catch (e) {
        throw _explain(e, login: false);
      }
    });
  }

  /// Liste der Passkeys, die auf dem Konto registriert sind.
  ///
  /// Wirft bei Fehlern (z. B. AAL2 nötig) - der Aufrufer behandelt das.
  static Future<List<Passkey>> listRegistered() async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Verwaltung ist derzeit nicht verfügbar.');
    }
    return SupabaseService.client.auth.passkey.list();
  }

  /// Löscht einen Passkey vom Konto (z. B. Alt-Gerät / doppelte Einträge).
  ///
  /// WICHTIG bei der Fehlersuche ("Der Server konnte den Passkey nicht
  /// bestätigen"): Ist auf dem Konto ein ALTER/Defekt-Passkey hinterlegt,
  /// kann dessen excludeCredentials-Eintrag die Registrierung stören -
  /// Löschen und Neuanlegen behebt das.
  static Future<void> delete({required String passkeyId}) async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Verwaltung ist derzeit nicht verfügbar.');
    }
    await SupabaseService.client.auth.passkey.delete(passkeyId: passkeyId);
  }

  /// Bennent einen Passkey um (z. B. "Pixel 8" statt generischem Namen).
  static Future<void> rename({
    required String passkeyId,
    required String friendlyName,
  }) async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Verwaltung ist derzeit nicht verfügbar.');
    }
    await SupabaseService.client.auth.passkey.update(
      passkeyId: passkeyId,
      friendlyName: friendlyName,
    );
  }

  /// Anzahl der bereits registrierten Passkeys (Best-Effort; null bei
  /// Fehler - z. B. wenn AAL2 nötig wäre).
  static Future<int?> countRegistered() async {
    try {
      return (await listRegistered()).length;
    } catch (_) {
      return null;
    }
  }

  /// Test-Hook: Fehler-Mapping isoliert pruefbar machen.
  @visibleForTesting
  static AppException explainError(Object e, {required bool login}) =>
      _explain(e, login: login);

  /// Übersetzt kryptische Plugin-/WebAuthn-Fehler in verständliche Meldungen.
  ///
  /// Das Plugin meldet DOM-Fehlertypen als Code wie
  /// `android-unhandled: NotAllowedError`. Die häufigsten Ursachen:
  ///  - NotAllowedError: Abbruch/Timeout oder kein Sperrbildschirm aktiv
  ///  - SecurityError: RP-ID/Domain-Verknüpfung (assetlinks.json) passt nicht
  ///  - InvalidStateError: Auf diesem Gerät existiert bereits ein Passkey
  ///
  /// Jede Meldung bekommt zusätzlich einen L10n-Key ([AppException.messageKey])
  /// mit - Services haben keinen BuildContext, die Anzeige-Stellen lokalisieren
  /// deshalb über [L10n.exc] (Fallschlüssel: die deutsche Message).
  static AppException _explain(Object e, {required bool login}) {
    final action = login ? 'Anmeldung' : 'Einrichtung';
    final k = 'passkey.err.';
    // Plugin-Fehler kommen teils als PlatformException, teils als generisches
    // FlutterError - daher String-basiert auf den Fehlertyp prüfen.
    final text = e.toString();

    if (text.contains('cancelled') ||
        text.toLowerCase().contains('cancellationexception')) {
      return AppException(
        'Passkey-$action abgebrochen.',
        messageKey: login
            ? '${k}cancelledLogin'
            : '${k}cancelledRegister',
      );
    }
    if (text.contains('NotAllowedError')) {
      return AppException(
        'Passkey-$action wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
        messageKey: login ? '${k}notAllowedLogin' : '${k}notAllowedRegister',
      );
    }
    if (text.contains('InvalidStateError')) {
      return AppException(
        'Auf diesem Gerät existiert bereits ein Passkey für dieses Konto.',
        messageKey: '${k}invalidState',
      );
    }
    if (text.contains('SecurityError')) {
      return AppException(
        'Die App konnte ihre Domain-Zugehörigkeit nicht nachweisen '
        '(Passkey-Domain-Verknüpfung). Prüfe, ob die neueste App-Version '
        'installiert ist, und melde es dem Support, falls es bleibt.',
        messageKey: '${k}securityError',
      );
    }
    if (text.contains('android-sync-account-not-available')) {
      return AppException(
        'Der Passkey konnte nicht verschlüsselt gespeichert werden. '
        'Stelle sicher, dass du auf dem Gerät mit einem Google-Konto '
        'angemeldet bist und die Google Play Services aktuell sind.',
        messageKey: '${k}syncAccount',
      );
    }
    if (text.contains('android-timeout')) {
      return AppException(
        'Zeitüberschreitung beim Passkey-$action. Bitte versuche es '
        'gleichzeitig am Bildschirm erneut.',
        messageKey: login ? '${k}timeoutLogin' : '${k}timeoutRegister',
      );
    }
    if (text.contains('no_credential') || text.contains('NoCredential')) {
      return AppException(
        login
            ? 'Kein Passkey für dieses Konto gefunden. Richte zuerst einen '
                'unter Einstellungen ein.'
            : 'Kein Passkey-Speicher verfügbar. Prüfe Sperrbildschirm und '
                'Google Play Services.',
        messageKey: login ? '${k}noCredentialLogin' : '${k}noCredentialRegister',
      );
    }

    // Server lehnt die Anfrage ab, BEVOR der native Dialog erscheint
    // ("schlägt direkt fehl"): GoTrue liefert die WebAuthn-Challenge.
    // Typische Ursachen: Passkeys/WebAuthn im Supabase-Dashboard nicht
    // aktiviert oder RP-ID/Origins falsch konfiguriert.
    if (text.toLowerCase().contains('captcha')) {
      return AppException(
        'Der Sicherheitscheck fehlte oder ist abgelaufen. '
        'Bitte versuche es erneut.',
        messageKey: '${k}captcha',
      );
    }
    // GoTrue lehnt ab, NACHDEM die native Zeremonie lief: Die WebAuthn-
    // Verifikation des Credentials scheitert ("credential verification
    // failed"). Häufigste Ursache (Diagnose, siehe
    // docs/PASSKEYS_SERVER_SETUP.md): Der Origin des installierten APKs
    // (android:apk-key-hash:<SHA-256>) fehlt in GOTRUE_WEBAUTHN_RP_ORIGINS
    // - der native Dialog funktioniert trotzdem, weil er nur die
    // assetlinks.json prüft. Zweitursache: Alter/Defekt-Passkey am Konto.
    if (text.toLowerCase().contains('verification failed')) {
      debugPrint('[PasskeyAuth] Verifikation fehlgeschlagen: $e');
      return AppException(
        'Der Server konnte den Passkey nicht bestätigen. Wahrscheinlich '
        'fehlt der Ursprung (apk-key-hash) der installierten App in der '
        'Passkey-Konfiguration des Servers - siehe '
        'docs/PASSKEYS_SERVER_SETUP.md. Alternativ: alten Passkey unter '
        '"Passkeys verwalten" löschen und erneut anlegen.',
        messageKey: '${k}verificationFailed',
      );
    }
    final isAuthApiError = text.contains('AuthApiException') ||
        RegExp(r'\bstatus: 4\d\d\b').hasMatch(text) ||
        text.toLowerCase().contains('webauthn');
    if (isAuthApiError) {
      debugPrint('[PasskeyAuth] Server-Fehler: $e');
      // Server-Grund (kuratiert, kurz) transparent machen: GoTrue-Antworten
      // sind kurze Sätze ohne Secrets - sie helfen dem Team bei der
      // Ursachensuche (z. B. "aal2 required", "User enrollments disabled").
      final reason = _serverReason(text);
      return AppException(
        'Der Server hat die Passkey-Anfrage abgelehnt. Bitte prüfe in den '
        'Supabase-Einstellungen, ob "Passkeys" aktiviert ist und die '
        'RP-ID auf auth.thestia.de gesetzt ist.$reason',
        messageKey: '${k}serverRejected',
        params: {'reason': reason},
      );
    }

    // Unbekannter Fehler: Details NIE durchreichen (auch nicht im Debug -
    // Profile-Builds haben kReleaseMode == false und wuerden sonst leaken).
    // Die vollstaendige Meldung landet nur im Log.
    debugPrint('[PasskeyAuth] $action fehlgeschlagen: $e');
    return AppException(
      'Passkey-$action fehlgeschlagen. Bitte versuche es später erneut.',
      messageKey: login ? '${k}unknownLogin' : '${k}unknownRegister',
    );
  }

  /// Extrahiert den kurzen Server-Grund aus einer GoTrue-Fehlermeldung
  /// (ohne Secrets): "message: ..." bzw. den HTTP-Status.
  static String _serverReason(String text) {
    final msgMatch = RegExp(r'message:\s*([^,}]+)').firstMatch(text);
    if (msgMatch != null) {
      final raw = msgMatch.group(1)!.trim();
      return ' (Server: ${raw.substring(0, raw.length.clamp(0, 120))})';
    }
    final statusMatch = RegExp(r'\bstatus: (\d{3})').firstMatch(text);
    if (statusMatch != null) return ' (HTTP ${statusMatch.group(1)})';
    return '';
  }
}
