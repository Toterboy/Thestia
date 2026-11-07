#!/usr/bin/env python3
"""Findet Funktionen, die etwas zurueckgeben sollen, aber kein RETURN
haben.

BEFUND (07.11.2026, Betreiber): "Nachrichten kommen noch immer nicht an."

DIE URSACHE (live gemessen): Der Aufruf von public.relay_store
antwortete mit

    HTTP 400  query has no destination for result data

Die Funktion endete mit

    INSERT INTO public.direct_message_relay ...
    RETURNING id;
  END;

In PL/pgSQL ist ein blosses "RETURNING id;" aber KEIN RETURN - es ist
nur ein SQL-Befehl, dessen Ergebnis verworfen wird. Die Funktion laeuft
danach ins Ende, ohne einen Wert zu liefern. Da sie RETURNS bigint
deklariert ist, meldet PostgreSQL genau diesen Fehler.

Das heisst: das Relay hat NIE funktioniert. Jede Nachricht, die ueber
den Relay-Weg ging (also genau dann, wenn der Direktkanal nicht steht -
im Mobilfunk, hinter einem Router oder ohne TURN), wurde verworfen.

WARUM EIN WERKZEUG: Der Fehler ist still. Die App merkt nichts, der
Nutzer sieht nur, dass nichts ankommt. Und ein Test der nur den
Quelltext liest, sieht es auch nicht - man muss die Funktion aufrufen.
Diese Pruefung fragt die Datenbank, welche Funktionen betroffen sind.

Aufruf::

    python tool/check_function_returns.py
"""

import json
import pathlib
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

SQL = """
SELECT p.proname,
       p.oid::regprocedure::text AS sig,
       p.prorettype::regtype::text AS rueckgabe,
       l.lanname AS sprache,
       p.prosrc ~* 'returning' AS hat_returning,
       p.prosrc ~* 'return\\s+[^i]' AS hat_return
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
 WHERE n.nspname = 'public'
   AND p.prokind = 'f'
   -- NUR PL/pgSQL: In einer SQL-Funktion ist "RETURNING" gerade die
   -- Rueckgabe (die letzte Anweisung liefert die Zeilen). Der Fehler
   -- tritt nur in PL/pgSQL auf, wo ein RETURN noetig ist.
   AND l.lanname = 'plpgsql'
   AND p.prorettype <> 'void'::regtype
   AND p.prorettype <> 'trigger'::regtype
   AND p.prorettype <> 'event_trigger'::regtype
   AND p.prosrc ~* 'returning'
   AND p.prosrc !~* 'return\\s+[^i]'
 ORDER BY p.proname, sig;
"""


def hole_zeilen():
    pfad = ROOT / "supabase" / "_pruef_returns.sql"
    pfad.write_text(SQL, encoding="utf-8")
    ergebnis = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(pfad)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    pfad.unlink(missing_ok=True)
    kombi = ergebnis.stdout + ergebnis.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        return None, kombi[:300]
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception as e:  # noqa: BLE001
        return None, str(e)[:200]
    if obj.get("_tag") == "Error":
        return None, json.dumps(obj)[:300]
    return obj.get("rows", []), None


def main() -> int:
    print("=" * 70)
    print("FUNKTIONEN: gibt es zurueck, ohne zurueckzugeben?")
    print("=" * 70)

    zeilen, fehler = hole_zeilen()
    if zeilen is None:
        print("  ! Die Funktionen sind nicht lesbar: %s" % (fehler or "")[:250])
        return 1

    if not zeilen:
        print()
        print("  OK: jede Funktion mit einem Rueckgabewert gibt ihn auch"
              " wirklich zurueck.")
        print("      (Ein 'RETURNING' ohne 'RETURN' waere hier aufgefallen -")
        print("       der Aufruf waere mit 400 'query has no destination for")
        print("       result data' gescheitert.)")
        return 0

    print()
    print("  X %d Funktion(en) geben einen Wert zurueck, ohne ihn"
          " zurueckzugeben:" % len(zeilen))
    for z in zeilen:
        print()
        print("      %s" % z["sig"])
        print("        Rueckgabetyp: %s" % z["rueckgabe"])
        print("        -> JEDER Aufruf scheitert mit 400 'query has no")
        print("           destination for result data'.")
    print()
    print("  Loesung: 'RETURNING x INTO v;' und am Ende 'RETURN v;'.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
