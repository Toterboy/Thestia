#!/usr/bin/env python3
"""Prueft die Geschlechtsregel der Dating Hour am lebenden Server.

WARUM (14.11.2026, Betreiber): "Bei Dating Hour irgendwie umsetzen, dass
von beiden Geschlechtern welche in dem Event sind, wenn alle Hetero."

Die Regel sitzt im Server (Migration 216 + 217): die Paarung beachtet
die Geschlechtswahl - beidseitig. Bevor sie das tat, hat die Paarung
die Wahl NIE beachtet: ein Nutzer, der nur Frauen suchte, konnte mit
einem Mann gepaart werden.

DAS WERKZEUG fragt die ECHTE Datenbank, wie die Regel auf konkrete
Faelle antwortet. Es aendert nichts - es rechnet nur.

Die Faelle:

  1) Mann (nichts gewaehlt) + Frau (nichts gewaehlt)   -> passt
     (das hetero Event: Mann und Frau kommen zusammen)
  2) Mann (nur Frauen) + Frau (nur Maenner)           -> passt
  3) Mann (nur Maenner) + Frau (nur Frauen)           -> passt NICHT
     (beide wollen ausdruecklich das eigene Geschlecht)
  4) Mann (nur Maenner) + Mann (nur Maenner)           -> passt
  5) Mann (nichts) + Mann (nichts)                    -> passt NICHT
     (das hetero Event: kein Same-Sex-Paar)
  6) Mann (Alle gewaehlt) + Mann (Alle gewaehlt)      -> passt
     ("Alle" heisst: offen)
  7) Frau (nur Frauen) + Mann (nichts)                -> passt NICHT
     (SIE will ihn nicht - die Pruefung ist beidseitig)
  8) Mann (nichts) + Frau (nur Frauen)                -> passt NICHT
     (ER will sie nicht)
  9) Trans Mann (nur Frauen) + Frau (nur Maenner)    -> passt
 10) Divers (nichts) + Mann (nichts)                  -> passt

Aufruf::

    python tool/checks/check_dating_hour_gender_mix.py

Endet mit Exitcode 1, wenn der Server eine andere Antwort gibt als
die Regel vorsieht.
"""

import json
import pathlib
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zaehlen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe aendert.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()


# (Beschreibung, SQL-Parameter, erwartetes Ergebnis)
# Die Praeferenz-Listen sind die Werte aus profiles.gender_preferences.
FAELLE = [
    (
        "Mann (nichts gewaehlt) + Frau (nichts gewaehlt)",
        "'male', '{}'::text[], 'female', '{}'::text[]",
        True,
    ),
    (
        "Mann (nur Frauen) + Frau (nur Maenner)",
        "'male', array['female'], 'female', array['male']",
        True,
    ),
    (
        "Mann (nur Maenner) + Frau (nur Frauen) - beide wollen das eigene",
        "'male', array['male'], 'female', array['female']",
        False,
    ),
    (
        "Mann (nur Maenner) + Mann (nur Maenner)",
        "'male', array['male'], 'male', array['male']",
        True,
    ),
    (
        "Mann (nichts) + Mann (nichts) - hetero Event, kein Same-Sex-Paar",
        "'male', '{}'::text[], 'male', '{}'::text[]",
        False,
    ),
    (
        "Mann (Alle gewaehlt) + Mann (Alle gewaehlt) - offen",
        "'male', array['male','female','diverse','other'], "
        "'male', array['male','female','diverse','other']",
        True,
    ),
    (
        "Frau (nur Frauen) + Mann (nichts) - SIE will ihn nicht",
        "'female', array['female'], 'male', '{}'::text[]",
        False,
    ),
    (
        "Mann (nichts) + Frau (nur Frauen) - ER will sie nicht",
        "'male', '{}'::text[], 'female', array['female']",
        False,
    ),
    (
        "Trans Mann (nur Frauen) + Frau (nur Maenner)",
        "'male_trans', array['female'], 'female', array['male']",
        True,
    ),
    (
        "Divers (nichts) + Mann (nichts)",
        "'diverse', '{}'::text[], 'male', '{}'::text[]",
        True,
    ),
]


def sql_bauen() -> str:
    # EIN Query mit UNION ALL: der CLI gibt bei mehreren Abfragen nur die
    # letzte zurueck - deshalb alles in eins.
    teile = []
    for nummer, (beschreibung, params, erwartet) in enumerate(FAELLE, 1):
        teile.append(
            "select {n} as nr, '{b}' as beschreibung, {e}::boolean as erwartet, "
            "public.dh_gender_compatible({p}) as ist".format(
                n=nummer,
                b=beschreibung.replace("'", "''"),
                e="true" if erwartet else "false",
                p=params,
            )
        )
    return "\nunion all\n".join(teile) + " order by nr;\n"


def ausfuehren(sql: str) -> list[dict]:
    datei = ROOT / "_tmp_dating_hour_gender_mix.sql"
    datei.write_text(sql, encoding="utf-8", newline="\n")
    cli = "supabase.cmd" if sys.platform == "win32" else "supabase"
    try:
        ergebnis = subprocess.run(
            [cli, "db", "query", "--linked", "--file", str(datei)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=180,
        )
    except FileNotFoundError:
        print("  (Das Supabase-CLI wurde nicht gefunden - der Test braucht es.)")
        return []
    finally:
        datei.unlink(missing_ok=True)

    text = (ergebnis.stdout or "") + (ergebnis.stderr or "")
    start = text.find("\n{")
    if start < 0:
        start = text.find("{")
    if start < 0:
        print("  (Die Antwort des Servers war nicht lesbar.)")
        print(text[:400])
        return []
    zeile = text[start:]
    try:
        obj = json.loads(zeile[: zeile.rfind("}") + 1])
    except json.JSONDecodeError:
        print("  (Die Antwort des Servers war kein JSON.)")
        print(text[:400])
        return []
    return obj.get("rows", [])


def main() -> int:
    print("=" * 70)
    print("DATING HOUR: die Geschlechtsregel am lebenden Server")
    print("=" * 70)
    print()

    zeilen = ausfuehren(sql_bauen())
    if not zeilen:
        print("FEHLER: Der Server hat nicht geantwortet.")
        return 1

    fehler = 0
    for zeile in zeilen:
        erwartet = bool(zeile["erwartet"])
        ist = bool(zeile["ist"])
        ok = erwartet == ist
        if not ok:
            fehler += 1
        print(
            "  %s %-52s erwartet: %-5s ist: %s"
            % (
                "OK  " if ok else "FEHLT",
                zeile["beschreibung"],
                "passt" if erwartet else "nicht",
                "passt" if ist else "nicht",
            )
        )

    print()
    if fehler:
        print("FEHLER: %d Fall(e) passen nicht zur Regel." % fehler)
        return 1
    print(
        "OK: alle %d Faelle verhalten sich wie die Regel vorsieht - das "
        "hetero Event besteht aus Maennern UND Frauen." % len(zeilen)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
