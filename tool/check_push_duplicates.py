"""Prueft: ein Ereignis, eine Benachrichtigung.

BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen fuer
das Selbe."

DIE FEHLERKLASSE (live gemessen, nicht vermutet):
Der Like-Versand lief ZWEIMAL - einmal ueber den DB-Trigger
(notify_push_trigger) und einmal ueber einen Aufruf der App. Dazu kam
der Transit-Weg, der fuer EINEN Funke drei Zeilen anlegte (zwei
technische Likes, ein Match, ein Soft-Ping) und damit bis zu vier
Push-Aufrufe erzeugte - beide Seiten bekamen je zwei Meldungen.

DAS GATE hat zwei Teile:

1. STATISCH (laeuft im CI, ohne Datenbank):
   * Kein Dart-Code darf `notify-user` mit kind='likes' aufrufen - der
     Like-Versand ist Sache des Triggers. Sonst kommt die zweite
     Meldung zurueck.
   * Die Edge Function muss Client-Aufrufe mit kind='likes' ablehnen.
   * Die Migration muss die beiden Regeln enthalten (Transit-Markierung
     und Match-Pruefung).

2. LIVE (nur mit --live, braucht das verknuepfte Projekt):
   * `tool/measure_push_duplicates.sql` zaehlt die Push-Aufrufe, ohne
     dass eine einzige Nachricht rausgeht (Transaktion + ROLLBACK).
     Geprueft werden die vier Szenarien.

Aufruf:
    python tool/check_push_duplicates.py          # statisch (CI)
    python tool/check_push_duplicates.py --live   # + Live-Messung
"""
import json
import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
if "--root" in sys.argv:
    # Der Selbsttest (tool/check_push_duplicates_selftest.py) baut einen
    # temporaeren Baum und ruft das Gate darauf auf.
    ROOT = pathlib.Path(sys.argv[sys.argv.index("--root") + 1])
LIB = ROOT / "lib"
FUNKTION = ROOT / "supabase" / "functions" / "notify-user" / "index.ts"
MESSUNG = ROOT / "tool" / "measure_push_duplicates.sql"

# Die erwarteten Push-Aufrufe je Szenario (live gemessen am 08.11.2026
# mit Migration 200). Vorher war der Transit-Funke bei 4.
SOLL = {
    "1 Transit-Funke": 2,
    "2 Profil-Like (einseitig)": 1,
    "3a Match entsteht": 2,
    "3b zweiter Like (Match besteht)": 0,
    "4 Soft-Ping (ohne Funke)": 1,
}

# Wer muss bei einem Ereignis benachrichtigt werden?
SOLL_EMPFAENGER = {
    "1 Transit-Funke": {"A": 1, "B": 1},
    "2 Profil-Like (einseitig)": {"B": 1},
    "3a Match entsteht": {"A": 1, "B": 1},
    "3b zweiter Like (Match besteht)": {},
    "4 Soft-Ping (ohne Funke)": {"B": 1},
}


