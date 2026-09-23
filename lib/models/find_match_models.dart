import 'package:wisp/models/user_profile.dart';

/// Ein erhaltener Like inklusive Profil (Vorstellung) des Likers.
class ReceivedLike {
  const ReceivedLike({
    required this.likeId,
    required this.profile,
    this.createdAt,
  });

  final int likeId;
  final UserProfile profile;
  final DateTime? createdAt;

  factory ReceivedLike.fromJson(Map<String, dynamic> json) {
    final profile = UserProfile.fromPublicView(
      Map<String, dynamic>.from(json['profile'] as Map? ?? {}),
    );
    final distanceKm = (json['distanceKm'] as num?)?.toDouble();
    return ReceivedLike(
      likeId: json['likeId'] as int,
      // Distanz kommt als Geschwister-Feld der RPC-Antwort (5-km-Schritte).
      profile: distanceKm == null ? profile : profile.copyWith(distanceKm: distanceKm),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
    );
  }
}

/// Ein Match inklusive Quiz-Freischaltungsstand (Interessen-Reiter).
class MatchWithState {
  const MatchWithState({
    required this.matchId,
    required this.partner,
    required this.unlockLevel,
    required this.failedAttempts,
    this.createdVia = 'swipe',
    this.status = 'active',
    this.createdAt,
    this.resparkedAt,
    this.passedAt,
    this.lastAttemptAt,
    this.kind = 'spark',
  });

  final int matchId;
  final UserProfile partner;
  final int unlockLevel;
  final int failedAttempts;
  final String createdVia;

  /// 'active' | 'cooled' | 'ended' (Migration 074).
  final String status;
  final DateTime? createdAt;

  /// Letzter Re-Funke (Migration 101): Auto-Kühl-Karenzzeit - ein
  /// re-entfachter Funke bleibt mindestens 72 h aktiv, auch ohne neue
  /// Nachricht.
  final DateTime? resparkedAt;
  final DateTime? passedAt;
  final DateTime? lastAttemptAt;

  /// Funken-Typ (Migration 116, Idee 3): 'spark' = romantisch,
  /// 'friends' = Freundschaft.
  final String kind;

  bool get isFriends => kind == 'friends';

  bool get quizPassed => unlockLevel >= 2;

  /// Nur Matches aus dem Find-your-Match-Flow sind quiz-gesperrt.
  bool get quizGated => createdVia == 'find_match' && !quizPassed;

  /// "Erschlossene Funken": ruhig beendet (kein Countdown, kein Druck),
  /// Re-Funke jederzeit mit einem Tap möglich.
  bool get cooled => status == 'cooled';

  factory MatchWithState.fromJson(Map<String, dynamic> json) {
    final profile = UserProfile.fromPublicView(
      Map<String, dynamic>.from(json['profile'] as Map? ?? {}),
    );
    final distanceKm = (json['distanceKm'] as num?)?.toDouble();
    return MatchWithState(
      matchId: json['matchId'] as int,
      // Distanz kommt als Geschwister-Feld der RPC-Antwort (5-km-Schritte).
      partner: distanceKm == null ? profile : profile.copyWith(distanceKm: distanceKm),
      unlockLevel: (json['unlockLevel'] as num?)?.toInt() ?? 0,
      failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
      createdVia: json['createdVia'] as String? ?? 'swipe',
      status: json['status'] as String? ?? 'active',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
      resparkedAt: json['resparkedAt'] == null
          ? null
          : DateTime.tryParse(json['resparkedAt'] as String),
      passedAt: json['passedAt'] == null
          ? null
          : DateTime.tryParse(json['passedAt'] as String),
      lastAttemptAt: json['lastAttemptAt'] == null
          ? null
          : DateTime.tryParse(json['lastAttemptAt'] as String),
      kind: json['kind'] as String? ?? 'spark',
    );
  }
}

/// Eintrag der gemeinsamen Erinnerungsliste (Idee 5, Migration 116).
class BucketItem {
  const BucketItem({
    required this.id,
    required this.text,
    required this.createdBy,
    required this.done,
    this.createdAt,
  });

  final int id;
  final String text;
  final String createdBy;
  final bool done;
  final DateTime? createdAt;

