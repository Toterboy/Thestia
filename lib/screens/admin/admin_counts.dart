import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/services/supabase_database_service.dart';

/// Filtert Sperren nach E-Mail, Begruendung oder Person.
///
/// Leerer Suchbegriff liefert die volle Liste zurueck: der Normalzustand
/// soll keinen Filtercode durchlaufen, und ein Tippfehler im Suchfeld darf
/// nicht als "keine Sperren" enden.
///
/// Exportiert (statt `private` im Screen), weil die Suchlogik der Teil ist,
/// der wahrscheinlichst falsch ist: zu enge Suche findet nichts, zu weite
/// findet alles. Beides faellt nur mit einem Test auf.
List<Map<String, dynamic>> filterBans(
  List<Map<String, dynamic>> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items.where((e) {
    final haystack = [
      '${e['email'] ?? ''}',
      '${e['reason'] ?? ''}',
      '${e['bannedBy'] ?? ''}',
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }).toList();
}

/// Kennzahlen fuer den Admin-Screen (ROADMAP Zeile 807).
///
/// Clientseitig aus den Listen berechnet, bewusst OHNE neue RPC: Migration
/// 133 ist noch nicht angewendet, und eine zweite ungetestete Migration
/// direkt danach waere das schlechteste Timing.
class AdminCounts {
  const AdminCounts({
    required this.openReports,
    required this.totalReports,
    required this.bugsLast24h,
    required this.bugsPrevious24h,
    required this.bugsTotal,
    required this.pendingVerifications,
    required this.pendingAppeals,
    required this.bans,
  });

  /// user_reports mit status = 'pending' (die einzige Status-Angabe, die
  /// `admin_list_user_reports` liefert).
  final int openReports;

  final int totalReports;

  /// bug_reports der letzten 24 Stunden.
  final int bugsLast24h;

  /// bug_reports des Zeitraums 24 bis 48 Stunden zurueck. Ohne diese
  /// Vergleichsgroesse sagt "3 neue Bugs" nichts: drei Meldungen sind an
  /// einem Montag normal und an einem Sonntag ein Ausreisser.
  final int bugsPrevious24h;

  final int bugsTotal;

  final int pendingVerifications;
  final int pendingAppeals;
  final int bans;

  /// `true`, wenn die Bug-Zahl gegenueber dem Vortag mehr als verdoppelt
  /// hat UND mindestens drei neue dazugekommen sind. Ohne die Mindestmenge
  /// waere "1 -> 2" ein Alarm, der jeder Fehlbedienung folgt.
  bool get bugsRising =>
      bugsLast24h >= 3 && bugsLast24h > bugsPrevious24h * 2;

  /// Platzhalter, solange nichts geladen ist: -1 statt 0, weil eine echte
  /// Null etwas anderes bedeutet als "noch nicht bekannt".
  static const AdminCounts unknown = AdminCounts(
    openReports: -1,
    totalReports: -1,
    bugsLast24h: -1,
    bugsPrevious24h: -1,
    bugsTotal: -1,
    pendingVerifications: -1,
    pendingAppeals: -1,
    bans: -1,
  );

  bool get isLoaded => openReports >= 0;
}

/// Zaehlt Meldungen mit Status `pending`.
///
/// Als eigene Funktion, nicht inline: das Zaehlen IST die Aussage dieser
/// Kennzahl und braucht einen Test. Ein Fehler zeigt eine falsche Zahl an,
/// keinen Absturz - die schlimmere Fehlerart.
int countOpenReports(List<Map<String, dynamic>> reports) {
  return reports.where((r) => r['status'] == 'pending').length;
}

/// Zaehlt Bug-Reports mit `createdAt` im Fenster `[from, to)`.
///
/// Die Zeitstempel kommen als ISO-String aus JSONB. Ein Eintrag ohne
/// parsebares Datum zaehlt in KEINEM Fenster, statt pauschal als alt oder
/// neu gewertet zu werden: sonst wuerde ein kaputter Zeitstempel still die
/// Kennzahl verschieben.
///
/// Der Vergleich laeuft in UTC, weil die Server-Zeitstempel zeitzonen-
/// behaftet sind und der Geraete-Offset sonst zwischen 0 und 24 Stunden
/// schwanken wuerde.
///
/// `from` und `to` muessen in der Reihenfolge liegen: die Grenzen werden
/// nicht getauscht. Der Aufrufer garantiert das ueber
/// [bugsRecentWindows], damit nicht jemand die Argumente vertauscht und
/// jede Kennzahl als Anstieg gemeldet bekommt.
int countBugsInWindow(
  List<Map<String, dynamic>> bugs,
  DateTime from,
  DateTime to,
) {
  final fromUtc = from.toUtc();
  final toUtc = to.toUtc();
  var n = 0;
  for (final b in bugs) {
    final dt = DateTime.tryParse('${b['createdAt']}')?.toUtc();
    if (dt == null) continue;
    if (!dt.isBefore(fromUtc) && dt.isBefore(toUtc)) n++;
  }
  return n;
}

/// Die beiden 24-Stunden-Fenster fuer [countBugsInWindow].
///
/// Als eine Funktion, damit `now` nur an EINER Stelle im Code steht. Zwei
/// getrennte `DateTime.now()`-Aufrufe liegen um Mikosekunden
/// auseinander: die Grenze zwischen "letzte 24 h" und "vorige 24 h" waere
/// dann ein Schnitt von unter einer Mikrosekunde Breite, und die Summe
/// beider Fenster koennte einen Bug doppelt zaehlen oder gar nicht.
/// Beide Fenster sind halboffen und ueberschneiden sich deshalb nicht.
({DateTime dayAgo, DateTime twoDaysAgo, DateTime now}) bugsRecentWindows(
  DateTime now,
) {
  final n = now.toUtc();
  return (
    now: n,
    dayAgo: n.subtract(const Duration(hours: 24)),
    twoDaysAgo: n.subtract(const Duration(hours: 48)),
  );
}

/// Laedt die Kennzahlen.
///
/// Jeder Nebenabruf hat einen eigenen try/catch: fehlt eine Migration
/// (118 fuer Einsprueche, 120 fuer Auto-Freigaben), darf daraus keine
/// falsche Null im gesunden Teil der Zeile werden - und vor allem kein
/// kompletter Ausfall der Zeile.
final adminCountsProvider = FutureProvider<AdminCounts>((ref) async {
  final db = ref.read(supabaseDatabaseServiceProvider);

  final reports = await db.fetchUserReports();
  final bugs = await db.fetchBugReports();

  final w = bugsRecentWindows(DateTime.now());

  int pendingVerifications = 0;
  try {
    pendingVerifications = (await db.fetchPendingVerifications()).length;
  } catch (e) {
    debugPrint('[AdminCounts] Verifizierungen: $e');
  }

  int pendingAppeals = 0;
  try {
    pendingAppeals = (await db.adminListPhotoAppeals()).length;
  } catch (e) {
    debugPrint('[AdminCounts] Einsprueche: $e');
  }

  int bans = 0;
  try {
    bans = (await db.fetchBannedEmails()).length;
  } catch (e) {
    debugPrint('[AdminCounts] Sperren: $e');
  }

  return AdminCounts(
    openReports: countOpenReports(reports),
    totalReports: reports.length,
    bugsLast24h: countBugsInWindow(bugs, w.dayAgo, w.now),
    bugsPrevious24h: countBugsInWindow(bugs, w.twoDaysAgo, w.dayAgo),
    bugsTotal: bugs.length,
    pendingVerifications: pendingVerifications,
    pendingAppeals: pendingAppeals,
    bans: bans,
  );
});

/// Erzwingt ein Neuladen der Kennzahlen.
///
/// Nach JEDER schreibenden Aktion in einem Tab aufzurufen: sonst zeigt die
/// Zeile weiter die Zahl von vor der Aktion, und der Admin glaubt, es sei
/// noch offen. Bewusst zentral - die Alternative (jeder Tab ruft es selbst)
/// ist bei sechs Tabs die Variante, die spaeter einer vergisst.
void refreshAdminCounts(WidgetRef ref) {
  ref.invalidate(adminCountsProvider);
}
