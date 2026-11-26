// Repräsentiert ein Nutzerprofil in der App.
//
// Enthält die für Dating relevanten Felder. Fotos werden als Liste von
// (Mock-)Bild-Pfaden/URLs gespeichert. Der Blind Mode sorgt dafür, dass
// diese Fotos erst nach einem Match für andere sichtbar sind.

import 'package:thestia/models/profile/habitude_level.dart';
import 'package:thestia/utils/common/json_leser.dart';
import 'package:thestia/utils/location/age_calculator.dart';
import 'package:thestia/utils/location/distance_bucket.dart';

/// Verifikationszustand einer Person.
///
/// DREI Zustände, nicht zwei. Der Unterschied ist der Kern der
/// Anzeige: wer sich geprüft hat, aber die Freigabe noch nicht
/// bekommen hat, ist NICHT "nicht verifiziert" - er ist "wird
/// geprüft". Beides zu vermischen fährt zu zwei falschen Aussagen:
/// "Deine Verifizierung fehlt" (falsch, sie liegt vor) und
/// "Du bist nicht verifiziert" (falsch, die Prüfung läuft).
enum VerificationState {
  /// Kein Video eingereicht, keine Prüfung.
  unverified,

  /// Eingereicht, Prüfung läuft oder ausstehend.
  underReview,

  /// Freigegeben - manuell oder automatisch.
  verified;

  /// Ist der Vollzugang möglich? Nur bei [verified].
  bool get grantsFullAccess => this == VerificationState.verified;

  /// Liest den Zustand aus der öffentlichen Projektion.
  ///
  /// Erwartet wird `verification_state` (Migration 144). Fehlt das
  /// Feld - ältere Server, oder ein Aufruf, der die Projektion nicht
  /// nutzt -, wird auf [isVerified] zurückgefallen, damit das
  /// verifizierte Abzeichen nicht verloren geht.
  static VerificationState fromJson(
    Map<String, dynamic> json, {
    bool isVerified = false,
  }) {
    final raw = json['verification_state'];
    if (raw is String) {
      switch (raw) {
        case 'verified':
          return VerificationState.verified;
        case 'under_review':
          return VerificationState.underReview;
        case 'unverified':
          return VerificationState.unverified;
      }
    }
    return isVerified
        ? VerificationState.verified
        : VerificationState.unverified;
  }

  /// Liest den Zustand aus der Spalte `verification_status` der Tabelle
  /// `profiles` (Migration 144/155).
  ///
  /// Das ist ein anderes Format als die öffentliche Projektion: hier
  /// stehen die Rohwerte 'none', 'pending', 'pending_minor', 'approved',
  /// 'rejected' und 'auto'.
  ///
  /// Wichtig: der Status wird nur GELESEN. Ein 'rejected' ist für die
  /// Anzeige "nicht verifiziert" - die Meldung, dass die Verifizierung
  /// fehlt, ist damit korrekt; der Nutzer kann sie erneut einreichen.
  static VerificationState fromServerStatus(
    Object? status, {
    bool isVerified = false,
  }) {
    if (isVerified) return VerificationState.verified;
    if (status is String) {
      switch (status) {
        case 'pending':
        case 'pending_minor':
          return VerificationState.underReview;
        case 'approved':
        case 'auto':
          return VerificationState.verified;
      }
    }
    return VerificationState.unverified;
  }
}

class UserProfile {
  /// Eindeutige ID des Nutzers.
  final String id;

  /// Anzeigename.
  final String name;

  /// Geburtsdatum (berechnet das Alter dynamisch).
  final DateTime? birthDate;

  /// Kurze Biografie / Vorstellungstext.
  final String bio;

  /// Liste von Interessen (z. B. "Reisen", "Kochen").
  final List<String> interests;

  /// Liste von Foto-URLs bzw. lokalen Pfaden.
  final List<String> photos;

  /// Bundesland (für Filter nach Bundesland).
  final String? state;

  /// Wohnsitzland (z. B. "Deutschland", "Österreich").
  final String country;

  /// Distanz in km (Mock-Wert).
  final double distanceKm;

  /// Eigenes Geschlecht.
  final String? gender;

  /// Sexuelle Präferenz (auf welches Geschlecht man steht).
  final String genderPreference;

  /// Ergebnis des Persönlichkeitstests (z. B. "Abenteurer").
  final String? personalityResult;

