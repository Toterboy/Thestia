"""Erzeugt die Favicons fuer die Website (tool/make_favicon.py).

WARUM (06.11.2026, Betreiber): In der Google-Suche erscheint neben
"Thestia" ein allgemeiner Globus-Knopf statt des Logos - die Seite hat
kein Favicon. Das ist das, was die Suche als "Bild" anzeigt.

DIE DATEIEN:
  favicon.png   192x192 - das App-Icon (das Play-Icon, verkleinert)
  favicon.ico   16/32/48 - der Standard-Pfad, den Browser ohne Link
                von sich aus anfragen (damit es keinen 404 gibt)
  favicon.svg   die Marke als Vektorn - fuer moderne Browser und die
                helle/dunkle Darstellung

Alle drei liegen im Publish-Ordner (passkey-assets/) und werden auf
https://thestia.de/favicon.* ausgeliefert.
"""
import pathlib
import re
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - nur ein Werkzeug-Hinweis
    print(
        'FEHLER: Pillow fehlt. Die Favicons werden daraus erzeugt:\n'
        '    python -m pip install Pillow',
    )
    sys.exit(1)

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

WURZEL = pathlib.Path(__file__).resolve().parent.parent
PUBLISH = WURZEL / "passkey-assets"
QUELLE = WURZEL / "fastlane" / "metadata" / "android" / "de-DE" / "images" / "icon.png"

# ---------------------------------------------------------------------
# 1) Das PNG (192x192) und das ICO aus dem App-Icon
# ---------------------------------------------------------------------
quelle = Image.open(QUELLE).convert("RGBA")
print("  Quelle: %dx%d" % quelle.size)

png = quelle.resize((192, 192), Image.LANCZOS)
png_pfad = PUBLISH / "favicon.png"
png.save(png_pfad, "PNG", optimize=True)
print("  favicon.png   192x192  %d Bytes" % png_pfad.stat().st_size)

ico_pfad = PUBLISH / "favicon.ico"
quelle.save(
    ico_pfad,
    "ICO",
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("  favicon.ico   16-256  %d Bytes" % ico_pfad.stat().st_size)

# ---------------------------------------------------------------------
# 2) Das SVG: die Marke aus dem Theme (muss zum Theme passen!)
# ---------------------------------------------------------------------
theme = (WURZEL / "tool" / "web_theme.py").read_text(encoding="utf-8")
m = re.search(r"_SVG_MARKE = \(\n(.*?)\n\)\n", theme, re.S)
if not m:
    raise SystemExit("Die Marke wurde im Theme nicht gefunden")
zeilen = []
for zeile in m.group(1).split("\n"):
    zeile = zeile.strip()
    if zeile.startswith("'") and zeile.endswith("'"):
        zeilen.append(zeile[1:-1].replace("\\'", "'"))
svg = "\n".join(zeilen)
# Als eigenstaendige Datei braucht das SVG einen Hintergrund, sonst
# ist die Marke auf weissem Grund schwer zu erkennen (und im Tab
# verschwindet sie).
svg = svg.replace(
    '<svg viewBox="0 0 24 24" aria-hidden="true">',
    '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" '
    'viewBox="0 0 24 24" role="img" aria-label="Thestia">',
    1,
)
svg_pfad = PUBLISH / "favicon.svg"
svg_pfad.write_text(svg + "\n", encoding="utf-8", newline="\n")
print("  favicon.svg          %d Bytes" % svg_pfad.stat().st_size)
