import 'package:thestia/services/server_time_service.dart';

/// Domain-Modelle für das Dating-Hour-Feature.
///
/// Diese Modelle werden ausschließlich aus Supabase-Rows gebaut. Es gibt
/// keine lokale Hive-Persistenz mehr - Status, Teilnahme und Sessions werden
/// serverseitig in Supabase verwaltet (RLS + SECURITY DEFINER RPCs).
/// Siehe dazu supabase/migrations/018-023_dating_hour_*.sql.

/// Model für eine Dating-Hour-Session (5-Minuten-Chat).
class DatingHourSession {
  final String id;
  final String eventId;
  final String userA;
  final String userB;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? endedAt;
  final String? userADecision; // 'accept' oder 'reject'
  final String? userBDecision; // 'accept' oder 'reject'
  final bool isMatch;

  const DatingHourSession({
    required this.id,
    required this.eventId,
    required this.userA,
    required this.userB,
    required this.startedAt,
    required this.expiresAt,
    this.endedAt,
    this.userADecision,
    this.userBDecision,
    this.isMatch = false,
  });

  /// Baut eine Session aus einer Supabase-Row.
  factory DatingHourSession.fromJson(Map<String, dynamic> json) {
    return DatingHourSession(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userA: json['user_a'] as String,
      userB: json['user_b'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      userADecision: json['user_a_decision'] as String?,
      userBDecision: json['user_b_decision'] as String?,
      isMatch: json['is_match'] as bool? ?? false,
    );
  }

  /// Prüft, ob der übergebene Nutzer Teilnehmer A ist.
  bool isParticipantA(String userId) => userA == userId;

  /// Liefert die ID des Gesprächspartners.
  String getPeerId(String userId) => userA == userId ? userB : userA;

  /// Liefert die eigene Entscheidung des übergebenen Nutzers.
  String? getDecisionFor(String userId) =>
      userA == userId ? userADecision : userBDecision;

  /// Ob der Timer abgelaufen ist (5 Minuten).
  ///
  /// V: Serverzeit statt DateTime.now(), damit eine verstellte Geräte-Uhr
  /// das 5-Minuten-Fenster nicht verlängern/verkürzen kann.
  bool get isExpired =>
      ServerTimeService.instance.getVerifiedNow().isAfter(expiresAt);

  /// Verbleibende Zeit in Sekunden.
  int get remainingSeconds =>
      expiresAt.difference(ServerTimeService.instance.getVerifiedNow()).inSeconds.clamp(0, 300);

  /// Ob beide Nutzer "Annehmen" gedrückt haben.
  bool get isMutualMatch =>
      userADecision == 'accept' && userBDecision == 'accept';

  /// Ob beide eine Entscheidung getroffen haben.
  bool get bothDecided => userADecision != null && userBDecision != null;

  /// Ob die Session abgeschlossen ist (Match oder Ablehnung/Timeout).
  bool get isCompleted => endedAt != null;

  /// Ob mindestens eine Person abgelehnt hat (oder Timer abgelaufen ohne beidseitige Annahme).
  bool get isRejected => isCompleted && !isMatch;

  DatingHourSession copyWith({
    String? id,
    String? eventId,
    String? userA,
    String? userB,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? endedAt,
    String? userADecision,
    String? userBDecision,
    bool? isMatch,
  }) {
    return DatingHourSession(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      userA: userA ?? this.userA,
      userB: userB ?? this.userB,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      endedAt: endedAt ?? this.endedAt,
      userADecision: userADecision ?? this.userADecision,
      userBDecision: userBDecision ?? this.userBDecision,
      isMatch: isMatch ?? this.isMatch,
    );
  }
}

/// Präferenzen für den Dating-Hour-Modus.
class DatingHourPreferences {
  final int ageMin;
  final int ageMax;
  final String genderPreference; // 'male', 'female', 'non_binary', 'all'
  final String preferredTrait; // Freitext, z. B. "Humor"
  final double maxDistanceKm;

  /// Gewohnheiten als SOFT-Präferenz (Serverwerte oder null = egal).
  final String? smoking;
  final String? alcohol;
  final String? drugs;

  const DatingHourPreferences({
    required this.ageMin,
    required this.ageMax,
    required this.genderPreference,
    required this.preferredTrait,
    required this.maxDistanceKm,
    this.smoking,
    this.alcohol,
    this.drugs,
  });

  DatingHourPreferences copyWith({
    int? ageMin,
    int? ageMax,
    String? genderPreference,
    String? preferredTrait,
    double? maxDistanceKm,
    String? smoking,
    String? alcohol,
    String? drugs,
  }) {
    return DatingHourPreferences(
      ageMin: ageMin ?? this.ageMin,
      ageMax: ageMax ?? this.ageMax,
      genderPreference: genderPreference ?? this.genderPreference,
      preferredTrait: preferredTrait ?? this.preferredTrait,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      smoking: smoking ?? this.smoking,
      alcohol: alcohol ?? this.alcohol,
      drugs: drugs ?? this.drugs,
    );
  }

  /// Wird als `preferences::jsonb` an `join_dating_hour` übergeben.
  Map<String, dynamic> toJson() => {
        'ageMin': ageMin,
        'ageMax': ageMax,
        'genderPreference': genderPreference,
        'preferredTrait': preferredTrait.trim().length > 50
            ? preferredTrait.trim().substring(0, 50)
            : preferredTrait.trim(),
        'maxDistanceKm': maxDistanceKm,
        if (smoking != null) 'smoking': smoking,
        if (alcohol != null) 'alcohol': alcohol,
        if (drugs != null) 'drugs': drugs,
      };

