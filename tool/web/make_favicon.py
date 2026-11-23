"""Erzeugt die Bilder der Website (Favicons und Logo).

WARUM (06.11.2026, Betreiber): In der Google-Suche erschien neben
"Thestia" ein allgemeiner Globus-Knopf statt des Logos - die Seite hat
kein Favicon. Das ist, was die Suche als "Bild" anzeigt.

BEFUND (09.11.2026, Betreiber): "das Logo ist nur ein Herz und nicht das
ThestiaIcon Logo. Das Runde sollte dabei auch die Farben von dem
Abgerundeten haben (Hier muss das Bild Rund sein)."

DAS WAR ZWEI FEHLER IN EINER:

  1) `favicon.svg` war die MARKE (nur ein Herz). Und weil das SVG im
     HTML als Icon deklariert war, zeigte der Browser-Tab genau das:
     ein Herz. Der Browser nimmt das LETZTE passende Icon - das SVG
     gewinnt also gegen die PNG.

  2) Das Legacy-Launcher-Icon (rund) war blass. Zwei Ursachen: Der
     Hintergrund-Kreis wurde in eine kleinere Maske gelegt (sichtbar
     blieb nur die Mitte des Verlaufs), und das Herz war halbtransparent
     (die Alpha-Schwelle in `generate_launcher_icon.py`).

DIE DATEIEN - alle aus EINER Quelle, `assets/images/thestia_icon_base.png`
(die einzige Logo-Quelle im Projekt). Seit dem 23.11.2026 sind sie
ALLE ABGERUNDET (nicht rund):

  favicon.png   192x192  - das ThestiaIcon, abgerundet
  favicon.ico   16/32/48/64/128/256 - dasselbe, abgerundet. Das ist der
                Weg, den die Suche nimmt (sie fragt /favicon.ico).
  favicon.svg   dasselbe als SVG (mit dem PNG eingebettet) - fuer
                Browser, die SVG-Icons bevorzugen. Ohne diese Datei
                nimmte der Browser das Herz.
  logo.png      256x256  - dasselbe Bild fuer die Kopfzeile und die
                Karte jeder Seite (23.11.2026, Betreiber: "Bei allen
                Websites und auch auth.thestia soll statt diesem Herz
                Icon das richtige App logo da sein, also dieses
                abgerundete, aber nicht ganz runde").

DIE ENTSCHEIDUNG VOM 09.11.2026 ("Hier muss das Bild Rund sein") ist
damit ueberholt (23.11.2026, Betreiber): "Das Icon sollte außerdem
nicht rund sein. Es soll so sein wie thestia_icon_base.png aus
assets/images." Die Quelle hat bereits abgerundete, transparente Ecken
- es wird nur skaliert, nicht mehr in einen Kreis geschnitten.

WARUM EIN WERKZEUG FUER BEIDES: Der Weg zum Logo laeuft sonst
auseinander - das war schon einmal der Grund fuer den Bug vom
09.11.2026. Wer das Logo aendert, aendert es hier an EINER Stelle.

Aufruf:
    python tool/web/make_favicon.py
"""
from __future__ import annotations

import base64
import io
import pathlib
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


WURZEL = _projektwurzel()

PUBLISH = WURZEL / "passkey-assets"

#: Die Logo-Quelle (die einzige im Projekt).
QUELLE = WURZEL / "assets" / "images" / "thestia_icon_base.png"

#: ABGERUNDET, NICHT RUND (23.11.2026, Betreiber): "Das Icon sollte
#: außerdem nicht rund sein. Es soll so sein wie thestia_icon_base.png
#: aus assets/images." Die runde Fassung (tool/images/logo_round.py)
#: war die Entscheidung vom 09.11.2026 - sie ist damit ueberholt.
#: Die Quelle unten ist bereits das abgerundete Artwork mit
#: transparenten Ecken; es wird nur noch skaliert, nicht maskiert.

