#!/usr/bin/env python3
"""Prueft: Keine STABLE-Funktion darf in die Datenbank schreiben.

BEFUND (20.11.2026, Betreiber): "Die Funken beim Interessen-Screen
koennen nicht geladen werden."

DIE URSACHE (live gemessen): Der Aufruf von
public.list_my_matches_with_state() ueber die Data-API antwortete mit

    HTTP 405  {"code":"25006","message":"cannot execute INSERT in a
    read-only transaction"}

Die Kette:

  * Die Funktion war STABLE. PostgREST fuehrt STABLE-Aufrufe in einer
    READ-ONLY-Transaktion aus.
  * Die Funktion berechnet die Entfernung ueber
    public.profile_distance_km(...).
  * profile_distance_km() ruft public.consume_rate_limit() auf (der
    Trilaterationsschutz) - und DIE schreibt in public.rate_limit_hits.
  * Ein INSERT in einer READ-ONLY-Transaktion ist verboten.

WARUM EIN WERKZEUG STATT EINES EINZELFIXES: Der Fehler ist still. Die
App zeigte "Laden fehlgeschlagen", der Server loggte nichts, alle
Migrationen waren gruen. Und er kann wieder passieren: wer eine neue
STABLE-Funktion baut, die den Rate-Limit benutzt, baut denselben
Fehler erneut - in einer Liste, die man nicht im Blick hat.

DAS WERKZEUG hat zwei Teile:

  1) STATISCH (ohne Datenbank, laeuft in der CI): Es liest die
     Migrationsdateien und meldet jede STABLE-Funktion, die einen der
     Schreiber benutzt. Damit sieht man den Fehler BEVOR er live geht.

  2) LIVE (nur mit Zugang zur Produktivdatenbank): Es fragt die
     Produktivdatenbank ab - dort kann eine Funktion auch von Hand
     veraendert worden sein.

Aufruf::

    python tool/checks/check_stable_functions.py            # nur statisch
    python tool/checks/check_stable_functions.py --live     # zusaetzlich live
"""

import json
import pathlib
import re
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
        if (kandidat / "pubspec.yaml").exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "supabase" / "migrations").is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()
MIG = ROOT / "supabase" / "migrations"

#: Die Muster, die einen SCHREIBER erkennen.
#:
#: WARUM GENAU DIESE: public.consume_rate_limit() ist der Rate-Limit-
#: Zaehler (er schreibt in public.rate_limit_hits) - er wird ueber
#: profile_distance_km() benutzt. Beide sind im Quelltext erkennbar.
#: Die drei SQL-Befehle decken den Rest ab (direkte Schreiber).
SCHREIBER = (
    re.compile(r"consume_rate_limit", re.I),
    re.compile(r"profile_distance_km", re.I),
    re.compile(r"\binsert\s+into\b", re.I),
    re.compile(r"\bupdate\s+[a-z_.\"]", re.I),
    re.compile(r"\bdelete\s+from\b", re.I),
)


