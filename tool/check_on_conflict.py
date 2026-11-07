#!/usr/bin/env python3
"""Prueft, ob jede Funktion ihre ON-CONFLICT-Ziele auch bedienen kann.

WARUM (07.11.2026, Betreiber): "Bei Dating Hour finden sich die
Partner nicht (zwei user drin (meine geräte)) und es passiert nichts."

DIE URSACHE: Die Paarungsrunde sagt
    ON CONFLICT (event_id, user_a, user_b) DO NOTHING
der Unique-Index lautet aber
    CREATE UNIQUE INDEX ... (event_id, user_a, user_b) WHERE (ended_at IS NULL)

Ein PARTIELLER Index traegt ein ON-CONFLICT-Ziel nur, wenn die
Bedingung GENAU dieselbe ist. Sonst: 42P10 - und die Funktion
arbeitet einfach nicht. Im Cron-Log faellt so etwas nicht auf; in der
App sieht man nur "sie suchen sich" und wartet.

Diese Pruefung laeuft gegen die PRODUKTIVDATENBANK: sie fragt die
tatsaechlichen Funktionen und die tatsaechlichen Indizes ab. Damit
gilt sie fuer den Stand, der laeuft - nicht fuer eine Vermutung
ueber den Quelltext.

Aufruf::

    python tool/check_on_conflict.py
"""

import json
import pathlib
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

SQL_FUNKTIONEN = """
SELECT p.proname,
       p.oid::regprocedure::text AS sig,
       p.prosrc
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc ILIKE '%on conflict%'
 ORDER BY p.proname;
"""

SQL_INDIZES = """
SELECT i.indrelid::regclass::text AS tabelle,
       i.indexrelid::regclass::text AS indexname,
       pg_get_indexdef(i.indexrelid) AS def,
       coalesce(pg_get_expr(i.indpred, i.indrelid), '') AS bedingung,
       array_to_string(ARRAY(
         SELECT a.attname::text
           FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
           JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
          ORDER BY k.ord), ',') AS spalten
  FROM pg_index i
 WHERE i.indisunique
   AND i.indrelid IN (
     SELECT oid FROM pg_class
      WHERE relnamespace = 'public'::regnamespace AND relkind = 'r')
 ORDER BY i.indexrelid::regclass::text;
"""


def query(sql_text):
    sql = ROOT / "supabase" / "_pruef_on_conflict.sql"
    sql.write_text(sql_text, encoding="utf-8")
    ergebnis = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(sql)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    sql.unlink(missing_ok=True)
    kombi = ergebnis.stdout + ergebnis.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        return None, kombi
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception as e:                                   # noqa: BLE001
        return None, "%s | %s" % (e, kombi[:400])
    if obj.get("_tag") == "Error":
        return None, json.dumps(obj)[:500]
    return obj.get("rows", []), None


def norm(text):
    """Normalisiert eine Bedingung fuer den Vergleich.

    Leerzeichen egal, aber der Wortlaut muss uebereinstimmen - ein
    Index mit "ended_at IS NULL" traegt ein Konflikt-Ziel nur bei
    genau "ended_at IS NULL".
    """
    if not text:
        return ""
    return " ".join(text.lower().replace("(", " ").replace(")", " ")
                    .split())


def main() -> int:
    print("=" * 70)
    print("ON CONFLICT: kann der Server jedes Ziel bedienen?")
    print("=" * 70)

    funktionen, fehler1 = query(SQL_FUNKTIONEN)
    if funktionen is None:
        print("  ! Die Funktionen sind nicht lesbar: %s" % (fehler1 or "")[:200])
        return 1
    indizes, fehler2 = query(SQL_INDIZES)
    if indizes is None:
        print("  ! Die Indizes sind nicht lesbar: %s" % (fehler2 or "")[:200])
        return 1

    print()
    print("  %d Funktionen mit ON CONFLICT, %d eindeutige Indizes"
          % (len(funktionen), len(indizes)))

    import re

    fehler_liste = []
    for f in funktionen:
        body = f["prosrc"] or ""
        for m in re.finditer(
                r"ON\s+CONFLICT\s*\(([^)]*)\)\s*"
                r"(?:WHERE\s+(.+?)\s+)?DO\s+(?:NOTHING|UPDATE|SET)",
                body, re.I | re.S):
            spalten = tuple(s.strip().lower() for s in m.group(1).split(","))
            bedingung = norm(m.group(2) or "")
            # Ein Index passt, wenn er dieselben Spalten hat UND
            # dieselbe Bedingung (beide leer oder beide gleich).
            passend = []
            for i in indizes:
                if tuple(s.strip() for s in (i["spalten"] or "").split(",")) != spalten:
                    continue
                index_bedingung = norm(i["bedingung"] or "")
                if index_bedingung == bedingung:
                    passend.append(i)
            if not passend:
                # Kandidaten mit denselben Spalten aber anderer Bedingung
                andere = [
                    i for i in indizes
                    if tuple(s.strip() for s in (i["spalten"] or "").split(","))
                    == spalten
                ]
                fehler_liste.append((f["sig"], spalten, bedingung, andere))

    print()
    if fehler_liste:
        print("  X %d ON-CONFLICT-Ziel(e) kann der Server nicht bedienen:"
              % len(fehler_liste))
        print("    (42P10 - die Funktion arbeitet nicht, und im Cron-Log")
        print("     faellt es nicht auf)")
        for sig, spalten, bedingung, andere in fehler_liste:
            print()
            print("    %s" % sig)
            print("      verlangt: (%s)%s"
                  % (", ".join(spalten),
                     (" WHERE " + bedingung) if bedingung else ""))
            for i in andere:
                print("      vorhanden: %s  %s"
                      % (i["indexname"],
                         ("WHERE " + (i["bedingung"] or "")) if i["bedingung"]
                         else "(ohne Bedingung)"))
            if not andere:
                print("      vorhanden: KEIN Index mit genau diesen Spalten")
        return 1

    print("  OK: jedes ON-CONFLICT-Ziel hat einen passenden Index.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