  factory DatingHourPreferences.fromJson(Map<String, dynamic> json) {
    return DatingHourPreferences(
      ageMin: json['ageMin'] as int,
      ageMax: json['ageMax'] as int,
      genderPreference: json['genderPreference'] as String,
      preferredTrait: json['preferredTrait'] as String,
      maxDistanceKm: (json['maxDistanceKm'] as num).toDouble(),
      smoking: json['smoking'] as String?,
      alcohol: json['alcohol'] as String?,
      drugs: json['drugs'] as String?,
    );
  }
}

/// Model für den Dating-Hour-Event (z. B. Samstag 20:00-21:00).
class DatingHourEvent {
  final String id;
  final DateTime eventDate;
  final int dayOfWeek; // 0=So, 6=Sa
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status; // 'scheduled','active','ended','cancelled'

  /// Ob der aktuelle User für dieses Event opt-in hat.
  /// Wird vom Service/UI nach dem Laden gesetzt, da RLS nur die eigene
  /// Teilnehmerzeile lesen lässt.
  bool currentUserParticipating;

  /// Liste der aktiven Teilnehmer-IDs.
  /// Im MVP tracken wir hier nur die eigene Teilnahme (siehe RLS-Kommentar
  /// oben). Eine echte Live-Anzahl müsste über eine separate Aggregat-Abfrage
  /// oder Realtime erfolgen.
  List<String> activeParticipants;

  DatingHourEvent({
    required this.id,
    required this.eventDate,
    required this.dayOfWeek,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.currentUserParticipating = false,
    this.activeParticipants = const [],
  });

  /// Baut ein Event aus einer Supabase-Row.
  factory DatingHourEvent.fromJson(Map<String, dynamic> json) {
    return DatingHourEvent(
      id: json['id'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      dayOfWeek: json['day_of_week'] as int,
      startHour: json['start_hour'] as int,
      startMinute: json['start_minute'] as int,
      endHour: json['end_hour'] as int,
      endMinute: json['end_minute'] as int,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      status: json['status'] as String,
    );
  }

  /// Startzeit des Events (lokale Zeitkomponenten aus der DB).
  DateTime get startTime => DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        startHour,
        startMinute,
      );

  /// Endzeit des Events.
  DateTime get endTime => DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        endHour,
        endMinute,
      );

  /// Beitritts-Startzeit (10 Minuten vorher).
  DateTime get joinStartTime => startTime.subtract(const Duration(minutes: 10));

  /// Ob das Event gerade läuft - nutzt Serverzeit.
  bool get isRunningNow {
    final now = ServerTimeService.instance.getVerifiedNow();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  /// Ob das Event beendet ist (Status oder Zeit).
  bool get isEnded =>
      status == 'ended' ||
      ServerTimeService.instance.getVerifiedNow().isAfter(endsAt);

  /// Ob man dem Event noch beitreten kann (vor oder während, aber nicht nach Ende).
  bool get canJoin {
    final now = ServerTimeService.instance.getVerifiedNow();
    return !isEnded && now.isBefore(endsAt);
  }

  /// Minuten bis zum Event-Start.
  int get minutesUntilStart {
    final now = ServerTimeService.instance.getVerifiedNow();
    if (startsAt.isAfter(now)) {
      return startsAt.difference(now).inMinutes;
    }
    return 0;
  }

  /// Minuten bis zum Event-Ende.
  int get minutesUntilEnd {
    final now = ServerTimeService.instance.getVerifiedNow();
    if (endsAt.isAfter(now)) {
      return endsAt.difference(now).inMinutes;
    }
    return 0;
  }

  DatingHourEvent copyWith({
    String? id,
    DateTime? eventDate,
    int? dayOfWeek,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    DateTime? startsAt,
    DateTime? endsAt,
    String? status,
    bool? currentUserParticipating,
    List<String>? activeParticipants,
  }) {
    return DatingHourEvent(
      id: id ?? this.id,
      eventDate: eventDate ?? this.eventDate,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      status: status ?? this.status,
      currentUserParticipating:
          currentUserParticipating ?? this.currentUserParticipating,
      activeParticipants: activeParticipants ?? this.activeParticipants,
    );
  }
}

/// Freundliche Ablehnungs-Nachrichten (zufällig ausgewählt).
class RejectionMessages {
  static const List<String> _messages = [
    'Diese Verbindung hat leider nicht ganz gepasst. Aber keine Sorge, das sagt nichts über dich aus! Wir suchen gleich jemand Neues für dich. 😊',
    'Manchmal funkt es einfach nicht, und das ist völlig okay! Dein nächstes Gespräch wartet schon. 😉',
    'Nicht jede Unterhaltung führt zum Funken, aber jede bringt dich weiter. Weiter so! 🙂',
    'Die Chemie hat diesmal nicht gestimmt, aber du bist großartig, wie du bist! Neuer Versuch? 😊',
    'Schade, dass es nicht gepasst hat. Aber hey, jeder Chat ist Übung für den richtigen Moment! 💪',
    'Nicht entmutigen lassen! Manchmal braucht es ein paar Anläufe. Dein Funke kommt noch! 😊',
    'Dieses Gespräch war nicht der richtige Fit. Aber das nächste könnte es sein! Wir suchen weiter... 🚀',
    'Kein Funke dieses Mal, aber du hast Mut bewiesen, dich darauf einzulassen. Respekt! 🌟',
  ];

  /// Gibt eine zufällige freundliche Ablehnungsnachricht zurück.
  static String getRandom() {
    final index = DateTime.now().millisecondsSinceEpoch % _messages.length;
    return _messages[index];
  }
}