  /// MBTI-Persönlichkeitstyp (z. B. "ENFP", "INFJ").
  final String? personalityType;

  /// Video-Vorstellung (optional, für Video-Swiping-Modus).
  final String? videoUrl;

  /// Audio-Vorstellung (optional, für Audio-Swiping-Modus).
  final String? audioUrl;

  /// Lieblingssong (optional, für Musik-Swiping-Modus).
  final String? favoriteSong;

  /// Lieblingsband/-künstler (optional, getrennt vom Song, Migration 119).
  final String? favoriteBand;

  /// Breitengrad des verifizierten Standorts (optional).
  final double? locationLat;

  /// Längengrad des verifizierten Standorts (optional).
  final double? locationLng;

  /// Nutzer wurde verifiziert.
  final bool isVerified;

  /// Dreistufiger Verifikationszustand (v0.10.0, Migration 144).
  ///
  /// Aus `is_verified` allein ist "wird geprüft" nicht ableitbar -
  /// dafür braucht es den Rohstatus aus der Projektion.
  final VerificationState verificationState;

  /// Standort des Nutzers wurde als verdächtig eingestuft.
  final bool isLocationSuspicious;

  /// Aktuelles Mood of the Day (optional, z. B. "happy").
  final String? mood;

  /// Kurze Text-Vorstellung für "Find your Match" (ohne Foto).
  final String introText;

  /// Storage-Pfad der Audio-Vorstellung für "Find your Match".
  /// Zugriff nur über die match-media-Edge-Function (signierte URL).
  final String? introAudioPath;

  /// Umgang mit Rauchen (beeinflusst den Find-your-Match-Algorithmus).
  final HabitudeLevel? smoking;

  /// Umgang mit Alkohol (beeinflusst den Find-your-Match-Algorithmus).
  final HabitudeLevel? alcohol;

  /// Umgang mit anderen Drogen (beeinflusst den Find-your-Match-Algorithmus).
  final HabitudeLevel? drugs;

  /// Musik-Genres, die der Nutzer mag (Slugs aus dem Katalog, Migration 074).
  final List<String> musicLiked;

  /// Musik-Genres, die der Nutzer explizit NICHT mag (negativer Score).
  final List<String> musicDisliked;

  /// Verbindungs-Score (0-100, serverseitig in get_find_match_candidates
  /// berechnet: Distanz + gemeinsame Interessen + Musik). Nur für
  /// Kandidaten-Objekte gesetzt, reiner Anzeige-Wert.
  final int? matchScore;

  /// Gewählter Geburtstags-Stil (classic/midnight/sage/rose/mono,
  /// Migration 115). Wirkt nur am Geburtstag (schick, nicht kitschig).
  final String birthdayStyle;

  /// True, wenn heute der Geburtstag ist (serverseitig als Boolean aus
  /// Tag/Monat berechnet - das Geburtsdatum selbst wird nie geleakt).
  /// Für das EIGENE Profil lokal aus birthDate berechnet.
  final bool birthdayToday;

  const UserProfile({
    required this.id,
    required this.name,
    this.birthDate,
    required this.bio,
    this.interests = const <String>[],
    this.photos = const <String>[],
    this.verificationState = VerificationState.unverified,
    this.state,
    this.country = 'Deutschland',
    this.distanceKm = 0,
    this.gender,
    this.genderPreference = 'all',
    this.personalityResult,
    this.personalityType,
    this.videoUrl,
    this.audioUrl,
    this.favoriteSong,
    this.favoriteBand,
    this.locationLat,
    this.locationLng,
    this.isVerified = false,
    this.isLocationSuspicious = false,
    this.mood,
    this.introText = '',
    this.introAudioPath,
    this.smoking,
    this.alcohol,
    this.drugs,
    this.musicLiked = const <String>[],
    this.musicDisliked = const <String>[],
    this.matchScore,
    this.birthdayStyle = 'classic',
    this.birthdayToday = false,
    this.createdAt,
  });

  /// Zeitpunkt, zu dem das Konto angelegt wurde.
  ///
  /// Wird für die Anzeige "neuer Account" gebraucht (siehe
  /// [isRecentlyCreated]). Die Spalte `created_at` liefern sowohl das
  /// eigene Profil als auch `get_public_profile` bereits mit - sie war
  /// nur nie im Modell abgelegt.
  ///
  /// Bewusst der Zeitpunkt des Kontos und nicht der Registrierung: das
  /// ist der für den Missbrauch relevante Zeitraum.
  final DateTime? createdAt;

