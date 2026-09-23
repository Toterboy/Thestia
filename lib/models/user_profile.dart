// Repräsentiert ein Nutzerprofil in der App.
//
// Enthält die für Dating relevanten Felder. Fotos werden als Liste von
// (Mock-)Bild-Pfaden/URLs gespeichert. Der Blind Mode sorgt dafür, dass
// diese Fotos erst nach einem Match für andere sichtbar sind.

import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/utils/age_calculator.dart';

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

  /// Wohnort / Stadt (für Distanz-Anzeige).
  final String city;

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
    this.city = '',
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
  });

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
  /// Mapped `age` → birthDate (rückgerechnet), `lat_approx`/`lng_approx` →
  /// locationLat/locationLng. Alle sensiblen Felder sind in der View nicht
  /// enthalten und werden mit Defaults belegt.
  factory UserProfile.fromPublicView(Map<String, dynamic> json) {
    // Alter rückrechnen: ungefähres Geburtsjahr.
    final age = json['age'] as int?;
    final birthDate = age != null
        ? DateTime(DateTime.now().year - age, 1, 1)
        : null;

    return UserProfile(      id: json['user_id'] as String,
      name: json['name'] as String,
      bio: json['bio'] as String? ?? '',
      // Profilbilder (v0.9.0, max. 3): verschlüsselte Refs - Lesen via
      // loadAvatarBytes (Client entschlüsselt lokal).
      photos: (json['photos'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      interests: (json['interests'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
      gender: json['gender'] as String?,
      personalityType: json['personality_type'] as String?,
      locationLat: (json['lat_approx'] as num?)?.toDouble(),
      locationLng: (json['lng_approx'] as num?)?.toDouble(),
      birthDate: birthDate,
      mood: json['mood'] as String?,
      favoriteSong: (json['favorite_song'] as String?)?.trim().isNotEmpty == true
          ? (json['favorite_song'] as String).trim()
          : null,
      favoriteBand: (json['favorite_band'] as String?)?.trim().isNotEmpty == true
          ? (json['favorite_band'] as String).trim()
          : null,
      introText: json['intro_text'] as String? ?? '',
      introAudioPath: json['intro_audio_path'] as String?,
      smoking: HabitudeLevel.fromServer(json['smoking'] as String?),
      alcohol: HabitudeLevel.fromServer(json['alcohol'] as String?),
      drugs: HabitudeLevel.fromServer(json['drugs'] as String?),
      musicLiked: (json['music_liked'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      musicDisliked: (json['music_disliked'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      birthdayStyle: (json['birthday_style'] as String?)?.isNotEmpty == true
          ? (json['birthday_style'] as String)
          : 'classic',
      birthdayToday: json['birthday_today'] as bool? ?? false,
      // Abgerundete Distanz in km (5-km-Schritte, serverseitig berechnet).
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      matchScore: (json['match_score'] as num?)?.toInt(),
    );
  }

  /// Erzeugt ein [UserProfile] aus einem JSON-Map (Persistenz).
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      bio: json['bio'] as String,
      interests: (json['interests'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
      city: json['city'] as String? ?? '',
      state: json['state'] as String?,
      country: json['country'] as String? ?? 'Deutschland',
      distanceKm: (json['distanceKm'] as num? ?? 0).toDouble(),
      gender: json['gender'] as String?,
      genderPreference: json['genderPreference'] as String? ?? 'all',
      birthDate: json['birthDate'] == null
          ? null
          : DateTime.tryParse(json['birthDate'] as String),
      personalityResult: json['personalityResult'] as String?,
      personalityType: json['personalityType'] as String?,
      videoUrl: json['videoUrl'] as String?,
      audioUrl: json['audioUrl'] as String?,
      favoriteSong: json['favoriteSong'] as String?,
      favoriteBand: json['favoriteBand'] as String?,
      locationLat: json['location_lat'] == null
          ? null
          : (json['location_lat'] as num).toDouble(),
      locationLng: json['location_lng'] == null
          ? null
          : (json['location_lng'] as num).toDouble(),
      isVerified: json['is_verified'] as bool? ?? false,
      isLocationSuspicious:
          json['is_location_suspicious'] as bool? ?? false,
      mood: json['mood'] as String?,
      introText: json['intro_text'] as String? ?? '',
      introAudioPath: json['intro_audio_path'] as String?,
      smoking: HabitudeLevel.fromServer(json['smoking'] as String?),
      alcohol: HabitudeLevel.fromServer(json['alcohol'] as String?),
      drugs: HabitudeLevel.fromServer(json['drugs'] as String?),
      musicLiked: (json['music_liked'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      musicDisliked: (json['music_disliked'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      birthdayStyle: json['birthdayStyle'] as String? ?? 'classic',
      birthdayToday: json['birthdayToday'] as bool? ?? false,
    );
  }

  /// Wandelt das Profil in ein JSON-Map um (Persistenz).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bio': bio,
        'interests': interests,
        'photos': photos,
        'city': city,
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
      };

  /// Erstellt eine Kopie mit veränderten Feldern (immutabel).
  UserProfile copyWith({
    String? id,
    String? name,
    DateTime? birthDate,
    String? bio,
    List<String>? interests,
    List<String>? photos,
    String? city,
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
    bool clearIntroAudio = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      photos: photos ?? this.photos,
      city: city ?? this.city,
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
      isLocationSuspicious:
          isLocationSuspicious ?? this.isLocationSuspicious,
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
          other.city == city &&
          other.gender == gender &&
          other.genderPreference == genderPreference &&
          other.personalityType == personalityType &&
          other.isVerified == isVerified &&
          other.isLocationSuspicious == isLocationSuspicious &&
          other.mood == mood;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        birthDate,
        bio,
        city,
        gender,
        genderPreference,
        personalityType,
        isVerified,
        isLocationSuspicious,
        mood,
      );
}

/// Einheitliches Distanz-Label (5-km-Schritte, serverseitig berechnet).
extension UserProfileDistanceLabel on UserProfile {
  String get distanceLabel {
    if (distanceKm <= 0) return '';
    final km = distanceKm.round();
    // Rundung auf 5-km-Schritte: Werte unter 2.5 km runden auf 0.
    return km == 0 ? 'unter 5 km entfernt' : 'ca. $km km entfernt';
  }
}