def ohne_kommentare(text: str) -> str:
    """Entfernt Zeilenkommentare und Blockkommentare."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"--[^\n]*", " ", text)
    return text


def schreibt(text: str) -> bool:
    """Schreibt der Text in die Datenbank?"""
    sauber = ohne_kommentare(text)
    return any(muster.search(sauber) for muster in SCHREIBER)


def normalisiere_argumente(argumente: str) -> str:
    """Nur die Typen - die Parameternamen sind fuer den Schluessel egal.

    WARUM: "ALTER FUNCTION profile_distance_km(uuid)" und
    "CREATE FUNCTION profile_distance_km(p_other uuid)" sind DIESELBE
    Funktion - der Schluessel muss beides zusammenbringen.
    """
    argumente = ohne_kommentare(argumente).strip()
    if not argumente:
        return ""
    teile = []
    tiefe = 0
    aktuell = ""
    for zeichen in argumente:
        if zeichen == "(":
            tiefe += 1
        elif zeichen == ")":
            tiefe -= 1
        if zeichen == "," and tiefe == 0:
            teile.append(aktuell)
            aktuell = ""
            continue
        aktuell += zeichen
    teile.append(aktuell)
    typen = []
    for teil in teile:
        teil = teil.strip()
        if not teil:
            continue
        # "IN p_x integer" -> "integer"
        wort = teil.split()[-1]
        typen.append(wort.lower())
    return ",".join(typen)


def migrationen(ordner: pathlib.Path | None = None) -> list[pathlib.Path]:
    basis = ordner or MIG
    return sorted(
        basis.glob("*.sql"),
        key=lambda p: int(re.match(r"(\d+)", p.name).group(1)),
    )


def funktionen_aus_datei(sql: str) -> list[dict]:
    """Alle Funktionsdefinitionen einer Datei.

    Jede Definition wird als dict geliefert: name, argumente, kopf
    (der Teil vor dem Rumpf) und rumpf.
    """
    ergebnis = []
    muster = re.compile(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"
        r"(?:public\.)?\"?([a-zA-Z0-9_]+)\"?\s*\(",
        re.I,
    )
    for treffer in muster.finditer(sql):
        # Die Klammern der Argumentliste ausgleichen.
        tiefe, pos = 1, treffer.end()
        while pos < len(sql) and tiefe:
            if sql[pos] == "(":
                tiefe += 1
            elif sql[pos] == ")":
                tiefe -= 1
            pos += 1
        argumente = sql[treffer.end():pos - 1].strip()
        # Der Rumpf: entweder $$...$$ oder '...' oder BEGIN ... END.
        rest = sql[pos:]
        rumpf = ""
        kopf = rest
        dollar = re.search(r"\$(\w*)\$", rest)
        if dollar:
            kopf = rest[:dollar.start()]
            schluss = rest.find(dollar.group(0), dollar.end())
            if schluss > 0:
                rumpf = rest[dollar.end():schluss]
        else:
            # BEGIN ... END (ohne Dollar-Quoting).
            begin = re.search(r"\bBEGIN\b", rest, re.I)
            if begin:
                kopf = rest[:begin.start()]
                rumpf = rest[begin.start():]
        ergebnis.append({
            "name": treffer.group(1).lower(),
            "argumente": argumente,
            "kopf": kopf,
            "rumpf": rumpf,
        })
    return ergebnis


def alters_aus_datei(sql: str) -> list[dict]:
    """Alle ALTER FUNCTION ... VOLATILE/STABLE/IMMUTABLE einer Datei."""
    ergebnis = []
    muster = re.compile(
        r"ALTER\s+FUNCTION\s+(?:public\.)?\"?([a-zA-Z0-9_]+)\"?\s*\(",
        re.I,
    )
    for treffer in muster.finditer(sql):
        tiefe, pos = 1, treffer.end()
        while pos < len(sql) and tiefe:
            if sql[pos] == "(":
                tiefe += 1
            elif sql[pos] == ")":
                tiefe -= 1
            pos += 1
        argumente = sql[treffer.end():pos - 1].strip()
        rest = sql[pos:pos + 120]
        wechsel = re.search(r"\b(VOLATILE|STABLE|IMMUTABLE)\b", rest, re.I)
        if not wechsel:
            continue
        ergebnis.append({
            "name": treffer.group(1).lower(),
            "argumente": argumente,
            "volatilitaet": wechsel.group(1).lower(),
        })
    return ergebnis


def statisch_pruefen(ordner: pathlib.Path | None = None) -> list[str]:
    """Prueft die Migrationsdateien (ohne Datenbank).

    DER ENDLUSTAND ZAEHLT: Die Migrationen werden in Reihenfolge
    gelesen. Eine CREATE OR REPLACE setzt die Funktion (und ihre
    Volatilitaet), ein ALTER FUNCTION ... VOLATILE aendert sie. Genau so
    entsteht auch der Zustand in der Datenbank - Migration 221 hat die
    drei Funktionen auf VOLATILE gesetzt.
    """
    befunde = []
    stand = {}
    for datei in migrationen(ordner):
        sql = datei.read_text(encoding="utf-8", errors="replace")
        for funktion in funktionen_aus_datei(sql):
            key = "%s(%s)" % (
                funktion["name"],
                normalisiere_argumente(funktion["argumente"]),
            )
            kopf = ohne_kommentare(funktion["kopf"]).upper()
            volatilitaet = "volatile"
            if "IMMUTABLE" in kopf:
                volatilitaet = "immutable"
            elif "STABLE" in kopf:
                volatilitaet = "stable"
            stand[key] = {
                "volatilitaet": volatilitaet,
                "rumpf": funktion["rumpf"],
                "datei": datei.name,
            }
        for alter in alters_aus_datei(sql):
            key = "%s(%s)" % (
                alter["name"],
                normalisiere_argumente(alter["argumente"]),
            )
            eintrag = stand.get(key)
            if eintrag is None:
                # ALTER auf eine Funktion, die es im Repository nicht gibt:
                # das kann eine alte Migration sein, die hier fehlt.
                continue
            eintrag["volatilitaet"] = alter["volatilitaet"]
            eintrag["datei"] = datei.name

    for key, eintrag in sorted(stand.items()):
        if eintrag["volatilitaet"] != "stable":
            continue
        if schreibt(eintrag["rumpf"]):
            befunde.append(
                "%s (zuletzt in %s): STABLE, schreibt aber in die "
                "Datenbank" % (key, eintrag["datei"])
            )
    return befunde


def live_pruefen() -> list[str]:
    """Prueft die Produktivdatenbank (nur mit Zugang)."""
    sql_text = """
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig,
       p.provolatile
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.provolatile = 's'
   and (p.prosrc ilike '%consume_rate_limit%'
        or p.prosrc ilike '%profile_distance_km%'
        or p.prosrc ilike '%insert into%'
        or p.prosrc ilike '%delete from%')
 order by 1;
