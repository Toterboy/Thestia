"""Prueft, ob alle Migrationen aus dem Repository auch angewandt sind.

BEFUND (07.11.2026): Die Tabelle public.chat_image_hashes wurde in
Migration 068 angelegt (mit UNIQUE (sender_id, receiver_id,
photo_hash)), ist auf dem Produktivsystem aber NICHT vorhanden -
obwohl die Funktion register_chat_image_hash existiert und mit
"relation does not exist" scheitern wuerde.

Also: Ein Teil der Migration 068 ist nie gelaufen. Das ist die Art
Fehler, die niemand sieht, weil die Funktion "ja eh nur intern
genutzt wird".

Dieses Skript vergleicht das Repository mit der Historie des
Produktivsystems und nennt jede Migration, die fehlt.
"""
import json
import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG = ROOT / "supabase" / "migrations"

SQL = "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;"


def main() -> int:
    repo = {}
    for datei in sorted(MIG.glob("*.sql")):
        m = re.match(r"(\d+)_", datei.name)
        if m:
            repo[int(m.group(1))] = datei.name

    sql = ROOT / "supabase" / "_pruef_historie.sql"
    sql.write_text(SQL, encoding="utf-8")
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
        print("  (Historie nicht lesbar)")
        print(kombi[:400])
        return 1
    zeile = kombi[start:]
    obj = json.loads(zeile[:zeile.rfind("}") + 1])
    live = {int(r["version"]) for r in obj.get("rows", [])}

    print("  Im Repository: %d Migrationen (bis %d)"
          % (len(repo), max(repo) if repo else 0))
    print("  Auf dem Server: %d Migrationen" % len(live))

    fehlend = sorted(n for n in repo if n not in live)
    extra = sorted(n for n in live if n not in repo)

    print()
    if fehlend:
        print("  X %d Migration(en) aus dem Repository sind NICHT angewandt:"
              % len(fehlend))
        for n in fehlend:
            print("      %d  %s" % (n, repo[n]))
    else:
        print("  OK  jede Migration aus dem Repository ist angewandt.")

    if extra:
        print()
        print("  ! %d Migration(en) auf dem Server gibt es im Repository"
              " nicht: %s"
              % (len(extra), ", ".join(str(n) for n in extra[:12])))

    return 1 if fehlend else 0


if __name__ == "__main__":
    sys.exit(main())
