"""Findet und entfernt die BOM (Byte Order Mark) aus den Migrationsdateien.

WARUM: Die Migrationsdateien werden mit zwei verschiedenen Werkzeugen
geschrieben - dem write-Tool (ohne BOM) und PowerShell
`Set-Content -Encoding UTF8` (mit BOM). Der SQL-Sicherheits-Checker
(pglast) parst eine Datei mit BOM nicht:

    syntax error at or near "\ufeff", at index 0

Der Parse-Check (`check_migrations_sql.py) sieht das BOM nicht - er
entfernt es beim Lesen. Deshalb war der Fehler nur im CI sichtbar.

Aufruf::

    python tool/fix_migration_bom.py
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG = ROOT / "supabase" / "migrations"

BOM = b"\xef\xbb\xbf"


def main() -> int:
    geaendert = 0
    geprueft = 0
    for datei in sorted(MIG.glob("*.sql")):
        geprueft += 1
        roh = datei.read_bytes()
        if roh.startswith(BOM):
            datei.write_bytes(roh[len(BOM):])
            print("  BOM entfernt: %s" % datei.name)
            geaendert += 1
    print()
    print("  %d Migrationsdateien geprueft, %d bereinigt." % (geprueft, geaendert))
    return 0


if __name__ == "__main__":
    sys.exit(main())
