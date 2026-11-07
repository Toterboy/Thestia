#!/usr/bin/env python3
"""Prueft, dass die App und der Server dieselben Merkmale kennen.

WARUM (07.11.2026, Betreiber): "Zudem soll bei Haarfarben auch noch
sowas wie lila usw. sein."

Diese Frage hat eine versteckte Falle: Die erlaubten Merkmale stehen
zweimal - im Server (public.transit_tag_catalog) und in der App
(lib/models/transit_models.dart). Die RPC match_proximity_spark baut
ihre Whitelist aus der Server-Tabelle; ein Wert, den der Server nicht
kennt, wird beim Senden STILLSCHWEIGEND weggefiltert.

Das heisst: Bietet die App eine Farbe an, die der Server nicht kennt,
faellt das dem Nutzer nicht auf - er waehlt sie, sie wird gesendet und
verschwindet. Der Funke kommt nie. Das ist kein Fehler, den man beim
Testen sieht, sondern einer, den man nur an der Quelle findet.

Dieses Werkzeug vergleicht deshalb beide Seiten:

  1. Die Farb-Paletten (Haar, Augen, Kleidung).
  2. Die Merkmals-Slugs des Katalogs gegen die der App.

Aufruf (braucht eine verbundene Datenbank)::

    python tool/check_transit_catalog.py

Ohne Datenbank sagt das Skript, was es nicht pruefen konnte - es
behauptet nicht, es sei gruen.
"""

import json
import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL = ROOT / "lib" / "models" / "transit_models.dart"

SQL = """
SELECT slug, allowed_colors::text AS farben
  FROM public.transit_tag_catalog
 ORDER BY slug;
"""


