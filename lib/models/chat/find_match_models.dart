import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/utils/common/json_leser.dart';

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
    // BEFUND (22.11.2026, Fuzzing): Die Casts hier (`as int`, `as Map`,
    // `as String`) warfen, sobald der Server einen anderen Typ lieferte.
    // Die Daten kommen vom Server - ein Fehler dort darf die App nicht
    // abstuerzen lassen.
    final profilWert = json['profile'];
    final profile = UserProfile.fromPublicView(
      profilWert is Map
          ? Map<String, dynamic>.from(profilWert)
          : <String, dynamic>{},
    );
    final distanceKm = numOf(json, ['distanceKm'])?.toDouble();
    return ReceivedLike(
      likeId: intOf(json, ['likeId']) ?? 0,
      // Distanz kommt als Geschwister-Feld der RPC-Antwort (5-km-Schritte).
      profile: distanceKm == null
          ? profile
          : profile.copyWith(distanceKm: distanceKm),
      createdAt: dateOf(json, ['createdAt']),
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
    this.autoMatch = false,
    this.messageCount = 0,
    this.messageCountMine = 0,
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

  /// Automatisch entstandener Funke (Migration 177): true = der Funke
  /// kam nach 10 Minuten Dating Hour zustande und wurde NICHT von
  /// beiden Seiten bestaetigt. Der Interessen-Screen fragt deshalb
  /// einmal nach (behalten oder Person entfernen).
  ///
  /// Die Spalte heisst in der Datenbank `matches.auto_match`.
  final bool autoMatch;

  /// Wie viele Nachrichten die PERSON (der Partner) geschrieben hat.
  ///
  /// BEFUND (11.11.2026): Die Zahl ist serverseitig (Migration 210) -
  /// damit stimmt sie auf allen Geraeten und sie steht auch dann da, wenn
  /// der Chat auf diesem Geraet nie geoeffnet wurde.
  final int messageCount;

  /// Wie viele Nachrichten ICH in diesem Funke geschrieben habe.
  final int messageCountMine;

  bool get isFriends => kind == 'friends';

  bool get quizPassed => unlockLevel >= 2;

  /// Nur Matches aus dem Find-your-Match-Flow sind quiz-gesperrt.
  bool get quizGated => createdVia == 'find_match' && !quizPassed;

  /// "Erschlossene Funken": ruhig beendet (kein Countdown, kein Druck),
  /// Re-Funke jederzeit mit einem Tap möglich.
  bool get cooled => status == 'cooled';

  factory MatchWithState.fromJson(Map<String, dynamic> json) {
    final profilWert = json['profile'];
    final profile = UserProfile.fromPublicView(
      profilWert is Map
          ? Map<String, dynamic>.from(profilWert)
          : <String, dynamic>{},
    );
    final distanceKm = numOf(json, ['distanceKm'])?.toDouble();
    // Automatischer Funke (Migration 177). Die Listen-RPC liefert die
    // Spalte `auto_match` als 'autoMatch' (Namenskonvention der RPC);
    // 'auto_match' wird auch gelesen, falls der Wert unveraendert aus
    // der Tabelle kommt.
    final autoFlag = json['autoMatch'] ?? json['auto_match'];
    // BEFUND (22.11.2026, Fuzzing): Die Casts hier warfen bei jedem
    // falschen Typ (die Liste kommt vom Server).
    return MatchWithState(
      matchId: intOf(json, ['matchId']) ?? 0,
      // Distanz kommt als Geschwister-Feld der RPC-Antwort (5-km-Schritte).
      partner: distanceKm == null
          ? profile
          : profile.copyWith(distanceKm: distanceKm),
      unlockLevel: intOf(json, ['unlockLevel']) ?? 0,
      failedAttempts: intOf(json, ['failedAttempts']) ?? 0,
      createdVia: textOf(json, ['createdVia']) ?? 'swipe',
      status: textOf(json, ['status']) ?? 'active',
      createdAt: dateOf(json, ['createdAt']),
      resparkedAt: dateOf(json, ['resparkedAt']),
      passedAt: dateOf(json, ['passedAt']),
      lastAttemptAt: dateOf(json, ['lastAttemptAt']),
      kind: textOf(json, ['kind']) ?? 'spark',
      autoMatch: autoFlag is bool ? autoFlag : false,
      messageCount: intOf(json, ['messageCount']) ?? 0,
      messageCountMine: intOf(json, ['messageCountMine']) ?? 0,
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
      id: intOf(json, ['id']) ?? 0,
      text: textOf(json, ['text']) ?? '',
      createdBy: textOf(json, ['createdBy']) ?? '',
      done: boolOf(json, ['done']) ?? false,
      createdAt: dateOf(json, ['createdAt']),
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
      matchId: intOf(json, ['matchId']) ?? 0,
      partnerId: textOf(json, ['partnerId']) ?? '',
      createdVia: textOf(json, ['createdVia']) ?? 'swipe',
      unlockLevel: intOf(json, ['unlockLevel']) ?? 0,
      failedAttempts: intOf(json, ['failedAttempts']) ?? 0,
      answeredCurrent: boolOf(json, ['answeredCurrent']) ?? false,
      passedAt: dateOf(json, ['passedAt']),
      lastAttemptAt: dateOf(json, ['lastAttemptAt']),
      currentQuestionId: textOf(json, ['currentQuestionId']),
      nextAttemptAt: dateOf(json, ['nextAttemptAt']),
      cooldownRemainingSeconds: intOf(json, ['cooldownRemainingSeconds']) ?? 0,
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
      id: textOf(json, ['questionId']) ?? '',
      prompt: textOf(json, ['prompt']) ?? '',
      options: textListOf(json, ['options']),
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
    final error = textOf(json, ['error']);
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
            intOf(json, ['cooldownRemainingSeconds']) ?? 0,
        nextAttemptAt: dateOf(json, ['nextAttemptAt']),
      );
    }
    return QuizAnswerResult(
      correct: boolOf(json, ['correct']) ?? false,
      passed: boolOf(json, ['passed']) ?? false,
      waitingForPartner: boolOf(json, ['waitingForPartner']) ?? false,
      unlockLevel: intOf(json, ['unlockLevel']) ?? 0,
      failedAttempts: intOf(json, ['failedAttempts']) ?? 0,
      nextAttemptAt: dateOf(json, ['nextAttemptAt']),
      cooldownRemainingSeconds: intOf(json, ['cooldownRemainingSeconds']) ?? 0,
    );
  }
}

/// Eine Interessens-Kategorie mit der Zahl der Kandidaten, die der
/// Betreiber dort gerade findet (Migration 204).
///
/// Die Zahl ist **serverseitig** berechnet und respects dieselben
/// Altersregeln wie die Kandidaten selbst: Wer 16 oder 17 ist, sieht
/// auch in den Zahlen nur Minderjaehrige.
class CategoryCount {
  const CategoryCount({required this.category, required this.count});

  /// Die Kategorie (ein Interesse, z. B. "Musik").
  final String category;

  /// Wie viele Personen mit Vorstellung es in der Kategorie gibt.
  final int count;

  factory CategoryCount.fromJson(Map<String, dynamic> json) {
    return CategoryCount(
      category: textOf(json, ['category']) ?? '',
      count: intOf(json, ['cnt']) ?? 0,
    );
  }

  @override
  String toString() => 'CategoryCount($category: $count)';
}