  /// Ab wie vielen Tagen gilt ein Konto nicht mehr als neu.
  static const int recentAccountDays = 7;

  /// Ob das Konto jünger als [recentAccountDays] Tage ist.
  ///
  /// Ein Hinweis, kein Beweis: auch echte neue Nutzer fallen darunter.
  /// Er soll davor schützen, dass man dauerhaft von Accounts
  /// angeschrieben wird, die es gerade erst gibt. Ein exaktes Datum
  /// wäre zusätzlich ein Datenleck, deshalb wird nichts genauer
  /// angezeigt als "neu".
  ///
  /// Ohne [createdAt] (Server liefert die Spalte nicht) gilt das Konto
  /// bewusst NICHT als neu: eine falsche Entwarnung wäre schädlicher
  /// als ein fehlender Hinweis.
  bool get isRecentlyCreated {
    final created = createdAt;
    if (created == null) return false;
    final age = DateTime.now().toUtc().difference(created.toUtc());
    return age.inDays < recentAccountDays;
  }

  /// True, wenn das Geburtsdatum auf heute fällt (Tag/Monat, lokal für
  /// das eigene Profil; fremde Profile liefern birthdayToday serverseitig).
  static bool isBirthdayToday(DateTime? birthDate) {
    if (birthDate == null) return false;
    final now = DateTime.now();
    return birthDate.month == now.month && birthDate.day == now.day;
  }

  /// Berechnet das Alter dynamisch basierend auf dem aktuellen Datum.
  ///
  /// Liefert null, wenn kein birthDate gesetzt ist.
  int? get age {
    final calculatedAge = calculateAge(birthDate);
    // Audit H-Log: Geburtsdatum ist PII und wird NICHT geloggt
    // (auch nicht im Debug - der Getter läuft im Hot Path).
    return calculatedAge;
  }