def lies_db():
    """Liest den Katalog aus der Produktivdatenbank."""
    sql = ROOT / "supabase" / "_pruef_katalog.sql"
    sql.write_text(SQL, encoding="utf-8")
    try:
        ausgabe = subprocess.run(
            ["supabase.cmd", "db", "query", "--linked", "--file", str(sql)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except FileNotFoundError:
        return None, "supabase.cmd nicht gefunden"
    finally:
        sql.unlink(missing_ok=True)

    kombi = ausgabe.stdout + ausgabe.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        return None, "keine Antwort der Datenbank"
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception as e:                                   # noqa: BLE001
        return None, "Antwort nicht lesbar: %s" % e
    if obj.get("_tag") == "Error":
        return None, json.dumps(obj)[:200]

    katalog = {}
    for r in obj.get("rows", []):
        roh = (r.get("farben") or "").strip("{}")
        farben = [f.strip('"') for f in roh.split(",") if f.strip()]
        katalog[r["slug"]] = farben
    return katalog, None


def lies_app():
    """Liest die Paletten und die Merkmals-Slugs aus der App.

    Die Quelle der Wahrheit ist der Katalog-Block in
    lib/models/transit_models.dart: jeder TransitTag-Eintrag nennt
    seinen Slug und (wenn er Farben kennt) seine Palette.

    Wichtig: Die Slugs werden NICHT geraten. Ein geratener Slug
    ("eye_color" statt "eyes_color") wuerde einen Fehler melden, den
    es nicht gibt - und einen echten Fehler verdecken.
    """
    text = MODEL.read_text(encoding="utf-8")

    def liste(name):
        m = re.search(
            r"static const List<String> %s = \[(.*?)\];" % name,
            text,
            re.S,
        )
        if not m:
            return None
        return re.findall(r"'([^']+)'", m.group(1))

    paletten = {
        "hairColors": liste("hairColors"),
        "eyeColors": liste("eyeColors"),
        "clothingColors": liste("clothingColors"),
    }

    # Der Katalog-Block: TransitTag( 'slug', ... allowedColors: TransitTag.X )
    merkmale = {}
    bloecke = re.split(r"TransitTag\(\s*\n", text)
    for block in bloecke[1:]:
        # Nur der Katalog-Block (er steht nach "static const List<TransitTag> catalog")
        if "allowedColors" not in block and "colorizable" not in block:
            continue
        m = re.match(r"'([a-z0-9_]+)'", block.strip())
        if not m:
            continue
        slug = m.group(1)
        # "allowedColors: eyeColors" - der Name der Liste, optional mit
        # TransitTag.-Praefix.
        c = re.search(r"allowedColors:\s*(?:TransitTag\.)?(\w+)", block)
        werte = paletten.get(c.group(1)) if c else None
        merkmale[slug] = werte

    return paletten, merkmale


def main() -> int:
    print("=" * 70)
    print("MERKMALE: App und Server muessen dasselbe kennen")
    print("=" * 70)

    app_paletten, app_merkmale = lies_app()
    katalog, fehler = lies_db()

    print()
    print("  Die App (lib/models/transit_models.dart):")
    for name, werte in app_paletten.items():
        print("    %-14s %d Werte" % (name, len(werte or [])))
    print("    %d Merkmale mit eigener Palette"
          % len([s for s, w in app_merkmale.items() if w]))

    if katalog is None:
        print()
        print("  ! Die Datenbank war nicht erreichbar: %s" % fehler)
        print("    Die Paletten konnten NICHT geprueft werden.")
        print("    Das ist kein bestandener Check - es wird nichts behauptet.")
        return 1

    print()
    print("  Der Server (public.transit_tag_catalog): %d Eintraege"
          % len(katalog))

    fehler_Liste = []

    # 1) Die Paletten vergleichen - je Merkmal, das eine eigene Palette
    #    hat (Haar, Augen).
    print()
    print("  Die Paletten:")
    for slug, app_werte in sorted(app_merkmale.items()):
        if not app_werte:
            continue
        server_werte = set(katalog.get(slug) or [])
        if not server_werte:
            fehler_Liste.append(
                "der Server kennt den Merkmal %s nicht (Slug: %s)"
                % (slug, slug))
            print("    X %-12s der Server kennt den Slug nicht" % slug)
            continue
        nur_app = sorted(set(app_werte) - server_werte)
        nur_server = sorted(server_werte - set(app_werte))
        if nur_app:
            fehler_Liste.append(
                "die App bietet an, was der Server nicht kennt (%s): %s"
                % (slug, ", ".join(nur_app)))
            print("    X %-12s in der App, nicht auf dem Server: %s"
                  % (slug, ", ".join(nur_app)))
        if nur_server:
            fehler_Liste.append(
                "der Server kennt, was die App nicht anbietet (%s): %s"
                % (slug, ", ".join(nur_server)))
            print("    X %-12s auf dem Server, nicht in der App: %s"
                  % (slug, ", ".join(nur_server)))
        if not nur_app and not nur_server:
            print("    OK %-12s %d Farben, App und Server sind gleich"
                  % (slug, len(app_werte)))

    # 2) Die Merkmals-Slugs vergleichen.
    print()
    print("  Die Merkmals-Slugs:")
    server_slugs = set(katalog.keys())
    nur_app = sorted(set(app_merkmale.keys()) - server_slugs)
    nur_server = sorted(server_slugs - set(app_merkmale.keys()))
    if nur_app:
        fehler_Liste.append(
            "die App bietet Merkmale an, die der Server nicht kennt: %s"
            % ", ".join(nur_app))
        print("    X in der App, nicht auf dem Server: %s"
              % ", ".join(nur_app))
    if nur_server:
        # Der Server kennt mehr als die App - das ist kein Fehler (die
        # App muss nicht alles anbieten), aber es wird gemeldet.
        print("    ! auf dem Server, nicht in der App: %s"
              % ", ".join(nur_server))
    if not nur_app:
        print("    OK alle Merkmale der App kennt der Server")

    print()
    if fehler_Liste:
        print("FEHLER: %d Abweichung(en):" % len(fehler_Liste))
        for f in fehler_Liste:
            print("  - %s" % f)
        print()
        print("  Ein Merkmal, das der Server nicht kennt, wird beim")
        print("  Senden stillschweigend weggefiltert - der Nutzer waehlt")
        print("  es, es verschwindet, und der Funke kommt nie.")
        return 1

    print("OK: App und Server kennen dieselben Merkmale und Farben.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
