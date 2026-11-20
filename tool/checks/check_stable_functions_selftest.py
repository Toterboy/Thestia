#!/usr/bin/env python3
"""Selbsttest fuer check_stable_functions.py.

WARUM DIESER TEST: Ein Pruefer, der nichts findet, ist nicht von einem
Pruefer zu unterscheiden, der kaputt ist. Dieser Selbsttest legt
absichtlich einen Fehler an und verlangt, dass der Pruefer ihn MELDET.

Geprueft werden drei Faelle:

  1) Eine STABLE-Funktion, die den Rate-Limit benutzt -> muss
     gemeldet werden (das ist der Fehler aus Migration 221).
  2) Dieselbe Funktion als VOLATILE -> darf NICHT gemeldet werden.
  3) Eine STABLE-Funktion, die spaeter per ALTER FUNCTION ... VOLATILE
     repariert wurde -> darf NICHT gemeldet werden (der Endzustand
     zaehlt).

Aufruf::

    python tool/checks/check_stable_functions_selftest.py
"""

import pathlib
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check_stable_functions as pruefer  # noqa: E402


STABLE_SCHREIBT = """
-- Test: eine STABLE-Funktion, die in die Datenbank schreibt.
CREATE OR REPLACE FUNCTION public.test_stable_schreibt()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.consume_rate_limit('test', 5, 3600) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN '{}'::jsonb;
END;
$$;
"""

VOLATILE_SCHREIBT = STABLE_SCHREIBT.replace("STABLE", "VOLATILE")

STABLE_MIT_ALTER = STABLE_SCHREIBT + """
-- Test: die Reparatur per ALTER (so hat Migration 221 es gemacht).
ALTER FUNCTION public.test_stable_schreibt() VOLATILE;
"""

STABLE_LESTEND = """
-- Test: eine STABLE-Funktion, die wirklich nur liest.
CREATE OR REPLACE FUNCTION public.test_liest()
RETURNS int
LANGUAGE sql
STABLE
AS $$
  SELECT 1;
$$;
"""


def pruefe_mit(sql: str, erwartet: int, name: str) -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        ordner = pathlib.Path(tmp)
        (ordner / "001_test.sql").write_text(sql, encoding="utf-8")
        befunde = pruefer.statisch_pruefen(ordner)
    if len(befunde) != erwartet:
        print("FEHLER (%s): erwartet %d Befund(e), gefunden %d"
              % (name, erwartet, len(befunde)))
        for befund in befunde:
            print("    ", befund)
        return False
    print("OK: %s (%d Befund(e))" % (name, len(befunde)))
    return True


def main() -> int:
    ok = True
    ok &= pruefe_mit(STABLE_SCHREIBT, 1, "STABLE-Funktion mit Schreiber")
    ok &= pruefe_mit(VOLATILE_SCHREIBT, 0, "VOLATILE-Funktion mit Schreiber")
    ok &= pruefe_mit(STABLE_MIT_ALTER, 0, "STABLE, per ALTER repariert")
    ok &= pruefe_mit(STABLE_LESTEND, 0, "STABLE-Funktion, die nur liest")

    # Und noch einmal gegen das echte Repository: dort darf es keinen
    # Befund geben (Migration 221 hat repariert).
    befunde = pruefer.statisch_pruefen()
    if befunde:
        print("FEHLER: Im Repository gibt es %d Befund(e):" % len(befunde))
        for befund in befunde:
            print("    ", befund)
        ok = False
    else:
        print("OK: Das Repository ist sauber")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