def statische_pruefungen():
    ok = True
    print("STATISCHE PRUEFUNGEN")
    print("=" * 70)

    # --- 1) Kein Client-Aufruf mit kind='likes' -------------------------
    treffer = []
    muster = re.compile(
        r"notify-user[\s\S]{0,240}?'kind'\s*:\s*'likes'", re.I)
    for datei in sorted(LIB.rglob("*.dart")):
        text = datei.read_text(encoding="utf-8", errors="replace")
        if muster.search(text):
            treffer.append(datei.relative_to(ROOT))
    if treffer:
        print("  X Der Client ruft notify-user mit kind='likes' auf:")
        for t in treffer:
            print("      %s" % t)
        print("    -> der DB-Trigger schickt den Like-Push bereits. Ein")
        print("       Client-Aufruf erzeugt die ZWEITE Meldung (Befund")
        print("       08.11.2026).")
        ok = False
    else:
        print("  OK  kein Client ruft notify-user mit kind='likes' auf.")

    # --- 2) Die Edge Function lehnt Client-Likes ab ----------------------
    if not FUNKTION.exists():
        print("  X notify-user/index.ts fehlt.")
        ok = False
    else:
        text = FUNKTION.read_text(encoding="utf-8", errors="replace")
        if "kind_server_only" not in text:
            print("  X notify-user lehnt Client-Aufrufe mit kind='likes' NICHT ab.")
            print("    -> ohne diese Sperre kommt die Doppelmeldung zurueck,")
            print("       sobald jemand den Aufruf wieder einbaut.")
            ok = False
        else:
            print("  OK  notify-user lehnt Client-Aufrufe mit kind='likes' ab.")

    # --- 3) Die Migration enthaelt die beiden Regeln --------------------
    migration = ROOT / "supabase" / "migrations" / "200_push_duplicate_fix.sql"
    if not migration.exists():
        print("  X Migration 200 fehlt.")
        ok = False
    else:
        text = migration.read_text(encoding="utf-8", errors="replace")
        regeln = {
            "source = 'transit' (technische Likes markiert)":
                "'transit'" in text,
            "Like-Push nur bei source='profile'":
                "IS DISTINCT FROM 'profile'" in text,
            "Like-Push entfaellt bei bestehendem Funke":
                "public.matches m" in text,
            "Soft-Ping-Push entfaellt bei bestehendem Funke":
                "notify_soft_ping_trigger" in text and "NEW.sender" in text,
            "Soft-Ping nutzt das aktuelle Secret":
                "thestia_internal_secret" in text,
        }
        for name, vorhanden in regeln.items():
            if vorhanden:
                print("  OK  %s" % name)
            else:
                print("  X %s fehlt in Migration 200." % name)
                ok = False

    return ok


def live_pruefung():
    """Zaehlt die Push-Aufrufe live (Transaktion + ROLLBACK)."""
    print()
    print("LIVE-MESSUNG (Transaktion + ROLLBACK - es geht keine Nachricht raus)")
    print("=" * 70)

    ergebnis = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(MESSUNG)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    kombi = ergebnis.stdout + ergebnis.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        print("  (Messung nicht lesbar - ist das Projekt verknuepft?)")
        print(kombi[:400])
        return None

    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except json.JSONDecodeError:
        print("  (Messung nicht lesbar)")
        return None

    zeilen = obj.get("rows", [])
    if not zeilen:
        print("  (keine Zeilen)")
        return None

    # Die letzte Ergebnismenge enthaelt die Szenarien mit Empfaenger.
    szenarien = {}
    for z in zeilen:
        name = z.get("szenario")
        if not name:
            continue
        eintrag = szenarien.setdefault(name, {"anzahl": 0, "empfaenger": {}})
        eintrag["anzahl"] += 1
        empfaenger = z.get("empfaenger")
        if empfaenger:
            eintrag["empfaenger"][empfaenger] = \
                eintrag["empfaenger"].get(empfaenger, 0) + 1

    ok = True
    for name, soll in SOLL.items():
        ist = szenarien.get(name, {"anzahl": 0, "empfaenger": {}})
        marker = "OK " if ist["anzahl"] == soll else "X  "
        if ist["anzahl"] != soll:
            ok = False
        print("  %s %-34s %d Aufruf(e) (soll: %d)"
              % (marker, name, ist["anzahl"], soll))
        soll_empf = SOLL_EMPFAENGER.get(name, {})
        if ist["empfaenger"] != soll_empf:
            ok = False
            print("       X Empfaenger: %s (soll: %s)"
                  % (ist["empfaenger"], soll_empf))
        elif soll_empf:
            print("       OK  Empfaenger: %s" % ist["empfaenger"])

    return ok


def main():
    print("=" * 70)
    print("PRUEFUNG: ein Ereignis, eine Benachrichtigung")
    print("=" * 70)
    print()
    ok = statische_pruefungen()

    if "--live" in sys.argv:
        live = live_pruefung()
        if live is None:
            print()
            print("SKIP: die Live-Messung war nicht moeglich.")
        else:
            ok = live and ok

    print()
    if ok:
        print("OK: ein Ereignis, eine Benachrichtigung.")
        return 0
    print("FEHLER: siehe oben.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
