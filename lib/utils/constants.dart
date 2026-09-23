import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-weite Konstanten (Schlüssel, Defaults).
class AppConstants {
  AppConstants._();

  /// SharedPreferences-Schlüssel.
  static const String prefsSettingsKey = 'app_settings';
  static const String prefsProfileKey = 'user_profile';
  static const String prefsAuthKey = 'auth_user_id';
  static const String prefsCredentialsKey = 'auth_credentials';
  static const String prefsLikesKey = 'liked_profile_ids';
  static const String prefsGenderPreferenceKey = 'user_gender_preference';

  /// Fallback-ID für den Demo-Modus (kein Backend).
  static const String _demoUserId = 'me';

  /// Liefert die ID des aktuell eingeloggten Nutzers.
  ///
  /// Gibt die Supabase-User-ID zurück, wenn eine Session aktiv ist,
  /// sonst die Demo-ID `'me'` für den lokalen Modus.
  static String get currentUserId {
    try {
      // ignore: avoid_dynamic_calls
      final uid = _supabaseUserIdGetter?.call();
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return _demoUserId;
  }

  /// Wird in main.dart gesetzt, um die Supabase-User-ID abzurufen,
  /// ohne hier eine direkte Abhängigkeit zu erzeugen.
  static String? Function()? _supabaseUserIdGetter;

  /// Registriert den Getter für die Supabase-User-ID (Aufruf in main.dart).
  static void registerUserIdGetter(String? Function() getter) {
    _supabaseUserIdGetter = getter;
  }

  /// Expliziter Demo-Modus-Schalter.
  ///
  /// `--dart-define=DEMO_MODE=true` aktiviert die lokale Mock-Auth
  /// (fail-safe: ohne Angabe bleibt der Demo-Modus ausgeschaltet).
  /// Ob der Demo-Modus letztlich aktiv ist, entscheidet die reine
  /// Funktion `resolveDemoMode()` (lib/utils/demo_mode.dart):
  /// Release-Build und aktive Supabase-Session haben immer Vorrang.
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE');

  /// ID des Admin-Accounts (via --dart-define=ADMIN_UUID=... beim Build).
  ///
  /// Wird beim Build gesetzt: `flutter build --dart-define=ADMIN_UUID=<echte-uuid>`.
  /// Ist der Parameter nicht gesetzt, bleibt der Wert leer → Admin-Funktionen
  /// sind deaktiviert (fail-safe: niemand kann Admin werden).
  /// Der Zugang erfolgt über versteckten Long-Press im Profil auf den Namen.
  static final String adminUserId = const String.fromEnvironment(
    'ADMIN_UUID',
    defaultValue: '',
  );

  /// Standard-Interessen zur schnellen Auswahl beim Profil.
  static const List<String> presetInterests = [
    'Sport', 'Musik', 'Reisen', 'Kochen', 'Filme', 'Gaming',
    'Kunst', 'Lesen', 'Fotografie', 'Tiere', 'Fitness', 'Natur',
    'Technologie', 'Mode', 'Tanzen', 'Yoga', 'Wandern', 'Kaffee',
    'Party', 'Nachhaltigkeit', 'Theater', 'Schreiben', 'Motorrad',
    'Klettern', 'Volunteering',
  ];

  /// Musik-Genres zur Auswahl im Interview (Nutzer-Regel: Genres +
  /// Lieblingskünstler + Song abfragen). Deutsche Literale wie bei
  /// [presetInterests] (kein L10n); die Werte landen 1:1 in
  /// profiles.music_liked und damit im Matching (Migration 074).
  static const List<String> presetMusicGenres = [
    'Pop', 'Rock', 'Hip-Hop', 'Elektro', 'House', 'Techno',
    'Klassik', 'Jazz', 'Metal', 'Punk', 'Indie', 'R&B',
    'Soul', 'Funk', 'Reggae', 'Latin', 'Country', 'Schlager',
  ];

  /// Maximale Distanz (km) für den Entfernungsfilter (Slider-Obergrenze).
  static const int maxDistanceKm = 100;

  /// Standard-Distanz (km) für den Entfernungsfilter.
  static const int defaultDistanceKm = 50;

  // ===========================================================================
  // Build-Zeit-Konfiguration (via --dart-define)
  // ===========================================================================

  // ===========================================================================
  // Feature-Flags (bewusst ABgeschaltet, später reaktivierbar)
  // ===========================================================================

  /// NSFW-Foto-Moderation (Betreiber-Entscheidung: deaktiviert).
  ///
  /// `false` (Default): Bilder werden ohne Prüfung durchgelassen; es wird
  /// KEIN photo_moderation-DB-Eintrag erzeugt (keine Admin-Warteschlange).
  /// Reaktivierung später: `--dart-define=NSFW_MODERATION_ENABLED=true`
  /// zusammen mit der Edge-Function-Implementierung (Token serverseitig,
  /// HuggingFaceService muss dann den Function-Call ausführen).
  static const bool nsfwModerationEnabled =
      bool.fromEnvironment('NSFW_MODERATION_ENABLED', defaultValue: false);

  /// Video-Verifizierung mit lokaler KI-Triage (v0.9.1: aktiviert).
  ///
  /// `true` (Default): Info/Video/Complete-Routen erreichbar; Einreichung
  /// und manuelle Prüfung laufen wie bisher, plus KI-Sofortfreigabe bei
  /// unauffälliger Schätzung (Abweichung <= 2 Jahre) und Admin-Queue mit
  /// KI-Schätzung. Deaktivierung: `--dart-define=VERIFICATION_ENABLED=false`.
  static const bool verificationEnabled =
      bool.fromEnvironment('VERIFICATION_ENABLED', defaultValue: true);

  /// F-Droid-Build: komplett ohne Firebase/FCM kompiliert und zur Laufzeit
  /// deaktiviert. Build mit:
  ///   flutter build apk --release --flavor fdroid --dart-define=FDROID=true
  static const bool fdroidBuild =
      bool.fromEnvironment('FDROID', defaultValue: false);

  /// Basis-URL des Supabase-Projekts (aus .env), ohne trailing slash.
  /// Wird u. a. für die captcha-page Edge Function benötigt.
  static String get supabaseUrlBase {
    if (_dotenvReady) {
      final v = dotenv.env['SUPABASE_URL']?.trim() ?? '';
      if (v.isNotEmpty) return v.replaceAll(RegExp(r'/+$'), '');
    }
    return '';
  }

  // ===========================================================================
  // CAPTCHA bei der Registrierung (Bot-Schutz)
  // ===========================================================================

  /// CAPTCHA-Anbieter: `'hcaptcha'`, `'turnstile'` (Cloudflare) oder `''`
  /// (deaktiviert – Default).
  ///
  /// Quellen (in dieser Reihenfolge):
  ///  1. `.env`-Eintrag `CAPTCHA_PROVIDER` (empfohlen – gilt automatisch
  ///     für jeden Build/Run, keine --dart-define-Args nötig)
  ///  2. `--dart-define=CAPTCHA_PROVIDER=...` (Fallback)
  ///
  /// WICHTIG (Operator): Funktioniert NUR zusammen mit der Dashboard-
  /// Aktivierung (Authentication → CAPTCHA, gleicher Anbieter + Secret).
  /// Ohne Dashboard-Aktivierung wird das Token vom Server ignoriert.
  static String get captchaProvider {
    const fromEnv = String.fromEnvironment('CAPTCHA_PROVIDER');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (_dotenvReady) {
      final v = dotenv.env['CAPTCHA_PROVIDER']?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Öffentlicher Sitekey des CAPTCHA-Anbieters (kein Secret!).
  /// `.env`-Eintrag `CAPTCHA_SITEKEY` oder `--dart-define=CAPTCHA_SITEKEY=`.
  static String get captchaSiteKey {
    const fromEnv = String.fromEnvironment('CAPTCHA_SITEKEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (_dotenvReady) {
      return dotenv.env['CAPTCHA_SITEKEY']?.trim() ?? '';
    }
    return '';
  }

  /// dotenv wird in main() vor allem anderen geladen; der Getter toleriert
  /// Zugriffe vor dem Laden (z. B. in frühen Tests).
  static bool get _dotenvReady {
    try {
      return dotenv.isInitialized;
    } catch (_) {
      return false;
    }
  }

  /// True, wenn CAPTCHA im Client aktiv konfiguriert ist. Das zugehörige
  /// Secret (Turnstile/hCaptcha Secret Key) liegt ausschließlich im
  /// Supabase Dashboard – niemals im Client.
  static bool get captchaEnabled =>
      (captchaProvider == 'hcaptcha' || captchaProvider == 'turnstile') &&
      captchaSiteKey.isNotEmpty;

  // HINWEIS (Sicherheit): HF_API_TOKEN / HF_INFERENCE_URL wurden ENTFERNT -
  // ein in die App eingebettetes Token wäre aus APK/IPA extrahierbar.
  // Die NSFW-Moderation wird später serverseitig über eine Edge Function
  // implementiert (Token liegt dann ausschließlich als Function-Secret).

  // HINWEIS (Betreiber-Entscheidung): TURN wird NICHT genutzt (keine
  // laufenden Abos/Kosten). ICE läuft ausschließlich über STUN (europäische
  // Server, siehe WebRTCService/ice-config Edge Function). Konsequenz:
  // Hinter symmetrischen NATs/strikten Firewalls (z. B. Unternehmensnetze)
  // kann ggf. keine direkte P2P-Verbindung aufgebaut werden. Betroffen ist
  // insbesondere MOBILFUNK (CGNAT): Dort scheitert der P2P-Zufallschat
  // aktuell REGELMÄSSIG. Nutzer-Hinweis hierzu: random.errorConnectTimeout
  // (app_strings.dart). Lösung, falls gewünscht: TURN-Server (z. B.
  // coturn auf eigenem VPS) + TURN_URL/TURN_SECRET als Function-Secrets
  // setzen (Client/ice-config unterstützen das bereits).
}

/// Deutsche Bundesländer (Vollnamen, für die Auswahl im Profil und in der
/// Einrichtung - zentrale Definition, damit beide Screens identisch sind).
const kGermanStates = <String>[
  'Baden-Württemberg',
  'Bayern',
  'Berlin',
  'Brandenburg',
  'Bremen',
  'Hamburg',
  'Hessen',
  'Mecklenburg-Vorpommern',
  'Niedersachsen',
  'Nordrhein-Westfalen',
  'Rheinland-Pfalz',
  'Saarland',
  'Sachsen',
  'Sachsen-Anhalt',
  'Schleswig-Holstein',
  'Thüringen',
];