# ---------------------------------------------------------------------
# 1) Das abgerundete Icon in den benoetigten Groessen
# ---------------------------------------------------------------------
# 256 als Quelle fuer die ICO: das groesste Format darin soll nicht
# hochskaliert werden. Die abgerundeten Ecken sind in der Quelle
# bereits transparent - es wird nur skaliert, nicht maskiert.
gross = Image.open(QUELLE).convert("RGBA")
if gross.size != (256, 256):
    gross = gross.resize((256, 256), Image.LANCZOS)
gross_pfad = PUBLISH / "favicon.png"
gross.resize((192, 192), Image.LANCZOS).save(gross_pfad, "PNG", optimize=True)
print("  favicon.png   192x192  %d Bytes" % gross_pfad.stat().st_size)

ico_pfad = PUBLISH / "favicon.ico"
gross.save(
    ico_pfad,
    "ICO",
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("  favicon.ico   16-256  %d Bytes" % ico_pfad.stat().st_size)

# ---------------------------------------------------------------------
# 2) Das SVG: das abgerundete Icon als eingebettetes PNG
# ---------------------------------------------------------------------
# WARUM EINGEBETTET UND NICHT ALS VEKTOR: Das Artwork (Verlauf, Herz,
# Kopf-Silhouetten, Funken, Schriftzug) ist eine Rastergrafik. Eine
# "vektorisierte" Marke waere eine andere Marke - und genau das war der
# Fehler, den der Betreiber gemeldet hat ("nur ein Herz"). Das SVG
# enthaelt deshalb DASSELBE Bild wie die PNG, nur in einem Gefaess, das
# Browser als Icon akzeptieren.
puffer = io.BytesIO()
gross.resize((192, 192), Image.LANCZOS).save(puffer, "PNG", optimize=True)
daten = base64.b64encode(puffer.getvalue()).decode("ascii")

svg = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" '
    'viewBox="0 0 192 192" role="img" aria-label="Thestia">\n'
    '  <!-- Das ThestiaIcon, abgerundet (eingebettetes PNG - das '
    'Artwork ist eine Rastergrafik). Erzeugt von tool/web/'
    'make_favicon.py. -->\n'
    '  <image href="data:image/png;base64,%s" x="0" y="0" '
    'width="192" height="192"/>\n'
    '</svg>\n'
) % daten
svg_pfad = PUBLISH / "favicon.svg"
svg_pfad.write_text(svg, encoding="utf-8", newline="\n")
print("  favicon.svg          %d Bytes (abgerundetes ThestiaIcon)"
      % svg_pfad.stat().st_size)

# ---------------------------------------------------------------------
# 3) Das Logo fuer die Seiten (das ABGERUNDETE ThestiaIcon)
# ---------------------------------------------------------------------
# WARUM (23.11.2026, Betreiber): "Bei allen Websites und auch auth.thestia
# soll statt diesem Herz Icon das richtige App logo da sein, also dieses
# abgerundete, aber nicht ganz runde." Auf den Seiten stand bisher eine
# Marke aus einem Herz-SVG - nicht das Logo der App. Die Seite zeigt
# jetzt DASSELBE Bild wie der Launcher.
#
# DIE GROESSE: 256 Pixel - die Karte zeigt es mit 96 Pixeln (auf einem
# Pixel-doppelten Geraet also 192), die Kopfzeile mit 30. Mehr waere
# Dateigroesse ohne Nutzen, weniger waere unscharf.
LOGO_GROESSE = 256

logo = Image.open(QUELLE).convert("RGBA")
if logo.size[0] != LOGO_GROESSE:
    logo = logo.resize((LOGO_GROESSE, LOGO_GROESSE), Image.LANCZOS)
logo_pfad = PUBLISH / "logo.png"
logo.save(logo_pfad, "PNG", optimize=True)
print("  logo.png       %dx%d  %d Bytes (abgerundetes ThestiaIcon)"
      % (LOGO_GROESSE, LOGO_GROESSE, logo_pfad.stat().st_size))
