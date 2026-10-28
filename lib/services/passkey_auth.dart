// Die Passkey-API von GoTrue ist als @experimental markiert (Supabase
// Beta-Feature) - bewusst genutzt, Ignorieren der Warnung projectweit.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys_platform_interface/types/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/thestia_passkey_authenticator.dart';
import 'package:thestia/utils/constants.dart';

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
  ///
  /// [captchaToken]: GoTrue verlangt für die Passkey-REGISTRIERUNG ein
  /// CAPTCHA-Token. Ohne Token lehnt der Server die Challenge-Anfrage
  /// ab - live geprüft am 28.10.2026:
  ///
  ///   POST /auth/v1/passkeys/registration/options  (ohne Token)
  ///   -> HTTP 400 {"error_code":"captcha_failed",
  ///                "msg":"captcha protection: request disallowed
  ///                       (no captcha_token found)"}
  ///
  /// Das Paket `registerPasskey()` kann kein Token mitschicken:
  /// `startRegistration()` sendet einen LEEREN Body ({}). Deshalb
  /// scheiterte die Einrichtung seit jeher - der Server lehnte ab,
  /// BEVOR der native Dialog überhaupt erschien.
  ///
  /// Mit Token wird der erste Schritt deshalb hier selbst gemacht; der
  /// Rest (native Zeremonie, Verifikation) nutzt die Paket-API.
  static Future<void> register({String? captchaToken}) {
    return _runSingle(() async {
      if (!SupabaseService.isInitialized) {
        throw AppException('Passkey-Setup ist derzeit nicht verfügbar.');
      }
      try {
        if (captchaToken != null && captchaToken.isNotEmpty) {
          await _registerMitCaptcha(captchaToken);
        } else {
          await SupabaseService.client.auth.registerPasskey(_authenticator);
        }
      } catch (e) {
        throw _explain(e, login: false);
      }
    });
  }

  /// Registrierung MIT CAPTCHA-Token: Challenge selbst holen, dann die
  /// native Zeremonie, dann verifizieren.
  ///
  /// Der Aufbau entspricht dem von `registerPasskey()` im Paket - nur
  /// mit dem einen Unterschied, dass der Challenge-Aufruf das Token
  /// mitschickt. Das Body-Feld ist verschachtelt
  /// (`gotrue_meta_security.captcha_token`); mit einem flachen
  /// `captcha_token` lehnt GoTrue weiterhin ab.
  static Future<void> _registerMitCaptcha(String captchaToken) async {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) {
      throw AppException(
        'Bitte zuerst anmelden - ein Passkey gehört zu einem Konto.',
      );
    }

    final url =
        '${AppConstants.supabaseUrlBase}/auth/v1/passkeys/registration/options';
    final antwort = await http.post(
      Uri.parse(url),
      headers: {
        'apikey': AppConstants.supabasePublishableKey,
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'gotrue_meta_security': {'captcha_token': captchaToken},
      }),
    );

    if (antwort.statusCode != 200) {
      throw _explain(
        'AuthApiException: HTTP ${antwort.statusCode} ${antwort.body}',
        login: false,
      );
    }

    final daten = jsonDecode(antwort.body) as Map<String, dynamic>;
    final challengeId = daten['challenge_id'] as String;
    final optionen = Map<String, dynamic>.from(daten['options'] as Map);

    // Native Zeremonie (Fingerabdruck / Face-ID / Geräte-PIN).
    final response = await _authenticator.register(_requestAusOptionen(optionen));

    // Fertigstellen: der Server prüft die Signatur.
    await SupabaseService.client.auth.passkey.verifyRegistration(
      challengeId: challengeId,
      credential: response.toJson(),
    );
  }

  /// Wandelt die Server-Optionen in das Format des Passkey-Plugins.
  ///
  /// Gleiche Aufgabe wie `passkeyRegisterRequestFromOptions` im Paket -
  /// dieses ist aber nicht oeffentlich exportiert, deshalb hier die
  /// (kurze) eigene Umsetzung:
  ///   * die Challenge kommt base64url MIT Fuellzeichen; das Plugin
  ///     lehnt gefuellte Werte ab,
  ///   * jedes excluded Credential braucht eine (leere) Transport-Liste.
  static RegisterRequestType _requestAusOptionen(Map<String, dynamic> optionen) {
    final json = Map<String, dynamic>.of(optionen);

    final challenge = json['challenge'];
    if (challenge is String) {
      json['challenge'] = _ohneFuellzeichen(challenge);
    }

    final ausgeschlossen = json['excludeCredentials'];
    if (ausgeschlossen is List) {
      json['excludeCredentials'] = ausgeschlossen
          .whereType<Map<dynamic, dynamic>>()
          .map((credential) {
            final normalisiert = Map<String, dynamic>.from(credential);
            final id = normalisiert['id'];
            if (id is String) {
              normalisiert['id'] = _ohneFuellzeichen(id);
            }
            final transports = normalisiert['transports'];
            normalisiert['transports'] = transports is List
                ? transports.whereType<String>().toList()
                : <String>[];
            return normalisiert;
          })
          .toList();
    }

    return RegisterRequestType.fromJson(json);
  }

  /// Entfernt die base64url-Fuellzeichen ('=') am Ende.
  static String _ohneFuellzeichen(String wert) {
    var ende = wert.length;
    while (ende > 0 && wert[ende - 1] == '=') {
      ende--;
    }
    return wert.substring(0, ende);
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

  /// Prüft, ob auf dem Konto bereits mindestens ein Passkey liegt.
  ///
  /// v0.10.0: Die Einrichtung rief blind [register] auf. Wer das Gerät
  /// wechselt - oder dieselbe Einrichtung nach einem Update erneut
  /// durchläuft - bekam daraufhin einen zweiten nativen Dialog und
  /// danach je nach Plattform eine Fehlermeldung, weil der Credential
  /// schon existiert. Beides ist eine vermeidbare Sackgasse, und die
  /// Meldung ("Einrichtung fehlgeschlagen") lag falsch: es wurde nichts
  /// kaputtgemacht.
  ///
  /// Bewusst NICHT `listRegistered().isNotEmpty`:
  ///
  ///  * Die Liste zu lesen verlangt auf manchen Plattformen AAL2. Fehlt
  ///    die biometrische Anmeldung, wirft der Aufruf - und die
  ///    Einrichtung wuerde dann einen Passkey ablehnen, nur weil das
  ///    Lesen fehlschlug. Ein false lautet hier "unbekannt", nicht
  ///    "nicht vorhanden".
  ///  * Die Liste kann aus anderen Gruenden fehlschlagen (Netz, alte
  ///    Supabase-Version). Auch dann darf die Registrierung laufen.
  ///
  /// Deshalb wird jeder Fehler als "kein Passkey bekannt" behandelt, und
  /// der Aufrufer bekommt `true` fuer den Fehlerfall nur ueber
  /// [register] zurueckgemeldet.
  ///
  /// Rueckgabe: true = mindestens ein Passkey vorhanden (Fehlerfall: false).
  static Future<bool> hasRegisteredPasskey() async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final list = await SupabaseService.client.auth.passkey.list();
      return list.isNotEmpty;
    } catch (_) {
      // Unbekannt ist nicht "nein" - der Aufrufer soll trotzdem
      // registrieren duerfen.
      return false;
    }
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

    // Der ROHE Fehlertext gehoert ins Log, und zwar VOR jeder Zuordnung.
    //
    // Grund: die Zuordnung unten ist eine Whitelist. Was nicht auf eines
    // ihrer Muster passt, landet in der generischen Meldung
    // "Einrichtung fehlgeschlagen" - und die nennt die Ursache nicht.
    // Damit war die Meldung "Passkey-Einrichtung fehlgeschlagen" die
    // Gesamtaussage des Problems, obwohl Android eine sehr genaue
    // Fehlerklasse liefert (SecurityError, NotAllowedError,
    // android-sync-account-not-available, GetCredentialProvider-
    // ConfigurationException ...). Ohne dieses Log ist nicht
    // unterscheidbar, ob die Domain-Verknuepfung, der Sperrbildschirm,
    // die Play Services oder der Server die Ursache ist - und jede
    // dieser vier Klassen sieht in der Oberflaeche gleich aus.
    //
    // `developer.log` statt `debugPrint`: debugPrint steht in
    // Release-Builds in einem `if (kDebugMode)`-Zweig, und der Compiler
    // wirft den Zweig samt Aufruf weg. Die Diagnose waere damit genau
    // in den Builds weg, die der Nutzer tatsaechlich testet. log() aus
    // dart:developer ueberlebt und landet im Logcat.
    developer.log(
      'Passkey $action ROHER Fehler (${e.runtimeType}): $text',
      name: 'PasskeyAuth',
    );
    if (kDebugMode) {
      debugPrint('[PasskeyAuth] $action ROHER Fehler '
          '(${e.runtimeType}): $text');
    }


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
    // Vor den AuthApiError-Prüfungen: Fehler, die NICHTS mit dem Server
    // zu tun haben, aber bisher in den „unbekannt"-Zweig fielen.
    //
    // Ein MissingPluginException heißt: das Passkey-Plugin ist in DIESEM
    // Build nicht registiert. Die Meldung lautete vorher „versuche es
    // später erneut" - das ist die unnützigste aller Meldungen, weil der
    // Nutzer nichts tun kann und das Team keinen Hinweis hat. Aufgetreten
    // ist genau das beim Release-Bauen: der Text landete im unbekannten
    // Zweig, weil er keinen der bekannten Fehlertypen enthält.
    if (text.contains('MissingPluginException')) {
      debugPrint('[PasskeyAuth] Plugin fehlt: $e');
      return AppException(
        'Die Passkey-Funktion ist in dieser Version der App nicht '
        'verfügbar. Bitte melde es dem Support - es ist ein Fehler im '
        'Build, nicht auf deinem Gerät.',
        messageKey: '${k}pluginMissing',
      );
    }
    // RP-ID / Hostname: Der Server akzeptiert den Ursprung nicht. Das ist
    // NICHT dasselbe wie „verification failed" - hier scheitert schon die
    // Prüfung der Domain, bevor ein Credential entsteht.
    if (text.toLowerCase().contains('hostname') ||
        text.toLowerCase().contains('rp id') ||
        text.toLowerCase().contains('relying party')) {
      debugPrint('[PasskeyAuth] RP-ID-Hostname: $e');
      return AppException(
        'Die Server-Konfiguration passt nicht zur App (RP-ID/Hostname). '
        'Bitte melde es dem Support.',
        messageKey: '${k}rpIdMismatch',
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

    // Digital Asset Links: Androids eigene Fehlerklasse fuer genau den
    // Fall, in dem die Zeremonie gar nicht erst beginnt.
    //
    // WICHTIG - das ist NICHT dasselbe wie "SecurityError" weiter oben.
    // "SecurityError" ist die WebAuthn-Fehlermeldung, wenn der Browser
    // eine nicht verknuepfte Domain sieht. Android Credential Manager
    // laesst die Zeremonie aber schon vorher scheitern und wirft dann
    // aus dem StatementService:
    //
    //     Unable to verify package. Digital Asset Links verification failed.
    //     GetCredentialProviderConfigurationException
    //     AssetLinkError
    //
    // Dieser Text enthielt vorher keines der Muster und landete
    // deshalb im "unbekannt"-Zweig mit der Meldung "Passkey-Einrichtung
    // fehlgeschlagen" - ohne jeden Hinweis darauf, dass die Ursache an
    // der assetlinks.json liegt. Genau das war der Fall: die Datei war
    // erreichbar und korrekt, aber die Verknuepfung schlug fehl, und
    // die Meldung sagte nichts darueber.
    final dalText = text.toLowerCase();
    if (dalText.contains('asset link') ||
        dalText.contains('assetlink') ||
        dalText.contains('digital asset') ||
        dalText.contains('verify package') ||
        dalText.contains('getcredentialproviderconfiguration')) {
      debugPrint('[PasskeyAuth] Digital Asset Links: $e');
      return AppException(
        'Die App konnte sich nicht mit auth.thestia.de verknuepfen '
        '(Digital Asset Links). Die Verknuepfung prueft den '
        'Fingerabdruck des Signaturzertifikats der installierten App. '
        'Bei einer Neuinstallation aus dem Play Store ist das ein '
        'anderes Zertifikat als bei einem lokalen Build - dann passt '
        'der Fingerabdruck in der Datei noch nicht.',
        messageKey: '${k}assetLinks',
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