  /// Erzeugt ein [UserProfile] aus der public_profiles-View.
  ///
  /// Mappt `age` → birthDate (rückgerechnet). Alle sensiblen Felder sind
  /// in der View nicht enthalten und werden mit Defaults belegt.
  ///
  /// v0.10.0: Die View liefert keine Koordinaten mehr. Bis Migration 138
  /// standen hier `lat_approx`/`lng_approx` (1 Dezimal, ~11 km) - sie
  /// wurden auf locationLat/locationLng abgebildet und damit in Profile
  /// geschrieben, die man in die Lokalität anderer brachte. Die
  /// Zuordnungen sind bewusst entfernt und nicht auf null gesetzt: ein
  /// stillschweigend befülltes locationLat sieht nach Standort aus und
  /// wäre es nicht.
  factory UserProfile.fromPublicView(Map<String, dynamic> json) {
    // Alter rückrechnen: ungefähres Geburtsjahr.
    //
    // BEFUND (22.11.2026, Fuzzing): `json['age'] as int?` wirft, wenn
    // der Server eine Zahl mit Nachkommastellen oder einen Text
    // liefert. Das öffentliche Profil kommt vom SERVER - ein Fehler
    // dort darf die App nicht abstürzen lassen.
    final age = intOf(json, ['age']);
    final birthDate = age != null
        ? DateTime(DateTime.now().year - age, 1, 1)
        : null;

    // Verifikationsstatus (v0.10.0, Migration 144).
    //
    // BUG (Security-Audit 22.10.2026): die öffentliche Projektion
    // liefert is_verified und verification_state mit - sie wurden hier
    // aber nie gelesen. Dadurch zeigte die App bei fremden Profilen
    // nie das Verifikations-Abzeichen, obwohl der Server die Information
    // hatte. Die Modus-Sperre (Verifikation nötig) blieb dadurch auch
    // bei verifizierten Personen bestehen.
    final publicVerified = boolOf(json, ['is_verified']) ?? false;
    final publicState = VerificationState.fromJson(
      json,
      isVerified: publicVerified,
    );

    // Der Geburtstagsstil: ein leerer Serverwert bedeutet "keiner
    // gewählt" - dann gilt der Standard. (Vorher stand hier ein
    // `as bool?`-Cast auf dem Wert, der bei einem Textfeld auch
    // fehlschlagen konnte.)
    final geburtstagsStil =
        (_leseText(json, ['birthday_style', 'birthdayStyle']) ?? '').trim();
    final geburtstagHeute =
        _leseBool(json, ['birthday_today', 'birthdayToday']) ?? false;

    return UserProfile(
      id: _leseText(json, ['user_id', 'id']) ?? '',
      name: _leseText(json, ['name']) ?? '',
      bio: _leseText(json, ['bio']) ?? '',
      // Profilbilder (v0.9.0, max. 3): verschlüsselte Refs - Lesen via
      // loadAvatarBytes (Client entschlüsselt lokal).
      //
      // BEFUND (22.11.2026, Fuzzing): `map((e) => e as String)` wirft,
      // sobald der Server eine Zahl in die Liste stellt. Der Leser
      // [textListOf] überspringt solche Elemente.
      photos: textListOf(json, ['photos']),
      interests: textListOf(json, ['interests']),
      gender: _leseText(json, ['gender']),
      personalityType: _leseText(json, ['personality_type', 'personalityType']),
      birthDate: birthDate,
      mood: _leseText(json, ['mood']),
      favoriteSong:
          (_leseText(json, ['favorite_song', 'favoriteSong']) ?? '')
                  .trim()
                  .isNotEmpty ==
              true
          ? (_leseText(json, ['favorite_song', 'favoriteSong']) ?? '').trim()
          : null,
      favoriteBand:
          (_leseText(json, ['favorite_band', 'favoriteBand']) ?? '')
                  .trim()
                  .isNotEmpty ==
              true
          ? (_leseText(json, ['favorite_band', 'favoriteBand']) ?? '').trim()
          : null,
      // Die Vorstellung des ANDEREN. BEFUND (07.11.2026, Betreiber):
      // "Vorstellung von anderen nicht abhörbar. Sie lädt nicht oder
      // braucht seeeeeeehr lange."
      //
      // Hier standen nur die snake_case-Namen. Die RPC get_public_profile
      // liefert die Vorstellung zwar - aber diese Fabrik wird auch mit
      // Maps aus dem Cache gefüllt (dort camelCase). Dann war die
      // Vorstellung leer und der Abspiel-Button gar nicht da.
      //
      // Siehe die Lese-Helfer weiter unten in dieser Datei.
      introText: _leseText(json, ['intro_text', 'introText']) ?? '',
      introAudioPath: _leseText(json, ['intro_audio_path', 'introAudioPath']),
      smoking: HabitudeLevel.fromServer(_leseText(json, ['smoking'])),
      alcohol: HabitudeLevel.fromServer(_leseText(json, ['alcohol'])),
      drugs: HabitudeLevel.fromServer(_leseText(json, ['drugs'])),
      musicLiked: (_leseListe(json, [
        'music_liked',
      ])).whereType<String>().toList(),
      musicDisliked: (_leseListe(json, [
        'music_disliked',
      ])).whereType<String>().toList(),
      birthdayStyle: geburtstagsStil.isNotEmpty ? geburtstagsStil : 'classic',
      birthdayToday: geburtstagHeute,
      // Abgerundete Distanz in km (5-km-Schritte, serverseitig berechnet).
      distanceKm: (_leseZahl(json, ['distance_km', 'distanceKm']) ?? 0)
          .toDouble(),
      matchScore: _leseZahl(json, ['match_score', 'matchScore'])?.toInt(),
      // Die RPC liefert created_at mit (profile_to_jsonb), es wurde nur
      // nie gelesen. Wird für den Hinweis "neuer Account" gebraucht.
      createdAt: _parseCreatedAt(_leseText(json, ['created_at', 'createdAt'])),
      isVerified: publicVerified,
      verificationState: publicState,
    );
  }

