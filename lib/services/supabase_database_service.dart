import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thestia/models/gender.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/peer_id.dart';

/// Datenbankzugriff über Supabase PostgREST, abgesichert durch Row Level Security (RLS).
///
/// WICHTIG:
/// - Alle Tabellen, auf die zugegriffen wird, MÜSSEN in Supabase RLS-Policies haben.
/// - Die Policies legen fest, welche Zeilen ein Nutzer lesen/schreiben/löschen darf.
/// - Clientseitig brauchst du KEINE zusätzlichen Berechtigungsprüfungen, weil Supabase
///   die Policies auf Basis der eingeloggten Supabase-Auth-User-ID erzwingt.
///
/// Beispiel-Policies (Supabase SQL Editor):
/// ```sql
/// -- Eigenes Profil lesen/bearbeiten
/// CREATE POLICY "Users can read own profile"
///   ON profiles FOR SELECT TO authenticated
///   USING (auth.uid() = user_id);
///
/// CREATE POLICY "Users can update own profile"
///   ON profiles FOR UPDATE TO authenticated
///   USING (auth.uid() = user_id);
///
/// -- Alle Profile lesen (z.B. für Swipe - hier ggf. eingeschränkten View nutzen)
/// CREATE POLICY "Users can read all public profiles"
///   ON profiles FOR SELECT TO authenticated
///   USING (true);
/// ```
class SupabaseDatabaseService {
  SupabaseDatabaseService(this._client);

  final SupabaseClient _client;

  User? get _currentUser => SupabaseService.currentUser;

  // =========================================================================
  // Profile (profiles-Tabelle)
  // =========================================================================

  /// Lädt das eigene Profil aus der Supabase-Datenbank.
  ///
  /// Es werden nur die für die App benötigten Spalten selektiert; sensible
  /// Felder wie location_lat/location_lng bleiben in der Regel serverseitig.
  Future<UserProfile?> fetchOwnProfile() async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    // Retry: Ein transienter Netzfehler darf das Profil nicht leer lassen
    // (Name, Bio usw. würden nach Neuinstallation sonst fehlen). Ein
    // sauberes "keine Zeile" (Account serverseitig gelöscht) wird NICHT
    // retryed, sondern direkt zurückgegeben.
    //
    // ZWEISTUFIG (v0.8.1-Fix "App merkt sich nichts mehr"): Zuerst MIT
    // `photos` (Migration 077); schlägt das fehl, wird OHNE diese Spalte
    // geladen. Eine fehlende neue Spalte darf NIE das komplette Profil
    // leeren (Name/Bio/Theme wären sonst nach App-Start weg).
    Object? lastError;
    const columnsWithPhotos =
        'user_id, name, gender, gender_preferences, birth_date, bio, '
        'interests, photos, personality_type, max_distance_km, '
        'age_range_min, age_range_max, smoking, alcohol, drugs, '
        'is_verified, is_location_suspicious, city, state, country, '
        'intro_text, intro_audio_path, location_lat, location_lng, '
        'created_at, updated_at, music_liked, music_disliked';
    const columnsWithoutPhotos =
        'user_id, name, gender, gender_preferences, birth_date, bio, '
        'interests, personality_type, max_distance_km, age_range_min, '
        'age_range_max, smoking, alcohol, drugs, is_verified, '
        'is_location_suspicious, city, state, country, intro_text, '
        'intro_audio_path, location_lat, location_lng, created_at, '
        'updated_at, music_liked, music_disliked';
    for (final columns in [columnsWithPhotos, columnsWithoutPhotos]) {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        try {
          final response = await _client
              .from('profiles')
              .select(columns)
              .eq('user_id', userId)
              .maybeSingle();

          if (response == null) return null;

          // REST-Antwort (snake_case) in das lokale JSON-Format (camelCase)
          // mappen – UserProfile.fromJson erwartet das lokale Format und
          // würde sonst (z. B. fehlendes "id") eine Exception werfen.
          final prefs =
              (response['gender_preferences'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              [];
          final allSelected =
              prefs.length >= kAllGenderValues.length &&
              kAllGenderValues.every(prefs.contains);
          final mapped = <String, dynamic>{
            'id': response['user_id'],
            'name': response['name'],
            'bio': response['bio'],
            'interests': response['interests'],
            'photos': response['photos'],
            'gender': response['gender'],
            'genderPreference': allSelected || prefs.isEmpty
                ? 'all'
                : prefs.first,
            // PostgREST liefert DATE als "YYYY-MM-DD"-String –
            // DateTime.tryParse versteht das Format.
            'birthDate': response['birth_date'] == null
                ? null
                : response['birth_date'] as String,
            'personalityType': response['personality_type'],
            'location_lat': response['location_lat'],
            'location_lng': response['location_lng'],
            'is_verified': response['is_verified'],
            'is_location_suspicious': response['is_location_suspicious'],
            'city': response['city'] ?? '',
            'state': response['state'],
            'country': response['country'] ?? 'Deutschland',
            'introText': response['intro_text'] ?? '',
            'introAudioPath': response['intro_audio_path'],
            'smoking': response['smoking'],
            'alcohol': response['alcohol'],
            'drugs': response['drugs'],
            'music_liked': response['music_liked'],
            'music_disliked': response['music_disliked'],
          };
          return UserProfile.fromJson(mapped);
        } catch (e) {
          debugPrint(
            '[DB] Profil-Fetch (Spaltensatz mit photos=${columns == columnsWithPhotos}) fehlgeschlagen: $e',
          );
          lastError = e;
        }
      }
    }
    throw lastError ?? StateError('fetchOwnProfile fehlgeschlagen');
  }

