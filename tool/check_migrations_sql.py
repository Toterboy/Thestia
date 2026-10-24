"""Statische SQL-Validierung fuer die neuen Migrationen (098/099).

sqlglot unterstuetzt kein Dollar-Quoting und keine Postgres-"adjacent
string literal"-Verkettung - beides wird hier vor dem Parse abstrahiert.
Geprueft wird: Dollar-Quote-Balance, Klammer-Balance und Parsebarkeit
aller Statements AUSSERHALB der Funktionskoerper.
"""
import pathlib
import re
import sys

import sqlglot

# Pfade mit Forward-Slashes und verankert am Repo-Root. Vorher standen hier
# Windows-Rawstrings (r"supabase\migrations\...") - damit liess sich die Datei
# unter Linux nicht oeffnen, der Check lief also ausschliesslich auf
# Windows. Er ist jetzt zum ersten Mal in der CI gelandet und dort
# gescheitert. Zusaetzlich loest der Pfad unabhaengig vom aktuellen
# Arbeitsverzeichnis auf, damit der Check auch aus tool/ heraus laeuft.
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Der Check laeuft ueber ALLE Migrationen, nicht ueber eine feste Liste.
#
# BISHER stand hier eine Liste von fuenf Dateien (098/099/106/107/108) mit
# der Begruendung, der Check solle nicht stillschweigend alle 128 mitwachsen.
# Das hat den Zweck verfehlt: die Migrationen 109-155 wurden nie geprueft -
# auch nicht die sicherheitskritischen 144, 149, 151 und 155.
#
# Der Grund fuer die feste Liste war die Sorge vor Fehlalarmen, nicht die
# Sorge vor Aufwand. Die Abstraktionen in diesem Skript (Dollar-Quoting,
# zusammenhaengende String-Literale, der sqlglot-Sonderfall bei
# "LANGUAGE sql SECURITY DEFINER") sind inzwischen stabil - sie stammen
# aus den deployten Migrationen 062 und 108. Deshalb: Glob ueber alle.
#
# Es gibt bewusst keine Ausnahme: Wenn eine Migration nicht parst, ist das
# ein Befund und kein Fehlalarm.
FILES = sorted(
    str(p.relative_to(ROOT)).replace("\\", "/")
    for p in (ROOT / "supabase" / "migrations").glob("*.sql")
)