  /// Erzeugt ein [UserProfile] aus einem JSON-Map (Persistenz).
  /// Liest den gespeicherten Verifikationszustand.
  ///
  /// Der Zustand wird als ENUM-NAME gespeichert, nicht als der
  /// Server-Wert ('under_review'). Beim Lesen wird deshalb zuerst der
  /// eigene Name versucht, danach der Server-Wert, und zuletzt der
  /// Rückfall auf [isVerified].
  static VerificationState _stateFromStorage(Object? raw, bool isVerified) {
    if (raw is String) {
      for (final st in VerificationState.values) {
        if (st.name == raw) return st;
      }
      switch (raw) {
        case 'under_review':
          return VerificationState.underReview;
        case 'verified':
          return VerificationState.verified;
        case 'unverified':
          return VerificationState.unverified;
      }
    }
    return VerificationState.fromJson(const {}, isVerified: isVerified);
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: _leseText(json, ['id', 'user_id']) ?? '',
      name: _leseText(json, ['name']) ?? '',
      bio: _leseText(json, ['bio']) ?? '',
      interests: textListOf(json, ['interests']),
      photos: textListOf(json, ['photos']),
      state: _leseText(json, ['state']),
      country: _leseText(json, ['country']) ?? 'Deutschland',
      distanceKm: (_leseZahl(json, ['distanceKm', 'distance_km']) ?? 0)
          .toDouble(),
      gender: _leseText(json, ['gender']),
      genderPreference:
          _leseText(json, ['genderPreference', 'gender_preference']) ?? 'all',
      birthDate: _leseDatum(json, ['birthDate', 'birth_date']),
      personalityResult: _leseText(json, [
        'personalityResult',
        'personality_result',
      ]),
      personalityType: _leseText(json, ['personalityType', 'personality_type']),
      videoUrl: _leseText(json, ['videoUrl', 'video_url']),
      audioUrl: _leseText(json, ['audioUrl', 'audio_url']),
      favoriteSong: _leseText(json, ['favoriteSong', 'favorite_song']),
      favoriteBand: _leseText(json, ['favoriteBand', 'favorite_band']),
      locationLat: _leseZahl(json, ['location_lat', 'locationLat'])?.toDouble(),
      locationLng: _leseZahl(json, ['location_lng', 'locationLng'])?.toDouble(),
      isVerified: _leseBool(json, ['is_verified']) ?? false,
      verificationState: _stateFromStorage(
        _leseText(json, ['verification_state']),
        _leseBool(json, ['is_verified']) ?? false,
      ),
      isLocationSuspicious:
          _leseBool(json, ['is_location_suspicious']) ?? false,
      mood: _leseText(json, ['mood']),
      // BEFUND (07.11.2026, Betreiber): "Meine Vorstellung stimmt auch
      // nicht, da beide Nutzer eine Vorstellung gemacht haben aber hier
      // steht, dass keine hinterlegt wurde."
      //
      // DER GRUND: fromJson bedient drei Quellen mit drei Schreibweisen:
      // Server-Antworten (snake_case), handgebaute Maps (camelCase) und
      // der lokale Cache (camelCase). Der Parser kannte nur snake_case -
      // die Vorstellung kam deshalb weder aus dem Cache noch aus dem
      // Serverabruf an. Die Daten waren in der Datenbank vorhanden.
      //
      // Deshalb werden hier BEIDE Schreibweisen gelesen. Das Werkzeug
      // tool/checks/check_profile_cache_keys.py sucht nach jedem weiteren
      // solchen Mismatch.
      introText: _leseText(json, ['intro_text', 'introText']) ?? '',
      introAudioPath: _leseText(json, ['intro_audio_path', 'introAudioPath']),
      smoking: HabitudeLevel.fromServer(_leseText(json, ['smoking'])),
      alcohol: HabitudeLevel.fromServer(_leseText(json, ['alcohol'])),
      drugs: HabitudeLevel.fromServer(_leseText(json, ['drugs'])),
      musicLiked: (_leseListe(json, [
        'music_liked',
      ])).whereType<String>().toList(),
      musicDisliked: (_leseListe(json, [
        'music_disliked',
      ])).whereType<String>().toList(),
      birthdayStyle:
          _leseText(json, ['birthdayStyle', 'birthday_style']) ?? 'classic',
      birthdayToday:
          _leseBool(json, ['birthdayToday', 'birthday_today']) ?? false,
      createdAt: _parseCreatedAt(_leseText(json, ['createdAt', 'created_at'])),
    );
  }

  /// Wandelt das Profil in ein JSON-Map um (Persistenz).
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bio': bio,
    'interests': interests,
    'photos': photos,
    'state': state,
    'country': country,
    'distanceKm': distanceKm,
    'gender': gender,
    'genderPreference': genderPreference,
    'birthDate': birthDate?.toIso8601String(),
    'personalityResult': personalityResult,
    'personalityType': personalityType,
    'videoUrl': videoUrl,
    'audioUrl': audioUrl,
    'favoriteSong': favoriteSong,
    'favoriteBand': favoriteBand,
    'location_lat': locationLat,
    'location_lng': locationLng,
    'is_verified': isVerified,
    // Der Dreifachzustand wird mitgespeichert. Ohne das fällt er
    // nach dem Neustart auf is_verified zurück - und "wird geprüft"
    // wäre dann nicht mehr von "nicht verifiziert" zu unterscheiden.
    'verification_state': verificationState.name,
    'is_location_suspicious': isLocationSuspicious,
    'mood': mood,
    'introText': introText,
    'introAudioPath': introAudioPath,
    'smoking': smoking?.toServer(),
    'alcohol': alcohol?.toServer(),
    'drugs': drugs?.toServer(),
    'music_liked': musicLiked,
    'music_disliked': musicDisliked,
    'birthdayStyle': birthdayStyle,
    'birthdayToday': birthdayToday,
    'createdAt': createdAt?.toIso8601String(),
  };

  /// Liest `created_at` robust.
  ///
  /// Die Spalte kommt aus Supabase als ISO-String, kann aber auch
  /// bereits ein [DateTime] sein (z. B. aus einem Cache) und ist in
  /// manchen Fällen null. Ein kaputter Wert darf den Profilaufbau
  /// nicht sprengen - dann gilt das Konto schlicht nicht als neu.
  static DateTime? _parseCreatedAt(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  // =========================================================================
  // Die Lese-Helfer.
  //
  // BEFUND (07.11.2026, Betreiber): "Meine Vorstellung stimmt auch nicht,
  // da beide Nutzer eine Vorstellung gemacht haben aber hier steht, dass
  // keine hinterlegt wurde."
  //
  // DER GRUND: Es gibt drei Quellen für ein UserProfile, und sie
  // benutzen unterschiedliche Schreibweisen:
  //
  //   * Server-Antworten (REST, RPC, View) -> snake_case
  //     (intro_text, favorite_song, birthday_style, user_id)
  //   * von Hand gebaute Maps im Code     -> camelCase
  //     (introText, favoriteSong, birthdayStyle, id)
  //   * der lokale Cache (toJson)         -> camelCase
  //
  // Vor dieser Änderung lasen die Parser NUR eine davon. Ein Feld, das
  // der Produzent anders schrieb, kam nicht an - ohne Fehlermeldung. Bei
  // der Vorstellung hiess das: Die Daten lagen in der Datenbank, das
  // Profil zeigte trotzdem "keine hinterlegt".
  //
  // Deshalb liest jedes Feld jetzt unter ALLEN seinen Schreibweisen.
  // Der erste Treffer gewinnt; null zählt nicht als Treffer.
  //
  // Das Werkzeug tool/checks/check_profile_cache_keys.py sucht nach jedem
  // weiteren solchen Mismatch - es prüft toJson(), fromJson() und die
  // Server-Zuordnung gegeneinander.
  // =========================================================================

  /// Der erste vorhandene Wert unter einer der angegebenen Schreibweisen.
  static dynamic _lese(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final wert = json[key];
      if (wert != null) return wert;
    }
    return null;
  }

  /// Wie [_lese], aber als Text.
  static String? _leseText(Map<String, dynamic> json, List<String> keys) {
    final wert = _lese(json, keys);
    if (wert == null) return null;
    if (wert is String) return wert;
    return wert.toString();
  }

  /// Wie [_lese], aber als Zahl.
  static num? _leseZahl(Map<String, dynamic> json, List<String> keys) {
    final wert = _lese(json, keys);
    if (wert is num) return wert;
    if (wert is String) return num.tryParse(wert);
    return null;
  }

  /// Wie [_lese], aber als Wahrheitswert.
  ///
  /// Achtung: der Wert wird NICHT per `as bool?` gelesen - ein
  /// PostgREST liefert `true`/`false`, ein Cache kännte aber auch
  /// "true" (Text) enthalten. Das wird hier sauber gelesen, statt die
  /// ganze Profil-Erzeugung zu sprengen.
  static bool? _leseBool(Map<String, dynamic> json, List<String> keys) {
    final wert = _lese(json, keys);
    if (wert is bool) return wert;
    if (wert is String) {
      if (wert.toLowerCase() == 'true') return true;
      if (wert.toLowerCase() == 'false') return false;
    }
    return null;
  }

  /// Wie [_lese], aber als Liste.
  static List<dynamic> _leseListe(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final wert = _lese(json, keys);
    if (wert is List<dynamic>) return wert;
    return <dynamic>[];
  }

  /// Wie [_lese], aber als Datum.
  static DateTime? _leseDatum(Map<String, dynamic> json, List<String> keys) {
    final wert = _lese(json, keys);
    if (wert == null) return null;
    if (wert is DateTime) return wert;
    if (wert is String) return DateTime.tryParse(wert);
    return null;
  }

  /// Erstellt eine Kopie mit veränderten Feldern (immutabel).
  UserProfile copyWith({
    String? id,
    String? name,
    DateTime? birthDate,
    String? bio,
    List<String>? interests,
    List<String>? photos,
    String? state,
    String? country,
    double? distanceKm,
    String? gender,
    String? genderPreference,
    String? personalityResult,
    String? personalityType,
    String? videoUrl,
    String? audioUrl,
    String? favoriteSong,
    String? favoriteBand,
    double? locationLat,
    double? locationLng,
    bool? isVerified,
    VerificationState? verificationState,
    bool? isLocationSuspicious,
    String? mood,
    String? introText,
    String? introAudioPath,
    HabitudeLevel? smoking,
    HabitudeLevel? alcohol,
    HabitudeLevel? drugs,
    List<String>? musicLiked,
    List<String>? musicDisliked,
    int? matchScore,
    String? birthdayStyle,
    bool? birthdayToday,
    DateTime? createdAt,
    bool clearIntroAudio = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      photos: photos ?? this.photos,
      state: state ?? this.state,
      country: country ?? this.country,
      distanceKm: distanceKm ?? this.distanceKm,
      gender: gender ?? this.gender,
      genderPreference: genderPreference ?? this.genderPreference,
      personalityResult: personalityResult ?? this.personalityResult,
      personalityType: personalityType ?? this.personalityType,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      favoriteSong: favoriteSong ?? this.favoriteSong,
      favoriteBand: favoriteBand ?? this.favoriteBand,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      isVerified: isVerified ?? this.isVerified,
      verificationState: verificationState ?? this.verificationState,
      isLocationSuspicious: isLocationSuspicious ?? this.isLocationSuspicious,
      mood: mood ?? this.mood,
      introText: introText ?? this.introText,
      introAudioPath: clearIntroAudio
          ? null
          : (introAudioPath ?? this.introAudioPath),
      smoking: smoking ?? this.smoking,
      alcohol: alcohol ?? this.alcohol,
      drugs: drugs ?? this.drugs,
      musicLiked: musicLiked ?? this.musicLiked,
      musicDisliked: musicDisliked ?? this.musicDisliked,
      matchScore: matchScore ?? this.matchScore,
      birthdayStyle: birthdayStyle ?? this.birthdayStyle,
      birthdayToday: birthdayToday ?? this.birthdayToday,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.id == id &&
          other.name == name &&
          other.birthDate == birthDate &&
          other.bio == bio &&
          other.gender == gender &&
          other.genderPreference == genderPreference &&
          other.personalityType == personalityType &&
          other.isVerified == isVerified &&
          other.verificationState == verificationState &&
          other.isLocationSuspicious == isLocationSuspicious &&
          other.mood == mood;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    birthDate,
    bio,
    gender,
    genderPreference,
    personalityType,
    isVerified,
    isLocationSuspicious,
    mood,
  );
}

/// Einheitliches Distanz-Label für andere Nutzer (v0.10.0).
///
/// Die Entfernung wird NICHT als Zahl ausgegeben, sondern als 10-km-Stufe
/// ("10 bis 20 km"). Der genaue Wert bleibt beim Betrachter - er sieht
/// nur die Stufe, und unterhalb von 5 km gar nichts.
///
/// [t] ist [L10n.t] als Funktion, damit das Modell ohne BuildContext
/// auskommt (und der Text in Tests prüfbar ist).
///
/// Rückgabe: leerer String, wenn nichts angezeigt werden darf. Aufrufende
/// Widgets SHOULD den Wert nur einsetzen, wenn er nicht leer ist - sonst
/// entstehen führende Leerzeichen.
extension UserProfileDistanceLabel on UserProfile {
  String distanceLabel(String Function(String key) t) =>
      DistanceBucket.labelForKm(distanceKm, t) ?? '';
}
