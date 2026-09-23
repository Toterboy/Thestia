import 'package:intl/intl.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/models/message.dart';

/// Herzensstärken (v0.9.2, Nutzerwunsch-Ideen 1/3/5):
/// Erinnerungs-Momente, Freundschafts-Modus, gemeinsame Erinnerungsliste.
///
/// Der Dismiss-Store ist ein Set von Keys `matchId:type` - gezeigt
/// wird EIN anstehender Moment pro Chat-Öffnung (in Prefs).
class Milestones {
  const Milestones._();

  /// Liefert den aktuell anzuzeigenden Moment oder null.
  ///
  /// [matchedAt]: Funken-Entstehung (createdAt des Matches).
  /// [quizPassedAt]: Quiz-Bestehen (beide Seiten, serverseitig gepflegt).
  /// [dismissed]: bereits gezeigte Keys (matchId:type).
  static Milestone? currentFor({
    required int matchId,
    required DateTime? matchedAt,
    required DateTime? quizPassedAt,
    required Set<String> dismissed,
  }) {
    final now = DateTime.now();
    final candidates = <Milestone>[];
    if (quizPassedAt != null) {
      candidates.add(Milestone(
        type: 'quizPassed',
        date: quizPassedAt,
        titleKey: 'milestone.quizPassed',
        bodyKey: 'milestone.quizPassedBody',
      ));
    }
    if (matchedAt != null) {
      candidates.add(Milestone(
        type: 'sparkDay',
        titleKey: 'milestone.sparkDay',
        bodyKey: 'milestone.sparkDayBody',
        date: matchedAt,
      ));
      final months = [
        (1, 'month1'),
        (3, 'month3'),
        (12, 'year1'),
      ];
      for (final (n, type) in months) {
        final at = _addMonths(matchedAt, n);
        // Zeigen, solange der Moment <= 3 Tage her ist (nicht ewig nach-
        // hinken), und nur wenn er erreicht wurde.
        if (now.isAfter(at) && now.difference(at).inDays <= 3) {
          candidates.add(Milestone(
            type: type,
            date: at,
            titleKey: 'milestone.$type',
            bodyKey: 'milestone.${type}Body',
          ));
        }
      }
    }
    // Frischeste relevanteste zuerst (neuester Moment gewinnt).
    candidates.sort((a, b) => b.date.compareTo(a.date));
    for (final c in candidates) {
      if (!dismissed.contains('$matchId:${c.type}')) return c;
    }
    return null;
  }

  static DateTime _addMonths(DateTime base, int months) {
    var y = base.year;
    var m = base.month + months;
    while (m > 12) {
      m -= 12;
      y++;
    }
    return DateTime(y, m, base.day,
        base.hour, base.minute, base.second);
  }
}

/// Ein Erinnerungs-Moment (Jubiläums-Karte im Chat).
class Milestone {
  const Milestone({
    required this.type,
    required this.date,
    required this.titleKey,
    required this.bodyKey,
  });

  final String type;
  final DateTime date;
  final String titleKey;
  final String bodyKey;

  /// Datum-String für den Body (lokales Format: d. MMMM yyyy).
  String formattedDate(String languageCode) {
    try {
      return DateFormat.yMMMMd(
              languageCode == 'en' ? 'en_US' : 'de_DE')
          .format(date.toLocal());
    } catch (_) {
      final d = date.toLocal();
      return '${d.day}.${d.month}.${d.year}';
    }
  }
}

/// Zähler-Stand: Wie viele NACHRICHTEN seit Funkenbeginn - benutzt für
/// die Stillstand-Erinnerung der Erinnerungsliste (Idee 5).
class BucketReminder {
  const BucketReminder._();

  /// True, wenn die Erinnerungsliste Einträge hat und seit dem letzten
  /// erledigten/angelegten Eintrag mehr als 14 Tage vergangen sind UND
  /// im Chat Stille herrscht (keine Nachricht der letzten 7 Tage).
  static bool shouldRemind({
    required List<BucketItem> items,
    required List<Message> messages,
  }) {
    if (items.isEmpty) return false;
    final now = DateTime.now();
    // Chat-Stille: keine Nachricht seit 7 Tagen.
    for (final m in messages) {
      if (now.difference(m.timestamp).inDays < 7) return false;
    }
    // Liste unberührt: letzte Änderung (erledigt/angelegt) > 14 Tage.
    DateTime? lastTouch;
    for (final i in items) {
      final t = i.createdAt;
      if (t != null && (lastTouch == null || t.isAfter(lastTouch))) {
        lastTouch = t;
      }
    }
    if (lastTouch == null) return false;
    return now.difference(lastTouch).inDays >= 14;
  }

  /// Tage seit der letzten Listen-Änderung (für den Hinweistext).
  static int idleDays(List<BucketItem> items) {
    DateTime? lastTouch;
    for (final i in items) {
      final t = i.createdAt;
      if (t != null && (lastTouch == null || t.isAfter(lastTouch))) {
        lastTouch = t;
      }
    }
    if (lastTouch == null) return 0;
    return DateTime.now().difference(lastTouch).inDays;
  }
}
