"""Beobachtet Transit Spark live - waehrend du auf den zwei Handys testest.

WARUM (08.11.2026): Der BLE-Test auf zwei echten Geraeten ist das
einzige, was sich nicht am Schreibtisch pruefen laesst. Statt auf den
Handys im Log zu wuehlen, zeigt dieses Werkzeug, was **serverseitig**
passiert:

* `transit_signals` - wer hat gefunkt, wurde jemandem zugeordnet
* `transit_soft_pings` - der Ping (die Gegenseite wurde begruesst)
* `matches` - der Funke daraus
* `net.http_request_queue` - **jede Zeile ist ein Push-Aufruf**. Hier
  sieht man unmittelbar, ob ein Ereignis EINE Meldung oder drei
  erzeugt (Befund 08.11.2026: ein Transit-Funke erzeugte vier).

Aufruf (in einem zweiten Fenster, waehrend du testest):
    python tool/watch_transit.py            # beobachtet alle 5 Sekunden
    python tool/watch_transit.py --sekunden 2
    python tool/watch_transit.py --konto 46f3f558-b134-4d25-946b-4e052a8ab3b5

Beenden mit Strg+C.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMP = pathlib.Path(os.environ["TEMP"]) / "opencode"


def sql(text):
    datei = TEMP / "watch.sql"
    datei.write_text(text, encoding="utf-8")
    ausgabe = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(datei)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    ).stdout
    roh = ausgabe.strip()
    if not roh.startswith(("{", "[")):
        return []
    try:
        daten = json.loads(roh)
    except json.JSONDecodeError:
        return []
    return daten.get("rows", [])


def zeit(zeile):
    return str(zeile.get("zeit", ""))[:19]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sekunden", type=int, default=5)
    ap.add_argument("--konto", default="", help="nur dieses Konto beobachten")
    ap.add_argument("--laufzeit", type=int, default=0,
                    help="nach so vielen Sekunden selbst beenden (0 = endlos)")
    args = ap.parse_args()

    konto = args.konto
    print("=" * 74)
    print("TRANSIT-BEOBACHTER - laeuft. Zum Beenden: Strg+C")
    print("=" * 74)
    print()
    print("  Ich zeige: das Ereignis (Signal/Ping/Funke) und die daraus")
    print("  erzeugten Push-Aufrufe. Ein Ereignis sollte EINE Meldung")
    print("  ergeben - wenn du drei oder vier siehst, ist es wieder doppelt.")
    print()

    gesehen_signale = set()
    gesehen_pings = set()
    gesehen_matches = set()
    gesehen_pushes = set()
    letzte_ausgabe = 0.0
    ende = time.time() + args.laufzeit if args.laufzeit else None

    while True:
        if ende and time.time() > ende:
            print()
            print("  Beendet (%d Sekunden beobachtet)." % args.laufzeit)
            return 0
        kuerzel = (" WHERE (user_id = '%s' OR matched_with = '%s')" % (konto, konto)) if konto else ""

        for zeile in sql(
            "SELECT id, user_id, matched_with, status, created_at AS zeit "
            "FROM public.transit_signals" + kuerzel +
            " ORDER BY created_at DESC LIMIT 20;"
        ):
            schluessel = zeile.get("id")
            if schluessel in gesehen_signale:
                continue
            gesehen_signale.add(schluessel)
            print("  [%s] SIGNAL    von %s  Status: %-9s  zugeordnet: %s"
                  % (zeit(zeile), str(zeile.get("user_id"))[:8],
                     zeile.get("status"), str(zeile.get("matched_with"))[:8]))

        for zeile in sql(
            "SELECT id, sender, recipient, status, created_at AS zeit "
            "FROM public.transit_soft_pings" + kuerzel +
            " ORDER BY created_at DESC LIMIT 20;"
        ):
            schluessel = zeile.get("id")
            if schluessel in gesehen_pings:
                continue
            gesehen_pings.add(schluessel)
            print("  [%s] PING      von %s  an %s  Status: %s"
                  % (zeit(zeile), str(zeile.get("sender"))[:8],
                     str(zeile.get("recipient"))[:8], zeile.get("status")))

        for zeile in sql(
            "SELECT id, user_one_id, user_two_id, status, created_at AS zeit "
            "FROM public.matches" + kuerzel +
            " ORDER BY created_at DESC LIMIT 20;"
        ):
            schluessel = zeile.get("id")
            if schluessel in gesehen_matches:
                continue
            gesehen_matches.add(schluessel)
            print("  [%s] FUNKE     %s <-> %s  Status: %s"
                  % (zeit(zeile), str(zeile.get("user_one_id"))[:8],
                     str(zeile.get("user_two_id"))[:8], zeile.get("status")))

        # Jede Zeile in der Queue ist EIN Push-Aufruf.
        for zeile in sql("""
SELECT id,
       convert_from(body, 'UTF8')::jsonb ->> 'kind' AS art,
       convert_from(body, 'UTF8')::jsonb ->> 'target_user_id' AS empfaenger,
       convert_from(body, 'UTF8')::jsonb ->> 'title' AS titel,
       created_at AS zeit
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%'
 ORDER BY id;
"""):
            schluessel = zeile.get("id")
            if schluessel in gesehen_pushes:
                continue
            gesehen_pushes.add(schluessel)
            print("  [%s] PUSH      Art: %-10s an %s  \"%s\""
                  % (zeit(zeile), zeile.get("art"),
                     str(zeile.get("empfaenger"))[:8], zeile.get("titel")))

        jetzt = time.time()
        if jetzt - letzte_ausgabe > 30:
            letzte_ausgabe = jetzt
            version = sql("SELECT current_setting('server_version') AS v;")
            print("  ... (%s | PostgreSQL %s | wartend auf Ereignisse)"
                  % (time.strftime("%H:%M:%S"),
                     version[0].get("v") if version else "?"))
        time.sleep(max(1, args.sekunden))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print("  Beendet.")
        sys.exit(0)