  /// Lädt die serverseitig gespiegelten Präferenzen des eigenen Profils
  /// (Entfernung, Altersspanne, Geschlechts-Filter, "Ich suche",
  /// Bundesland, Ort). Wird nach Login/Session-Restore genutzt, damit
  /// nach einer Neuinstallation KEINE Präferenz verloren geht.
  ///
  /// Mit Fallback: Fehlt die erweiterte Auswahl eine Spalte (z. B.
  /// `theme_name` aus Migration 071 noch nicht eingespielt), wird die
  /// Kern-Migration-066-Auswahl ohne `theme_name` geladen - die
  /// Präferenz-Wiederherstellung hängt nicht an der neuesten Migration.
  Future<Map<String, dynamic>?> fetchOwnPreferences() async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    // Vierstufig (v0.8.1/v0.9.1): Der ausgewachsenste Spaltensatz zuerst,
    // bei Fehler jeweils WITHOUT die neuesten Spalten weiterprobieren. Eine
    // fehlende Migration darf nie die GESAMTE Präferenz-Wiederherstellung
    // (inkl. Theme) auslöschen. WICHTIG: Die erste Stufe muss ALLE
    // Radius-Felder enthalten (max_distance_km + distance_filter_mode +
    // preferred_state) - sonst bleibt der Modus (Km/Bundesland/Land) beim
    // Restore still auf dem Default (v0.9.1-Fix).
    for (final columns in const [
      'max_distance_km, age_range_min, age_range_max, '
          'gender_preferences, relationship_type, preferred_state, city, '
          'distance_filter_mode, theme_name',
      'max_distance_km, age_range_min, age_range_max, '
          'gender_preferences, relationship_type, preferred_state, city, '
          'theme_name',
      'max_distance_km, age_range_min, age_range_max, '
          'gender_preferences, city, distance_filter_mode',
      'max_distance_km, age_range_min, age_range_max, '
          'gender_preferences, city',
    ]) {
      try {
        return await _fetchOwnPreferencesRaw(columns);
      } catch (e) {
        debugPrint(
          '[DB] Präferenz-Fetch (Spaltensatz) fehlgeschlagen, '
          'Fallback-Stufe: $e',
        );
      }
    }
    // Letzte Stufe ist bereits probiert - fehlgeschlagen (Rechte/Netz).
    throw StateError(
      'fetchOwnPreferences: alle Fallback-Stufen fehlgeschlagen',
    );
  }

  Future<Map<String, dynamic>?> _fetchOwnPreferencesRaw(String columns) async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('profiles')
        .select(columns)
        .eq('user_id', userId)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  /// Lädt alle serverseitig gespiegelten Präferenzen des eigenen Profils
  /// (siehe [fetchOwnPreferences]). Wirft bei Fehler - der Aufrufer
  /// entscheidet über Retry/Fallback.
  Future<Map<String, dynamic>?> fetchOwnPreferencesWithRetry({
    int attempts = 2,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      try {
        final prefs = await fetchOwnPreferences().timeout(
          const Duration(seconds: 8),
        );
        return prefs;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('fetchOwnPreferences fehlgeschlagen');
  }

  // =========================================================================
  // Profilbild-Einspruch (v0.8.1, Migration 079)
  // =========================================================================

  /// Reicht ein abgelehntes Profilbild zur manuellen Prüfung ein
  /// (Bild liegt bereits unter {uid}/appeals/ im Storage).
  Future<void> submitPhotoAppeal({
    required String path,
    required String label,
    required double score,
  }) async {
    await _client.rpc(
      'submit_photo_appeal',
      params: {'p_path': path, 'p_label': label, 'p_score': score},
    );
  }

  /// Eigener Einspruchs-Status (pending/approved/rejected) oder null.
  Future<Map<String, dynamic>?> getMyPhotoAppeal() async {
    try {
      final res = await _client.rpc('get_my_photo_appeal');
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('[DB] getMyPhotoAppeal fehlgeschlagen: $e');
      return null;
    }
  }

  /// Entscheidung quittieren (nach Anzeige/Finalisierung).
  Future<void> acknowledgePhotoAppeal(String id) async {
    try {
      await _client.rpc('acknowledge_photo_appeal', params: {'p_id': id});
    } catch (e) {
      debugPrint('[DB] acknowledgePhotoAppeal fehlgeschlagen: $e');
    }
  }

  /// Admin: alle Einsprüche listen.
  Future<List<Map<String, dynamic>>> adminListPhotoAppeals() async {
    final res = await _client.rpc('admin_list_photo_appeals');
    return List<Map<String, dynamic>>.from(res as List<dynamic>);
  }

  /// Admin: Einspruch freigeben/ablehnen.
  Future<void> adminDecidePhotoAppeal({
    required String id,
    required bool approve,
  }) async {
    await _client.rpc(
      'admin_decide_photo_appeal',
      params: {'p_id': id, 'p_approve': approve},
    );
  }

  // =========================================================================
  // Transit Spark (v0.9.0, Migration 081)
  // =========================================================================

  /// "Blicke getauscht": frische Encounter-Tokens + 1-3 Merkmal-Tags
  /// senden. Match = beidseitiges Signal MIT gemeinsamem Merkmal
  /// (Bestandspipeline erzeugt den Funke), sonst 45 Minuten vorgehalten.
  Future<Map<String, dynamic>> matchProximitySpark({
    required List<String> tokens,
    required List<String> tags,
    required String mode,
    List<String> selfTags = const [],
    String? selfNote,
  }) async {
    // Fallback-Kette (v0.9.0/091/097): Der Server kann je nach
    // Migrationsstand die 5-Parameter- (091, +self_note), 4-Parameter-
    // (084), 3-Parameter- (082) oder 1-Parameter- (081) Signatur haben.
    // PostgREST matcht nach benannten Argumenten - ein Aufruf mit zu
    // vielen Parametern scheitert mit PGRST202. Zusaetzlich existierten
    // zeitweise MEHRERE Überladungen gleichzeitig (alte Signaturen wurden
    // nie gedroppt, erst 097) - dann antwortet PostgREST mit PGRST203
    // ("could not choose the best candidate"). Beides bedeutet: eine
    // Stufe absteigen.
    // p_self_note wird IMMER mitgeschickt (ggf. leer - serverseitig
    // nullif), damit der 5-Parameter-Aufruf auf 091er-Servern eindeutig
    // genau eine Überladung trifft.
    final note = selfNote?.trim() ?? '';
    final attempts = <Map<String, dynamic>>[
      {
        'p_tokens': tokens,
        'p_tags': tags,
        'p_mode': mode,
        'p_self_tags': selfTags,
        'p_self_note': note,
      },
      {
        'p_tokens': tokens,
        'p_tags': tags,
        'p_mode': mode,
        'p_self_tags': selfTags,
      },
      {'p_tokens': tokens, 'p_tags': tags, 'p_mode': mode},
      {'p_tokens': tokens},
    ];
    Object? lastError;
    for (final params in attempts) {
      try {
        final res = await _client.rpc('match_proximity_spark', params: params);
        return Map<String, dynamic>.from(res);
      } catch (e) {
        lastError = e;
        // Echte Fachfehler (Rate-Limit, Jugendschutz etc.) nicht
        // verschlucken: Nur bei Signatur-Fehlmatch eine Stufe absteigen.
        if (!isRpcSignatureMismatch(e)) rethrow;
      }
    }
    throw lastError ?? StateError('match_proximity_spark fehlgeschlagen');
  }

  /// True, wenn ein RPC-Fehler ein Signatur-Fehlmatch ist (eine Stufe
  /// absteigen), statt eines echten Fachfehlers (sofort weiterwerfen):
  /// - PGRST202 / "could not find the function" = Signatur fehlt
  ///   (Server älter als der Client).
  /// - PGRST203 / "could not choose the best candidate" = MEHRERE
  ///   Überladungen matchen (alte Signaturen wurden nie gedroppt,
  ///   erst Migration 097) - ebenfalls absteigen statt aufgeben.
  /// Reine Funktion (testbar).
  static bool isRpcSignatureMismatch(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('pgrst203') ||
        text.contains('could not find the function') ||
        text.contains('could not choose the best candidate') ||
        text.contains('function public.match_proximity_spark');
  }

  // =========================================================================
  // Transit Soft-Ping (v0.9.1, Migration 083)
  // =========================================================================

  /// Radar aktiv: eigenes Token serverseitig hinterlegen (Heartbeat).
  Future<void> transitPresenceHeartbeat(String token) async {
    await _client.rpc('transit_presence_heartbeat', params: {'p_token': token});
  }

  /// Radar aus: eigenes Token entfernen (Privacy).
  Future<void> transitPresenceLeave() async {
    await _client.rpc('transit_presence_leave');
  }

  /// Soft-Ping senden (1x pro Encounter-Token, 48 h Gueltigkeit).
  Future<void> sendSoftPing({
    required String token,
    required String messageKey,
    String? customLine,
  }) async {
    await _client.rpc(
      'send_soft_ping',
      params: {
        'p_token': token,
        'p_message_key': messageKey,
        'p_custom_line': customLine,
      },
    );
  }

  /// Eigene offene Soft-Pings (Empfaenger-Sicht).
  Future<List<Map<String, dynamic>>> listMySoftPings() async {
    final res = await _client.rpc('list_my_soft_pings');
    return List<Map<String, dynamic>>.from(res as List<dynamic>);
  }

  /// Soft-Ping annehmen -> Funke ueber Bestandspipeline.
  Future<Map<String, dynamic>> acceptSoftPing(String id) async {
    final res = await _client.rpc('accept_soft_ping', params: {'p_id': id});
    return Map<String, dynamic>.from(res);
  }

  /// Aktualisiert das eigene Profil in der Supabase-Datenbank.
  ///
  /// Robust gegenüber unvollständigen Migrationen (v0.8.1): Liefert
  /// PostgREST "Could not find the 'X' column", wird X aus dem Body
  /// entfernt und erneut geschrieben - EINE fehlende Spalte (z. B.
  /// `photos` ohne Migration 077) darf nie den GESAMTEN Schreibvorgang
  /// auslöschen (Name/Bio/Präferenzen wären sonst alle verloren).
  Future<void> updateOwnProfile(Map<String, dynamic> updates) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    var body = Map<String, dynamic>.from(updates);
    for (var attempt = 0; attempt < 8 && body.isNotEmpty; attempt++) {
      try {
        await _client.from('profiles').update(body).eq('user_id', userId);
        return;
      } catch (e) {
        final missing = _missingColumnFromError(e);
        if (missing == null || !body.containsKey(missing)) rethrow;
        body = Map<String, dynamic>.from(body)..remove(missing);
      }
    }
  }

  /// Extrahiert aus einem PostgREST-Fehler die fehlende Spalte. Zwei
  /// Muster:
  ///  - "Could not find the 'photos' column of 'profiles' in the schema
  ///    cache" (PGRST204, neuere PostgREST-Versionen)
  ///  - "column profiles.photos does not exist" (Postgres 42703)
  static String? _missingColumnFromError(Object e) {
    final text = e.toString();
    final m = RegExp(
      r"Could not find the '([A-Za-z0-9_]+)' column",
    ).firstMatch(text);
    if (m != null) return m.group(1);
    final m2 = RegExp(
      r'column\s+([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\s+does not exist',
    ).firstMatch(text);
    return m2?.group(2);
  }

  /// Lädt die Setup-Flags des eigenen Profils (serverseitige Quelle,
  /// damit die Einrichtung nach Neuinstallation nicht erneut erscheint).
  ///
  /// Die SELECT-Liste enthält bewusst AUCH die gespiegelten Präferenz-/
  /// Anzeige-Spalten: [updateSetupFlagsAndVerify] liest zur Kontrolle
  /// gezielt nur die geschriebenen Schlüssel zurück, der Auth-Sync nutzt
  /// zusätzlich `dating_hour_intro_seen` + `theme_name` (Migration 071).
  ///
  /// Mit Fallback: Fehlen die 071-Spalten auf dem Server (unvollständige
  /// Migration), liefern wir trotzdem die Kern-Flags zurück - die
  /// Einrichtungs-/Intro-Logik hängt nicht an der neuesten Migration.
  Future<Map<String, dynamic>?> fetchSetupFlags() async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    try {
      return await _fetchSetupFlagsRaw(
        'one_time_settings_completed, community_guidelines_accepted, '
        'personality_test_completed, onboarding_done, '
        'dating_hour_intro_seen, theme_name, ui_prefs, '
        'paused, habits_dealbreaker',
      );
    } catch (e) {
      debugPrint(
        '[DB] Flags-Fetch (voll) fehlgeschlagen, Fallback auf '
        'Kern-Flags: $e',
      );
    }
    return _fetchSetupFlagsRaw(
      'one_time_settings_completed, community_guidelines_accepted, '
      'personality_test_completed, onboarding_done',
    );
  }

  Future<Map<String, dynamic>?> _fetchSetupFlagsRaw(String columns) async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('profiles')
        .select(columns)
        .eq('user_id', userId)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  /// [fetchSetupFlags] mit Retry: Nach Neuinstallation/Login entscheidet
  /// dieses Ergebnis, ob die Einrichtung erneut erscheint. Ein transientes
  /// Netzwerk-Timeout (Handy-Netz, kalte TLS-Verbindung) darf die Flags
  /// nicht still als "nicht abgeschlossen" erscheinen lassen.
  ///
  /// Liefert `null`, wenn alle Versuche scheitern (Aufrufer fällt auf den
  /// lokalen Stand zurück).
  Future<Map<String, dynamic>?> fetchSetupFlagsWithRetry({
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(Duration(seconds: 1 * i));
      }
      try {
        final flags = await fetchSetupFlags().timeout(
          const Duration(seconds: 8),
        );
        if (flags != null) return flags;
        // Sauberes "keine Zeile" (Profil gelöscht): nicht retryen.
        return null;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('fetchSetupFlags fehlgeschlagen');
  }

  /// Schreibt Setup-Flags und VERIFIZIERT das Ergebnis per Zurücklesen.
  ///
  /// Hintergrund (Bug "Einrichtung erscheint nach Neuinstallation erneut"):
  /// Ein PostgREST-UPDATE gilt auch bei 0 betroffenen Zeilen (z. B. RLS-
  /// Strohfeuer, transientes Netzproblem) als erfolgreich - der Server
  /// behält `false`, ohne dass der Client einen Fehler sieht. Erst der
  /// Read-Back macht einen stillen Fehlschlag erkennbar. Bei Abweichung
  /// wird bis zu [attempts] mal erneut geschrieben.
  ///
  /// Der Vergleich ist TYPENSICHER: PostgREST liefert Listen als
  /// `List<dynamic>`, der Client schickt `List<String>` - ein nackter
  /// `!=`-Vergleich schlug für Spalten wie `gender_preferences` IMMER
  /// fehl (3 unnötige Schreibversuche + Fehlalarm beim Aufrufer, obwohl
  /// geschrieben war).
  ///
  /// Rückgabe: true = Flags stehen serverseitig wie gewünscht. Schlägt
  /// NUR die Verifikations-LESE fehl (Schema/Netz), gilt der Schreibvorgang
  /// als erfolgt (true, mit Log) - ein Leseproblem ist kein Schreibproblem.
  Future<bool> updateSetupFlagsAndVerify(
    Map<String, dynamic> flags, {
    int attempts = 3,
  }) async {
    Object? writeError;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(Duration(seconds: 1 * i));
      }
      writeError = null;
      try {
        await updateOwnProfile(Map<String, dynamic>.from(flags));
      } catch (e) {
        writeError = e;
        continue; // Schreiben fehlgeschlagen -> erneut versuchen.
      }

      // Verifikation liest gezielt NUR die geschriebenen Schlüssel zurück
      // (statt der vollen Flags-Zeile) - fehlt auf dem Server eine einzelne
      // ANDERE Spalte (unvollständige Migration), blockiert das nicht
      // länger jeden Schreibvorgang.
      Map<String, dynamic>? readBack;
      try {
        final raw = await _client
            .from('profiles')
            .select(flags.keys.join(', '))
            .eq('user_id', _currentUser?.id ?? '')
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        readBack = raw == null ? null : Map<String, dynamic>.from(raw);
      } catch (e) {
        // Schreiben war erfolgreich; nur die Kontrolle ist nicht möglich
        // (fehlende Spalte bei unvollständiger Migration / Netz). Nicht
        // fälschlich als Schreibfehler melden.
        debugPrint(
          '[DB] Verify-Read nicht möglich (Schreiben galt als '
          'erfolgreich): $e',
        );
        return true;
      }

      if (readBack == null) continue; // Zeile weg? Erneut versuchen.
      var allMatch = true;
      for (final entry in flags.entries) {
        if (!_valuesMatch(readBack[entry.key], entry.value)) {
          allMatch = false;
        }
      }
      if (allMatch) return true;
    }
    if (writeError != null) {
      debugPrint('[DB] updateSetupFlagsAndVerify Schreibfehler: $writeError');
    }
    return false;
  }

  /// Typensicherer Vergleich PostgREST-Antwort vs. geschickter Wert.
  static bool _valuesMatch(dynamic serverValue, dynamic sentValue) {
    if (serverValue is List && sentValue is List) {
      if (serverValue.length != sentValue.length) return false;
      final a = serverValue.map((e) => e.toString()).toList()..sort();
      final b = sentValue.map((e) => e.toString()).toList()..sort();
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    if (serverValue is num && sentValue is num) {
      return serverValue.toDouble() == sentValue.toDouble();
    }
    return serverValue == sentValue;
  }

  // =========================================================================
  // Geraete & Sitzungen ("Wo bin ich eingeloggt?")
  // =========================================================================

  /// Alle registrierten Geraete des eigenen Kontos (neueste zuerst).
  ///
  /// Jede Zeile wurde vom Geraet selbst angelegt (RLS: nur eigene Zeilen).
  /// Fehler werden mit bereinigter Ursache geworfen - der Geraete-Screen
  /// zeigt sie an, damit "Migration fehlt" vs. "RLS" vs. "Netz"
  /// unterscheidbar sind.
  Future<List<Map<String, dynamic>>> fetchOwnDevices() async {
    try {
      final response = await _client
          .from('auth_devices')
          .select()
          .order('last_seen_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw AppException(_explainDeviceError(e));
    }
  }

  /// Registriert/aktualisiert das aktuelle Geraet (Upsert auf
  /// user_id + device_id, siehe Migration 071).
  Future<void> upsertOwnDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? appVersion,
    String? deviceModel,
  }) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    try {
      await _client.from('auth_devices').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': appVersion,
        'device_model': deviceModel,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,device_id');
    } catch (e) {
      throw AppException(_explainDeviceError(e));
    }
  }

  /// Übersetzt PostgREST-/Netzwerkfehler der Geraete-Tabelle in kurze,
  /// handlungsorientierte Hinweise (keine Secrets, keine Lang-URLs).
  static String _explainDeviceError(Object e) {
    final text = e.toString().toLowerCase();
    // PGRST205: "Could not find the table ... schema cache".
    if (text.contains('pgrst205') ||
        (text.contains('relation') && text.contains('does not exist')) ||
        text.contains('schema cache')) {
      return 'Die Geräte-Tabelle existiert auf dem Server nicht. '
          'Bitte Migration 071 (auth_devices) in Supabase einspielen '
          'und die App neu starten.';
    }
    // 42501: RLS hat den Zugriff verweigert.
    if (text.contains('42501') || text.contains('row-level security')) {
      return 'Der Server hat den Zugriff auf die Geräte-Liste verweigert '
          '(RLS). Bitte Migration 071 vollständig einspielen '
          '(inkl. Policies).';
    }
    if (text.contains('20 geraete') || text.contains('maximal 20')) {
      return 'Maximal 20 Geräte pro Konto registrierbar. Melde dich von '
          'nicht mehr genutzten Geräten ab und entferne deren Einträge.';
    }
    if (text.contains('duplicate key') || text.contains('23505')) {
      return 'Dieses Gerät ist bereits registriert (Konflikt beim '
          'Speichern). Bitte erneut versuchen.';
    }
    if (text.contains('jwt') || text.contains('401')) {
      return 'Sitzung abgelaufen. Bitte neu einloggen.';
    }
    if (text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('connection')) {
      return 'Keine Verbindung zum Server. Bitte Netz prüfen und erneut '
          'versuchen.';
    }
    return 'Serverfehler bei der Geräte-Liste. Bitte später erneut '
        'versuchen.';
  }

  /// Loescht ein einzelnes eigenes Geraet aus der Liste.
  Future<void> deleteOwnDevice(String deviceId) async {
    await _client.from('auth_devices').delete().eq('device_id', deviceId);
  }

  /// Loescht alle GERAETE-Zeilen des eigenen Kontos AUSSER [keepDeviceId].
  ///
  /// Wird nach `signOut(scope: others)` aufgerufen: Die anderen Sitzungen
  /// sind dann serverseitig invalidiert, ihre Zeilen wandern aus der Liste.
  Future<void> deleteOtherOwnDevices(String keepDeviceId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    await _client
        .from('auth_devices')
        .delete()
        .eq('user_id', userId)
        .neq('device_id', keepDeviceId);
  }

  /// Holt öffentliche Profile anderer Nutzer (v0.9.0: RPC statt View -
  /// löst den security_definer_view-Befund auf). Whitelist + Jugendschutz
  /// serverseitig (Migration 080).
  Future<List<Map<String, dynamic>>> fetchPublicProfiles({
    int limit = 20,
  }) async {
    // Die RPC-Variante arbeitet auf ID-Listen; ohne Quell-IDs gibt es
    // hier nichts Sinnvolles - die Methode ist historisch ungenutzt und
    // liefert bewusst eine leere Liste statt einer DB-Weitabfrage.
    return [];
  }

  /// Holt ein einzelnes öffentliches Profil via RPC (v0.9.0, Migration
  /// 080 - Nachfolger der public_profiles-View). Null, wenn der Nutzer
  /// nicht existiert oder altersseitig nicht sichtbar ist.
  Future<Map<String, dynamic>?> fetchPublicProfile(String userId) async {
    final response = await _client.rpc(
      'get_public_profile',
      params: {'p_user_id': userId},
    );
    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  /// Abgerundete Distanz in km vom eigenen Profil zum Zielprofil
  /// (RPC `profile_distance_km`, 5-km-Schritte). Null ohne Koordinaten.
  Future<double?> fetchDistanceKm(String userId) async {
    try {
      final result = await _client.rpc(
        'profile_distance_km',
        params: {'p_other': userId},
      );
      if (result is num) return result.toDouble();
      return null;
    } catch (_) {
      // Distanz ist optional - Fehler still ignorieren.
      return null;
    }
  }

  // =========================================================================
  // Admin-Funktionen (alle RPCs pruefen is_current_user_admin serverseitig,
  // fail-closed - der Client-Check ist nur Kosmetik).
  // =========================================================================

  Future<List<Map<String, dynamic>>> _adminList(String rpc) async {
    final response = await _client.rpc(rpc);
    return List<Map<String, dynamic>>.from(response as List<dynamic>);
  }

  /// Alle Nutzer-Meldungen ("Nutzer melden").
  Future<List<Map<String, dynamic>>> fetchUserReports() =>
      _adminList('admin_list_user_reports');

  /// Meldung als bearbeitet markieren.
  Future<void> resolveUserReport(String reportId) async {
    await _client.rpc(
      'admin_resolve_user_report',
      params: {'p_report_id': reportId},
    );
  }

  /// Bug-Reports (DB-Kopie der per Email versendeten Reports).
  Future<List<Map<String, dynamic>>> fetchBugReports() =>
      _adminList('admin_list_bug_reports');

  /// Ausstehende Verifizierungen (Video wartet auf Freigabe).
  Future<List<Map<String, dynamic>>> fetchPendingVerifications() =>
      _adminList('admin_list_pending_verifications');

  /// Auto-Freigaben zur nachträglichen Stichprobe (v0.9.0,
  /// Manipulationsschutz): Wer das Badge per KI-Triage bekam, bleibt
  /// mit Video in dieser Liste, bis der Support bestätigt/entzogen
  /// hat. Fehlt die RPC (Migration 120 nicht deployed), wirft der
  /// Aufruf - der Aufrufer fängt das ab (Fail-open der Stichprobe).
  Future<List<Map<String, dynamic>>> fetchAutoVerifications() =>
      _adminList('admin_list_auto_verifications');

  /// Gebannte Email-Adressen (Anzeige).
  Future<List<Map<String, dynamic>>> fetchBannedEmails() =>
      _adminList('admin_list_banned_emails');

  // =========================================================================

  /// Holt Matches des eingeloggten Nutzers.
  Future<List<Map<String, dynamic>>> fetchMatches() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('matches')
        .select()
        .or('user_one_id.eq.$userId,user_two_id.eq.$userId');

    return List<Map<String, dynamic>>.from(response);
  }

  /// Legt ein Match an (beidseitig).
  ///
  /// HINWEIS (Audit K3): Der direkte Client-INSERT in `matches` ist seit
  /// Migration 040 serverseitig gesperrt – Matches entstehen ausschließlich
  /// über gegenseitige Likes (create_match_if_mutual) bzw. Dating-Hour.
  /// Diese Methode bleibt für den Demo-/Fallback-Pfad; am Server schlägt sie
  /// ohne bestehende Gegenseitigkeit fehl (RLS).
  Future<void> createMatch(String peerId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');
    if (!isValidPeerId(peerId)) throw AppException('Ungültiger Peer.');

    final userOneId = userId.compareTo(peerId) < 0 ? userId : peerId;
    final userTwoId = userId.compareTo(peerId) < 0 ? peerId : userId;

    await _client.from('matches').insert({
      'user_one_id': userOneId,
      'user_two_id': userTwoId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Prüft, ob eine E-Mail-Adresse auf der Plattform gesperrt ist
  /// (Migration 045: public.banned_emails). Liefert den hinterlegten
  /// Sperr-Grund, falls vorhanden. Die RPC ist pre-auth (anon) aufrufbar
  /// und serverseitig gedrosselt.
  Future<({bool banned, String? reason})> checkEmailBanStatus(
    String email,
  ) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return (banned: false, reason: null);
    final result = await _client.rpc(
      'check_email_ban_status',
      params: {'p_email': normalized},
    );
    if (result is Map) {
      return (
        banned: result['banned'] == true,
        reason: result['reason'] as String?,
      );
    }
    return (banned: false, reason: null);
  }

  // =========================================================================
  // Likes (likes-Tabelle)
  // =========================================================================

  /// Like vergeben. Verwendet die serverseitige RPC [create_match_if_mutual],
  /// damit Like-Insert, Mutual-Check und Match-Insert atomar ablaufen.
  ///
  /// Rückgabe: Map mit 'is_match' (bool) und 'match_id' (int?).
  Future<Map<String, dynamic>?> insertLike(String likedUserId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    final result = await _client.rpc(
      'create_match_if_mutual',
      params: {'p_liked_user_id': likedUserId},
    );

    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return result.cast<String, dynamic>();
    }
    return null;
  }

  /// Like zurückziehen.
  Future<void> deleteLike(String likedUserId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    await _client
        .from('likes')
        .delete()
        .eq('user_id', userId)
        .eq('liked_user_id', likedUserId);
  }

  // =========================================================================
  // Blockieren (Bot-/Spam-Schutz, Migration 043)
  // =========================================================================

  /// Blockiert einen Nutzer serverseitig (RPC `block_user`).
  ///
  /// Wirkung: Löscht Likes in beide Richtungen und bestehende Matches;
  /// künftige Likes/Matches/Dating-Hour-/Random-Chat-Paarungen mit diesem
  /// Nutzer werden serverseitig verhindert. Dauerhaft bis zum Unblock.
  Future<void> blockUser(String blockedUserId) async {
    if (!isValidPeerId(blockedUserId)) {
      throw AppException('Ungültiger Nutzer.');
    }
    await _client.rpc('block_user', params: {'p_blocked': blockedUserId});
  }

  /// Hebt eine Blockierung wieder auf (RPC `unblock_user`).
  Future<void> unblockUser(String blockedUserId) async {
    if (!isValidPeerId(blockedUserId)) {
      throw AppException('Ungültiger Nutzer.');
    }
    await _client.rpc('unblock_user', params: {'p_blocked': blockedUserId});
  }

  /// Liste der von mir blockierten Nutzer-IDs (für Einstellungen/Feedback).
  Future<List<String>> fetchBlockedUserIds() async {
    final response = await _client.from('blocked_users').select('blocked');
    return (response as List<dynamic>)
        .map((row) => (row as Map)['blocked'] as String)
        .toList();
  }

  /// "Meine Likes" — Profile, die ich geliked habe (v0.9.0: zweistufiger
  /// Fetch statt Embedded-Join auf die View - gleiche Ergebnis-Form:
  /// flaches Profil + 'liked_at'; Likes ohne sichtbares Profil (z. B.
  /// altersseitig) fallen weg, wie beim bisherigen INNER-Join).
  Future<List<Map<String, dynamic>>> fetchMyLikes() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final rows = await _client
        .from('likes')
        .select('liked_user_id, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final likeRows = List<Map<String, dynamic>>.from(rows as List<dynamic>);
    final ids = likeRows
        .map((r) => r['liked_user_id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return [];

    final profiles = await _fetchPublicProfilesByIds(ids);
    final byId = {for (final p in profiles) p['user_id'] as String: p};

    return likeRows.where((r) => byId.containsKey(r['liked_user_id'])).map((
      row,
    ) {
      return {
        ...byId[row['liked_user_id']] as Map<String, dynamic>,
        'liked_at': row['created_at'],
      };
    }).toList();
  }

  /// "Likes für mich" — Profile, die mich geliked haben (v0.9.0: siehe
  /// [fetchMyLikes] - identisches Antwort-Shape wie der frühere
  /// Embedded-Join auf die View).
  Future<List<Map<String, dynamic>>> fetchLikesForMe() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final rows = await _client
        .from('likes')
        .select('user_id, created_at')
        .eq('liked_user_id', userId)
        .order('created_at', ascending: false);

    final likeRows = List<Map<String, dynamic>>.from(rows as List<dynamic>);
    final ids = likeRows
        .map((r) => r['user_id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return [];

    final profiles = await _fetchPublicProfilesByIds(ids);
    final byId = {for (final p in profiles) p['user_id'] as String: p};

    return likeRows.where((r) => byId.containsKey(r['user_id'])).map((row) {
      return {
        ...byId[row['user_id']] as Map<String, dynamic>,
        'liked_at': row['created_at'],
      };
    }).toList();
  }

  /// Batch-Whitelist-Fetch über den 080er-RPC (max. 200 IDs pro Call,
  /// bei mehr wird gestaffelt).
  Future<List<Map<String, dynamic>>> _fetchPublicProfilesByIds(
    List<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 200) {
      final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      final res = await _client.rpc(
        'get_public_profiles',
        params: {'p_ids': chunk},
      );
      if (res is List) {
        result.addAll(res.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    }
    return result;
  }

  // =========================================================================
  // Realtime (optional)
  // =========================================================================

  /// Hinweis: Supabase Realtime (Broadcast / PostgresChanges) hängt von der
  /// konkreten SDK-Version ab. Falls benötigt, den entsprechenden Channel-
  /// Listener direkt über `SupabaseService.client.channel(...)` aufsetzen.
}

/// Provider für den [SupabaseDatabaseService].
final supabaseDatabaseServiceProvider = Provider<SupabaseDatabaseService>((
  ref,
) {
  final client = SupabaseService.client;
  return SupabaseDatabaseService(client);
});
