import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/screens/admin/admin_counts.dart';

/// Tests fuer die Kennzahlen-Zeile des Admin-Screens (ROADMAP Zeile 807).
///
/// Die Zaehlfunktionen sind bewusst aus dem Widget herausgezogen: sie
/// zeigen eine Zahl an, und ein Fehler darin faellt nicht als Absturz auf,
/// sondern als falsche Zahl im Admin-Screen.
void main() {
  // Fester Zeitpunkt statt DateTime.now(): die Fenstergrenzen sind der
  // eigentliche Gegenstand dieser Tests, und mit now() waeren sie flaky,
  // sobald der Testlauf ueber eine Grenze rutscht.
  Map<String, dynamic> bug(String iso) => {'createdAt': iso};

  // Aus EINEM Zeitpunkt abgeleitet, genau wie im Provider. Sonst prueft
  // der Test eine andere Konstellation als der Produktivcode.
  final w = bugsRecentWindows(DateTime.utc(2026, 3, 14, 12));
  final now = w.now;
  final dayAgo = w.dayAgo;
  final twoDaysAgo = w.twoDaysAgo;

  group('countOpenReports', () {
    test('zaehlt nur status pending', () {
      final reports = [
        {'status': 'pending'},
        {'status': 'pending'},
        {'status': 'resolved'},
        {'status': 'dismissed'},
      ];
      expect(countOpenReports(reports), 2);
    });

    test('leere Liste ergibt 0, nicht -1', () {
      expect(countOpenReports([]), 0);
    });

    test('Zeile ohne Status zaehlt nicht als offen', () {
      // Defensive: der Status kommt aus JSONB. Fehlt er, ist die Meldung
      // nicht als "offen" ausgewiesen - lieber zu niedrig als eine
      // Meldung als offen zu zaehlen, die es nicht mehr ist.
      expect(countOpenReports([{'id': 'x'}]), 0);
    });
  });

  group('countBugsInWindow', () {
    final bugs = [
      bug('2026-03-14T11:00:00Z'), // 1 h her, in [dayAgo, now)
      bug('2026-03-13T20:00:00Z'), // 16 h her, in [dayAgo, now)
      bug('2026-03-13T02:00:00Z'), // 34 h her, in [twoDaysAgo, dayAgo)
      bug('2026-03-11T12:00:00Z'), // 3 Tage her, ausserhalb
    ];

    test('die letzten 24 Stunden', () {
      expect(countBugsInWindow(bugs, dayAgo, now), 2);
    });

    test('die 24 bis 48 Stunden zurueck', () {
      expect(countBugsInWindow(bugs, twoDaysAgo, dayAgo), 1);
    });

    test('alte Bugs zaehlen in keinem Fenster', () {
      final old = [bug('2026-01-01T00:00:00Z')];
      expect(countBugsInWindow(old, dayAgo, now), 0);
      expect(countBugsInWindow(old, twoDaysAgo, dayAgo), 0);
    });

    test('exakte Grenze gehoert nur EINSEM Fenster zu (halboffen)', () {
      // Genau auf dayAgo, also exakt 24 Stunden alt: zaehlt zu den
      // JUNGEN 24 Stunden, nicht zu den vorigen. Beide Fenster sind
      // halboffen [von, bis) - waeren sie beide geschlossen, wuerde
      // dieser Zeitstempel doppelt gezaehlt und die Summe waere groesser
      // als bugsTotal.
      final exact = [bug('2026-03-13T12:00:00Z')];
      expect(countBugsInWindow(exact, dayAgo, now), 1);
      expect(countBugsInWindow(exact, twoDaysAgo, dayAgo), 0);
    });

    test('genau jetzt gehoert zu keinem Fenster', () {
      // now ist das obere Ende von [dayAgo, now) und damit ausgeschlossen.
      final atNow = [bug('2026-03-14T12:00:00Z')];
      expect(countBugsInWindow(atNow, dayAgo, now), 0);
    });

    test('die beiden Fenster überschneiden sich nicht', () {
      final beide = countBugsInWindow(bugs, dayAgo, now) +
          countBugsInWindow(bugs, twoDaysAgo, dayAgo);
      expect(beide, 3, reason: '4 Eintraege, einer davon aelter als 48 h');
      expect(beide, lessThanOrEqualTo(bugs.length));
    });

    test('Zeitstempel mit Zeitversatz landen im richtigen Fenster', () {
      // 2026-03-13T13:00:00+02:00 ist 11:00 UTC, also 25 Stunden her und
      // damit NICHT in den letzten 24 h. Ohne UTC-Vergleich wuerde es
      // faelschlich als neu zaehlen.
      final withOffset = [bug('2026-03-13T13:00:00+02:00')];
      expect(countBugsInWindow(withOffset, dayAgo, now), 0);
      expect(countBugsInWindow(withOffset, twoDaysAgo, dayAgo), 1);
    });

    test('unparsebarer Zeitstempel zaehlt in keinem Fenster', () {
      // Kaputter Zeitstempel darf die Kennzahl nicht still verschieben.
      final broken = <Map<String, dynamic>>[
        {'createdAt': 'kein-datum'},
        {'createdAt': null},
        <String, dynamic>{},
      ];
      expect(countBugsInWindow(broken, twoDaysAgo, now), 0);
    });

    test('Gegenprobe: Fenster umgekehrt ergibt 0', () {
      // Ohne diese Absicherung wuerde ein vertauschtes from/to im
      // Provider jede Zahl als "Anstieg" melden.
      expect(countBugsInWindow(bugs, now, dayAgo), 0);
    });
  });

  group('bugsRecentWindows', () {
    test('beide Fenster haengen an DEMSELBEN jetzt', () {
      // Der Grund fuer diese Funktion: zwei getrennte now()-Aufrufe
      // liegen Mikrosekunden auseinander, und ein Zeitstempel genau in
      // diesem Spalt gehoerte zu keinem Fenster - oder zu beiden.
      final w = bugsRecentWindows(DateTime.utc(2026, 3, 14, 12));
      expect(w.now.difference(w.dayAgo), const Duration(hours: 24));
      expect(w.dayAgo.difference(w.twoDaysAgo), const Duration(hours: 24));
      expect(w.now.isUtc, isTrue);
    });

    test('die Grenze ist genau 24 Stunden zurueck', () {
      final w = bugsRecentWindows(DateTime.utc(2026, 3, 14, 12));
      expect(w.dayAgo, DateTime.utc(2026, 3, 13, 12));
      expect(w.twoDaysAgo, DateTime.utc(2026, 3, 12, 12));
    });

    test('lokale Zeit wird auf UTC normalisiert', () {
      final w = bugsRecentWindows(DateTime.utc(2026, 3, 14, 12).toLocal());
      expect(w.now.isUtc, isTrue);
      expect(w.now.hour, 12);
    });
  });

  group('AdminCounts.bugsRising', () {
    AdminCounts counts(int last24, int prev24) => AdminCounts(
      openReports: 0,
      totalReports: 0,
      bugsLast24h: last24,
      bugsPrevious24h: prev24,
      bugsTotal: last24 + prev24,
      pendingVerifications: 0,
      pendingAppeals: 0,
      bans: 0,
    );

    test('Verdopplung bei genueend Menge meldet Anstieg', () {
      expect(counts(6, 2).bugsRising, isTrue);
    });

    test('1 -> 2 meldet KEINEN Anstieg', () {
      // Ohne Mindestmenge waere jede Fehlbedienung ein Alarm.
      expect(counts(2, 1).bugsRising, isFalse);
      expect(counts(1, 0).bugsRising, isFalse);
    });

    test('gleichbleibende Zahl meldet keinen Anstieg', () {
      expect(counts(4, 4).bugsRising, isFalse);
      expect(counts(4, 9).bugsRising, isFalse);
    });

    test('0 meldet keinen Anstieg', () {
      expect(counts(0, 0).bugsRising, isFalse);
    });
  });

  group('AdminCounts.unknown', () {
    test('isLoaded ist false und Werte sind -1', () {
      // -1 statt 0: eine echte Null heisst "nichts offen", -1 heisst
      // "noch nicht bekannt". Sonst wuerde die Zeile im Ladezustand
      // behaupten, es sei nichts zu tun.
      expect(AdminCounts.unknown.isLoaded, isFalse);
      expect(AdminCounts.unknown.openReports, -1);
      expect(AdminCounts.unknown.bugsLast24h, -1);
    });

    test('eine echte Null gilt als geladen', () {
      const loaded = AdminCounts(
        openReports: 0,
        totalReports: 0,
        bugsLast24h: 0,
        bugsPrevious24h: 0,
        bugsTotal: 0,
        pendingVerifications: 0,
        pendingAppeals: 0,
        bans: 0,
      );
      expect(loaded.isLoaded, isTrue);
      expect(loaded.bugsRising, isFalse);
    });
  });

  group('filterBans', () {
    final bans = [
      {
        'email': 'anna@example.com',
        'reason': 'Beleidigung im Chat',
        'bannedBy': 'admin-1',
      },
      {
        'email': 'bernd@example.com',
        'reason': 'Fake-Profil',
        'bannedBy': 'admin-2',
      },
      {'email': 'clara@example.com', 'reason': '', 'bannedBy': 'admin-1'},
    ];

    test('leere Suche liefert alles zurueck', () {
      expect(filterBans(bans, '').length, 3);
      expect(filterBans(bans, '   ').length, 3);
    });

    test('findet ueber die E-Mail, ohne Gross-/Kleinschreibung', () {
      final out = filterBans(bans, 'BERND');
      expect(out.length, 1);
      expect(out.first['email'], 'bernd@example.com');
    });

    test('findet ueber die Begruendung', () {
      // Der Fall, der den Suchbegriff ueberhaupt rechtfertigt: der Admin
      // kennt den Absender nicht, aber das Stichwort aus der Meldung.
      final out = filterBans(bans, 'beleidigung');
      expect(out.length, 1);
      expect(out.first['email'], 'anna@example.com');
    });

    test('findet ueber die sperrende Person', () {
      final out = filterBans(bans, 'admin-2');
      expect(out.length, 1);
      expect(out.first['email'], 'bernd@example.com');
    });

    test('Teilstring matcht', () {
      expect(filterBans(bans, 'example.com').length, 3);
      expect(filterBans(bans, 'anna@').length, 1);
    });

    test('Leerzeichen aussen werden ignoriert', () {
      expect(filterBans(bans, '  anna  ').length, 1);
    });

    test('kein Treffer ergibt leere Liste, nicht die ganze', () {
      final out = filterBans(bans, 'gibtesnicht');
      expect(out, isEmpty);
    });

    test('fehlende Felder erzeugen keinen Treffer und keinen Absturz', () {
      final sparse = <Map<String, dynamic>>[
        {'email': 'dora@example.com'},
        <String, dynamic>{},
      ];
      expect(filterBans(sparse, 'dora').length, 1);
      expect(filterBans(sparse, '').length, 2);
      expect(filterBans(sparse, 'null').length, 0);
    });

    test('Filter veraendert die Originalliste nicht', () {
      final original = List<Map<String, dynamic>>.from(bans);
      filterBans(bans, 'anna');
      expect(bans.length, original.length);
    });
  });
}