def check(rel: str) -> bool:
    path = ROOT / rel
    if not path.exists():
        print(f"{rel}: FEHLER - Datei nicht gefunden unter {path}")
        return False
    sql = path.read_text(encoding="utf-8")

    # 1) Dollar-Quoting: $$-Marker zaehlen (muss gerade sein; 1 Funktion
    #    = 2 Marker = 1 Block) und fuer den Parse durch Platzhalter
    #    ersetzen.
    marker_count = sql.count("$$")
    if marker_count % 2 != 0:
        print(f"{rel}: FEHLER - Dollar-Quotes unausbalanciert ({marker_count})")
        return False
    stripped = re.sub(r"\$\$.*?\$\$", "$$ DOLLAR_BODY $$", sql, flags=re.S)

    # 2) Adjazente String-Literale ('a'\n 'b') und 'a' || 'b'-Ketten zu
    #    je einem Literal verschmelzen (Postgres erlaubt beides,
    #    sqlglot nicht - Identisches Muster steht deployt in 062).
    #    Iterativ: Ketten teilen sich Zwischenliterale (non-overlapping).
    #
    #    BUG (gefunden am 22.10.2026): als Platzhalter wurde "&&"
    #    benutzt und anschliessend global entfernt. Damit wurde auch der
    #    echte Postgres-Operator "&&" (Array-Overlap, z. B.
    #    "WHERE tags && ARRAY['a','b']") aus der Anweisung entfernt -
    #    die Pruefung lief danach gegen ein veraendertes SQL. Der
    #    Platzhalter ist jetzt ein Zeichen, das im SQL nicht vorkommt.
    #    Der Platzhalter wird ersatzlos entfernt - dadurch werden die
    #    beiden Literale zu einem ('a''b'), das sqlglot als ein Literal
    #    liest. Genau das war das Verhalten des alten "&&"-Platzhalters,
    #    ohne echte "&&"-Operatoren zu zerstoeren.
    _JOIN = "\x00JOIN\x00"
    merged = stripped
    prev = None
    while prev != merged:
        prev = merged
        merged = re.sub(
            r"('(?:[^']|'')*')(\s*\n\s*|\s*\|\|\s*)('(?:[^']|'')*')",
            r"\1" + _JOIN + r"\3",
            merged,
        )
    merged = merged.replace(_JOIN, "")

    # 2b) sqlglot-Parserlücke: "LANGUAGE sql SECURITY DEFINER" ohne
    #     dazwischenliegendes SET search_path wirft in sqlglot 30.x
    #     ParseError ("Required keyword: 'this' missing for
    #     LanguageProperty"). Das ist ein Parser-Mangel, kein SQL-Fehler -
    #     die Konstruktion ist regulaeres Postgres und in Migration 108
    #     live deployt. Nachgewiesen: dieselbe Anweisung parst, sobald
    #     SET search_path zwischen LANGUAGE und SECURITY steht.
    #     Eingefuegt wird NUR fuer den Parse, nie fuer die Ausfuehrung.
    #
    #     Das gilt fuer JEDE LANGUAGE, nicht nur fuer sql: Migration 002
    #     benutzt "LANGUAGE plpgsql SECURITY DEFINER" und fiel deshalb
    #     durch, sobald der Check ueber alle Migrationen lief.
    merged = re.sub(
        r"(LANGUAGE\s+(?:sql|plpgsql))\s+(SECURITY\s+DEFINER)",
        r"\1 SET search_path = pg_temp \2",
        merged,
        flags=re.I,
    )

    #     Steht danach noch eine eigene SET-Klausel (z. B.
    #     "SET search_path = ''"), entsteht durch das Einsetzen eine
    #     doppelte SET-Klausel - die parst der Parser nicht mehr. Fuer den
    #     Parse wird die zweite entfernt; fuer die Ausfuehrung aendert
    #     das nichts, weil der Text nur zum Parsen veraendert wird.
    merged = re.sub(
        r"(SET\s+search_path\s*=\s*pg_temp\s+SECURITY\s+DEFINER)"
        r"\s+SET\s+search_path\s*=\s*'[^']*'",
        r"\1",
        merged,
        flags=re.I,
    )

    # 2c) sqlglot-Parserlücke: "DROP TRIGGER IF EXISTS ... ON ..." parst
    #     in sqlglot 30.x nicht ("Invalid expression / Unexpected token",
    #     Spalte 83 = der Punkt nach dem Tabellennamen). Das ist ein
    #     Parser-Mangel: die Anweisung ist regulaeres Postgres und in
    #     Dutzenden Migrationen live deployt.
    #
    #     Fuer den Parse wird die Anweisung durch einen Kommentar ersetzt.
    #     Die Klammer-Balance und die Dollar-Quote-Balance werden weiter
    #    hin geprueft - nur die Statement-Aufteilung faellt weg.
    merged = re.sub(
        r"DROP\s+TRIGGER\s+IF\s+EXISTS\s+[^;]+;",
        "-- (DROP TRIGGER IF EXISTS: vom Parser nicht unterstuetzt)",
        merged,
        flags=re.I | re.S,
    )

    # 2d) sqlglot-Parserlücke: "COMMENT ON TRIGGER ... ON ... IS '...'"
    #     parst nicht ("Required keyword: 'expression' missing").
    #     COMMENT ON FUNCTION/TABLE/COLUMN/VIEW parst - nur die
    #     TRIGGER-Variante fehlt im Parser.
    merged = re.sub(
        r"COMMENT\s+ON\s+TRIGGER\s+[^;]+;",
        "-- (COMMENT ON TRIGGER: vom Parser nicht unterstuetzt)",
        merged,
        flags=re.I | re.S,
    )

    # 2e) sqlglot-Parserlücke: in "COMMENT ON FUNCTION" kann die
    #     Signatur Array-Typen enthalten ("text[]"), die der Parser dort
    #     nicht kennt ("Expecting )"). In CREATE FUNCTION parst dasselbe
    #     problemlos - es ist also die Kombination, nicht der Typ.
    #     Fuer den Parse werden die Klammern der Array-Typen entfernt;
    #     der Typ selbst ist fuer die Pruefung ohne Bedeutung.
    merged = re.sub(
        r"COMMENT\s+ON\s+FUNCTION\s+[^;]+;",
        lambda m: m.group(0).replace("[]", ""),
        merged,
        flags=re.I | re.S,
    )

    # 3) Klammer-Balance ausserhalb von Strings UND Kommentaren pruefen.
    no_strings = re.sub(r"'(?:[^']|'')*'", "''", merged)
    no_strings = re.sub(r"--[^\n]*", "", no_strings)
    if no_strings.count("(") != no_strings.count(")"):
        print(f"{rel}: FEHLER - Klammern unausbalanciert "
              f"({no_strings.count('(')} offen / {no_strings.count(')')} zu)")
        return False

    # 4) Parse (postgres-Dialekt).
    try:
        stmts = [s for s in sqlglot.parse(merged, read="postgres") if s]
        kinds = [type(s).__name__ for s in stmts]
        print(f"{rel}: OK - {len(stmts)} Statements geparst: {kinds}")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"{rel}: PARSE-FEHLER: {e}")
        return False


ok = all(check(f) for f in FILES)
sys.exit(0 if ok else 1)