"""
    pfad = ROOT / "supabase" / "_pruef_stable.sql"
    pfad.write_text(sql_text, encoding="utf-8")
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
        raise SystemExit(
            "Die Produktivdatenbank ist nicht erreichbar: %s" % kombi[:300]
        )
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception as e:  # noqa: BLE001
        raise SystemExit("Antwort nicht lesbar: %s" % e)
    if obj.get("_tag") == "Error":
        raise SystemExit("Abfrage fehlgeschlagen: %s" % json.dumps(obj)[:300])
    return ["%s (live)" % r["sig"] for r in obj.get("rows", [])]


def main() -> int:
    print("=" * 70)
    print("STABLE-FUNKTIONEN: schreiben sie in die Datenbank?")
    print("=" * 70)

    befunde = statisch_pruefen()
    print()
    print("  Statisch (Migrationen im Repository): %d Befund(e)"
          % len(befunde))
    for befund in befunde:
        print("    FEHLER: %s" % befund)

    if "--live" in sys.argv:
        try:
            live = live_pruefen()
        except SystemExit as e:
            print()
            print("  ! %s" % e)
            return 1
        print()
        print("  Live (Produktivdatenbank): %d Befund(e)" % len(live))
        for befund in live:
            print("    FEHLER: %s" % befund)
        befunde += live

    print()
    if befunde:
        print(
            "  Eine STABLE-Funktion darf die Datenbank nicht veraendern.\n"
            "  PostgREST fuehrt STABLE-Aufrufe in einer READ-ONLY-\n"
            "  Transaktion aus - der Aufruf bricht dann mit HTTP 405 ab\n"
            "  ('cannot execute INSERT in a read-only transaction').\n"
            "  Loesung: ALTER FUNCTION ... VOLATILE (siehe Migration 221)."
        )
        return 1

    print(
        "  OK: keine STABLE-Funktion schreibt in die Datenbank.\n"
        "       (Die Liste der Funken, der Abstand und der\n"
        "        Profil-Stapel-Abruf antworten wieder.)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
