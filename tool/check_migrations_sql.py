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

# Bewusst eine feste Liste und kein Glob: der Check soll die fuenf
# nach dem Relay-Umbau hinzugekommen Migrationen pruefen, nicht
# stillschweigend alle 128 mitwachsen.
FILES = [
    "supabase/migrations/098_relay_store_relationship_check.sql",
    "supabase/migrations/099_random_chat_match_window.sql",
    "supabase/migrations/106_relay_dating_hour_and_limits.sql",
    "supabase/migrations/107_avatar_keys_out_of_public_view.sql",
    "supabase/migrations/108_hardening_followups.sql",
]


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
    merged = stripped
    prev = None
    while prev != merged:
        prev = merged
        merged = re.sub(
            r"('(?:[^']|'')*')(\s*\n\s*|\s*\|\|\s*)('(?:[^']|'')*')",
            r"\1&&\3",
            merged,
        )
    merged = merged.replace("&&", "")

    # 2b) sqlglot-ParserlÃ¼cke: "LANGUAGE sql SECURITY DEFINER" ohne
    #     dazwischenliegendes SET search_path wirft in sqlglot 30.x
    #     ParseError ("Required keyword: 'this' missing for
    #     LanguageProperty"). Das ist ein Parser-Mangel, kein SQL-Fehler -
    #     die Konstruktion ist regulaeres Postgres und in Migration 108
    #     live deployt. Nachgewiesen: dieselbe Anweisung parst, sobald
    #     SET search_path zwischen LANGUAGE und SECURITY steht.
    #     Eingefuegt wird NUR fuer den Parse, nie fuer die Ausfuehrung.
    merged = re.sub(
        r"(LANGUAGE\s+sql)\s+(SECURITY\s+DEFINER)",
        r"\1 SET search_path = pg_temp \2",
        merged,
        flags=re.I,
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
