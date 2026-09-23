"""Statische SQL-Validierung fuer die neuen Migrationen (098/099).

sqlglot unterstuetzt kein Dollar-Quoting und keine Postgres-"adjacent
string literal"-Verkettung - beides wird hier vor dem Parse abstrahiert.
Geprueft wird: Dollar-Quote-Balance, Klammer-Balance und Parsebarkeit
aller Statements AUSSERHALB der Funktionskoerper.
"""
import re
import sys

import sqlglot

FILES = [
    r"supabase\migrations\098_relay_store_relationship_check.sql",
    r"supabase\migrations\099_random_chat_match_window.sql",
    r"supabase\migrations\106_relay_dating_hour_and_limits.sql",
    r"supabase\migrations\107_avatar_keys_out_of_public_view.sql",
    r"supabase\migrations\108_hardening_followups.sql",
]


def check(path: str) -> bool:
    sql = open(path, encoding="utf-8").read()

    # 1) Dollar-Quoting: $$-Marker zaehlen (muss gerade sein; 1 Funktion
    #    = 2 Marker = 1 Block) und fuer den Parse durch Platzhalter
    #    ersetzen.
    marker_count = sql.count("$$")
    if marker_count % 2 != 0:
        print(f"{path}: FEHLER - Dollar-Quotes unausbalanciert ({marker_count})")
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

    # 3) Klammer-Balance ausserhalb von Strings UND Kommentaren pruefen.
    no_strings = re.sub(r"'(?:[^']|'')*'", "''", merged)
    no_strings = re.sub(r"--[^\n]*", "", no_strings)
    if no_strings.count("(") != no_strings.count(")"):
        print(f"{path}: FEHLER - Klammern unausbalanciert "
              f"({no_strings.count('(')} offen / {no_strings.count(')')} zu)")
        return False

    # 4) Parse (postgres-Dialekt).
    try:
        stmts = [s for s in sqlglot.parse(merged, read="postgres") if s]
        kinds = [type(s).__name__ for s in stmts]
        print(f"{path}: OK - {len(stmts)} Statements geparst: {kinds}")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"{path}: PARSE-FEHLER: {e}")
        return False


ok = all(check(f) for f in FILES)
sys.exit(0 if ok else 1)
