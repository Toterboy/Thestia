"""Erzeugt die Favicons fuer die Website (tool/make_favicon.py).

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
(die einzige Logo-Quelle im Projekt), und alle RUND:

  favicon.png   192x192  - das ThestiaIcon, rund
  favicon.ico   16/32/48/64/128/256 - dasselbe, rund. Das ist der Weg,
                den die Suche nimmt (sie fragt /favicon.ico).
  favicon.svg   dasselbe als SVG (mit dem PNG eingebettet) - fuer
                Browser, die SVG-Icons bevorzugen. Ohne diese Datei
                nimmte der Browser das Herz.

Der runde Schnitt steht in `tool/logo_round.py` - dieselbe Rechnung wie
in `tool/generate_round_logo.dart`, in Python (weil die Favicons mit
Pillow erzeugt werden).

Aufruf:
    python tool/make_favicon.py
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

WURZEL = pathlib.Path(__file__).resolve().parent.parent
PUBLISH = WURZEL / "passkey-assets"

sys.path.insert(0, str(WURZEL / "tool"))
from logo_round import rundes_logo  # noqa: E402

# ---------------------------------------------------------------------
# 1) Das runde Icon in den benoetigten Groessen
# ---------------------------------------------------------------------
# 256 als Quelle fuer die ICO: das groesste Format darin soll nicht
# hochskaliert werden.
gross = rundes_logo(256)
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
# 2) Das SVG: das runde Icon als eingebettetes PNG
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
    '  <!-- Das ThestiaIcon, rund (eingebettetes PNG - das Artwork ist '
    'eine Rastergrafik). Erzeugt von tool/make_favicon.py. -->\n'
    '  <image href="data:image/png;base64,%s" x="0" y="0" '
    'width="192" height="192"/>\n'
    '</svg>\n'
) % daten
svg_pfad = PUBLISH / "favicon.svg"
svg_pfad.write_text(svg, encoding="utf-8", newline="\n")
print("  favicon.svg          %d Bytes (rundes ThestiaIcon)"
      % svg_pfad.stat().st_size)