  factory BucketItem.fromJson(Map<String, dynamic> json) {
    return BucketItem(
      id: (json['id'] as num).toInt(),
      text: json['text'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
    );
  }
}

/// Quiz-Zustand eines Matches (serverseitig gepflegt).
class QuizState {
  const QuizState({
    required this.matchId,
    required this.partnerId,
    required this.unlockLevel,
    required this.failedAttempts,
    this.createdVia = 'swipe',
    this.passedAt,
    this.lastAttemptAt,
    this.currentQuestionId,
    this.nextAttemptAt,
    this.cooldownRemainingSeconds = 0,
    this.answeredCurrent = false,
  });

  final int matchId;
  final String partnerId;
  final String createdVia;
  final int unlockLevel;
  final int failedAttempts;
  final DateTime? passedAt;
  final DateTime? lastAttemptAt;
  final String? currentQuestionId;
  final DateTime? nextAttemptAt;
  final int cooldownRemainingSeconds;

  /// Ob der Aufrufer die aktuelle Frage bereits beantwortet hat
  /// (dann wartet er auf den Partner).
  final bool answeredCurrent;

  bool get passed => unlockLevel >= 2;
  bool get roundInProgress => currentQuestionId != null;

  /// Nur Find-your-Match-Matches sind vor dem Quiz gesperrt.
  bool get quizGated => createdVia == 'find_match' && !passed;

  factory QuizState.fromJson(Map<String, dynamic> json) {
    return QuizState(
      matchId: json['matchId'] as int,
      partnerId: json['partnerId'] as String? ?? '',
      createdVia: json['createdVia'] as String? ?? 'swipe',
      unlockLevel: (json['unlockLevel'] as num?)?.toInt() ?? 0,
      failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
      answeredCurrent: json['answeredCurrent'] as bool? ?? false,
      passedAt: json['passedAt'] == null
          ? null
          : DateTime.tryParse(json['passedAt'] as String),
      lastAttemptAt: json['lastAttemptAt'] == null
          ? null
          : DateTime.tryParse(json['lastAttemptAt'] as String),
      currentQuestionId: json['currentQuestionId'] as String?,
      nextAttemptAt: json['nextAttemptAt'] == null
          ? null
          : DateTime.tryParse(json['nextAttemptAt'] as String),
      cooldownRemainingSeconds:
          (json['cooldownRemainingSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Eine Quiz-Frage (ohne korrekte Antwort, die bleibt serverseitig).
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<String> options;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['questionId'] as String,
      prompt: json['prompt'] as String,
      options: (json['options'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// Ergebnis einer abgegebenen Antwort.
class QuizAnswerResult {
  const QuizAnswerResult({
    required this.correct,
    required this.passed,
    this.waitingForPartner = false,
    this.roundClosed = false,
    this.cooldownActive = false,
    this.unlockLevel = 0,
    this.failedAttempts = 0,
    this.nextAttemptAt,
    this.cooldownRemainingSeconds = 0,
  });

  final bool correct;
  final bool passed;
  final bool waitingForPartner;
  final bool roundClosed;
  final bool cooldownActive;
  final int unlockLevel;
  final int failedAttempts;
  final DateTime? nextAttemptAt;
  final int cooldownRemainingSeconds;

  factory QuizAnswerResult.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as String?;
    if (error == 'round_closed') {
      return const QuizAnswerResult(
        correct: false,
        passed: false,
        roundClosed: true,
      );
    }
    if (error == 'already_answered') {
      // Bereits beantwortet -> wir warten auf den Partner.
      return const QuizAnswerResult(
        correct: true,
        passed: false,
        waitingForPartner: true,
      );
    }
    if (error == 'cooldown') {
      return QuizAnswerResult(
        correct: false,
        passed: false,
        cooldownActive: true,
        cooldownRemainingSeconds:
            (json['cooldownRemainingSeconds'] as num?)?.toInt() ?? 0,
        nextAttemptAt: json['nextAttemptAt'] == null
            ? null
            : DateTime.tryParse(json['nextAttemptAt'] as String),
      );
    }
    return QuizAnswerResult(
      correct: json['correct'] as bool? ?? false,
      passed: json['passed'] as bool? ?? false,
      waitingForPartner: json['waitingForPartner'] as bool? ?? false,
      unlockLevel: (json['unlockLevel'] as num?)?.toInt() ?? 0,
      failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: json['nextAttemptAt'] == null
          ? null
          : DateTime.tryParse(json['nextAttemptAt'] as String),
      cooldownRemainingSeconds:
          (json['cooldownRemainingSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}
