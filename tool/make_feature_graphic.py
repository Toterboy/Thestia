"""Erzeugt die Play-Feature-Graphic (1024x500) fuer com.thestia.app.

Warum das nicht einfach das App-Icon ist: Play zeigt die Feature Graphic
als querformatiges Banner - im Kopf des Store-Listings, in der Suche,
im Karussell. Das Icon ist quadratisch (1:1), die Graphic hat 2,05:1.
Ein hochskaliertes Icon darin waere entweder von Leerraum umgeben oder
beschnitten. Die Graphic ist also eine eigene Komposition, in der das
Icon nur als Baustein vorkommt.

Plakatwerbung nach Googles eigenen Vorgaben: "design for scale and keep
important elements toward the center". In der Play-Suche wird die
Graphic klein angezeigt - deshalb Logo, Name und ein Claim, kein
Screenshot. Ein Mockup waere dort unlesbar.

Vorgaben von Play (Hilfeseite):
  - exakt 1024 x 500 px
  - JPEG oder 24-Bit-PNG, KEIN Alphakanal
  - sRGB
Alphakanal wird deshalb auf den Verlauf komponiert und das Ergebnis
konsequent nach RGB konvertiert.

Farben aus dem App-Icon gezogen (haeufigste Töne):
  #6000C0  Violett, #7800A8 / #9000A8  Mittelviolett,
  #D80078 / #F01860  Magenta, #F0F0F0 / #F0D8F0  Hell
Daraus ein diagonaler Verlauf, der die Markenrichtung trifft.
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
W, H = 1024, 500
ICON = ROOT / 'assets/images/thestia_icon_base.png'
OUT_DIR = ROOT / 'fastlane/metadata/android'
OUT_NAME = 'featureGraphic.png'

# Markenverlauf: Violett -> Magenta, diagonal von links oben nach rechts
# unten. Die Zwischenfarben stammen aus dem Icon selbst, damit die
# Graphic nicht danebenliegt.
C_FROM = (0x5A, 0x00, 0xB8)   # Violett
C_MID = (0x9A, 0x00, 0x90)   # Mittelviolett
C_TO = (0xE0, 0x10, 0x66)   # Magenta
INK = (0xFF, 0xFF, 0xFF)
INK_SOFT = (0xF0, 0xD8, 0xF0)

BRAND = 'Thestia'
HOOK = 'Person statt Bild.'
PROOF = 'Datenschutzfreundliches Dating  ·  E2E-verschlüsselt  ·  P2P'

FONT_BOLD = pathlib.Path('C:/Windows/Fonts/segoeuib.ttf')
FONT_REG = pathlib.Path('C:/Windows/Fonts/segoeui.ttf')
FONT_SEMI = pathlib.Path('C:/Windows/Fonts/segoeuisb.ttf')
if not FONT_SEMI.exists():
    FONT_SEMI = FONT_REG


def gradient(size: tuple[int, int]) -> Image.Image:
    """Diagonaler Verlauf, in drei Stufen interpoliert.

    In zwei Schritten interpoliert statt in einem: ein reiner
    Zweipunkt-Verlauf von Violett nach Magenta laeuft durch ein
    entsaettetes Kirscha, das in der Icon-Palette gar nicht vorkommt.
    """
    w, h = size
    base = Image.new('RGB', (w, h))
    px = base.load()
    for y in range(h):
        for x in range(w):
            t = (x / (w - 1) * 0.55) + (y / (h - 1) * 0.45)
            if t < 0.5:
                u = t / 0.5
                a, b = C_FROM, C_MID
            else:
                u = (t - 0.5) / 0.5
                a, b = C_MID, C_TO
            px[x, y] = (round(a[0] + (b[0] - a[0]) * u),
                        round(a[1] + (b[1] - a[1]) * u),
                        round(a[2] + (b[2] - a[2]) * u))
    return base


def fit_font(draw: ImageDraw.ImageDraw, text: str, path: pathlib.Path,
             start: int, max_w: int, floor: int = 14) -> ImageFont.FreeTypeFont:
    """Groesste Schriftgroesse, bei der die Zeile in max_w passt.

    Die erste Version der Graphic hat die Proof-Zeile ohne Messung
    gesetzt - sie lief rechts aus dem Bild, "P2P" fehlte vollstaendig.
    Ein Layout ohne Breitenpruefung ist kein Layout, deshalb wird hier
    gemessen und solange verkleinert, bis es passt.
    """
    for size in range(start, floor - 1, -1):
        f = ImageFont.truetype(str(path), size)
        w = draw.textbbox((0, 0), text, font=f)[2]
        if w <= max_w:
            return f
    f = ImageFont.truetype(str(path), floor)
    w = draw.textbbox((0, 0), text, font=f)[2]
    if w > max_w:
        raise SystemExit(
            f'FEHLER: "{text}" passt auch bei {floor}px nicht in {max_w}px '
            f'({w}px). Text kuerzen oder zwei Zeilen daraus machen.')
    return f


# Zuschnitt des Emblems, als Anteile der Icon-Groesse. Zentral
# konfigurierbar, damit sich der Bildausschnitt justieren laesst, ohne
# an der Geometrie zu drehen.
#
#   CROP_SIDE   Kantenlaenge des Quadrats (Anteil der Icon-Breite)
#   CROP_CX     Mittelpunkt x (0.5 = mittig)
#   CROP_CY     Mittelpunkt y - bestimmt, wie viel Marke und wie viel
#               Schriftzug sichtbar werden
#
# Abgelesen aus dem Icon (941x941):
#   Bildmarke mit Figuren und Glitzern  y ca. 0,10 bis 0,58
#   Schriftzug "Thestia"                ab  y ca. 0,64
# Bei CROP_SIDE 0,56 und CROP_CY 0,31 liegt die Unterkante bei 0,59 - also
# mit Luft ueber dem Schriftzug. CROP_CX leicht links der Mitte, damit
# der Glitzer rechts nicht an der Kreiskante abgeschnitten wird.
CROP_SIDE = 0.56
CROP_CX = 0.47
CROP_CY = 0.31


def emblem(size: int) -> Image.Image:
    """Bildmarke ohne Schriftzug, als saubere Kreisscheibe.

    Das App-Icon ist eine abgerundete Kachel und traegt unten den
    Schriftzug "Thestia". In der Graphic waere der Name damit zweimal
    da und die beiden konkurrierten.

    Der naive Anschnitt am unteren Rand (oberhalb des Schriftzugs) hat
    nicht funktioniert: die Kachel fuellt das Quadrat fast vollstaendig,
    deshalb dominierte ihre eigene abgerundete Form die Kreismaske - das
    Ergebnis war wieder eine Kachel, unten zusaetzlich mit einem Rest
    des Schriftzugs. Richtig ist deshalb, ein Quadrat INNERHALB der
    Kachel auszuschneiden: es liegt dann auf dem Icon-Verlauf, die
    Kreismaske schneidet sauber, und die Kachelkante liegt ausserhalb
    und stoert nicht.
    """
    with Image.open(ICON) as im:
        im = im.convert('RGBA')
        w, h = im.size
        side = int(min(w, h) * CROP_SIDE)
        cx = w * CROP_CX
        cy = h * CROP_CY
        box = (max(0, int(cx - side / 2)), max(0, int(cy - side / 2)),
               min(w, int(cx + side / 2)), min(h, int(cy + side / 2)))
        sq = im.crop(box).resize((size, size), Image.LANCZOS)
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    # Alpha MULTIPLIZIEREN, nicht setzen. putalpha() ueberschreibt den
    # Kanal: alle Pixel innerhalb des Kreises wurden deckend, auch die
    # transparenten neben der Icon-Kachel - und deren RGB ist (0,0,0).
    # Ergebnis war ein schwarzer Ring um das Emblem.
    sq.putalpha(ImageChops.multiply(sq.getchannel('A'), mask))
    return sq


def main() -> int:
    print('=' * 70)
    print('PLAY FEATURE GRAPHIC')
    print('=' * 70)
    if not ICON.exists():
        print(f'  FEHLER: {ICON} nicht gefunden.')
        return 1
    if not FONT_BOLD.exists():
        print(f'  FEHLER: {FONT_BOLD} nicht gefunden - Text nicht moeglich.')
        return 1

    canvas = gradient((W, H))
    d = ImageDraw.Draw(canvas)

    MARGIN = 84
    EMB = 250
    ix, iy = MARGIN, (H - EMB) // 2

    shadow = Image.new('RGBA', (EMB, EMB), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([0, 0, EMB - 1, EMB - 1], fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    canvas.paste(shadow, (ix + 3, iy + 11), shadow)
    mark = emblem(EMB)
    canvas.paste(mark, (ix, iy), mark)

    tx = ix + EMB + 56
    max_w = W - tx - MARGIN
    print(f'  Textfeld: x={tx}..{W - MARGIN}  ({max_w} px breit)')

    f_brand = fit_font(d, BRAND, FONT_BOLD, 104, max_w)
    f_hook = fit_font(d, HOOK, FONT_SEMI, 46, max_w)
    f_proof = fit_font(d, PROOF, FONT_REG, 25, max_w)
    print(f'  Schriftgrade (an Textfeld angepasst): Marke {f_brand.size}, '
          f'Claim {f_hook.size}, Nachweis {f_proof.size}')
    for label, txt, f in (('Marke', BRAND, f_brand), ('Claim', HOOK, f_hook),
                          ('Nachweis', PROOF, f_proof)):
        w = d.textbbox((0, 0), txt, font=f)[2]
        print(f'    {label:9s} {w:4d} px  {"passt" if w <= max_w else "PASST NICHT"}')

    # Textblock auf die Mitte des Emblems ausrichten
    heights = []
    for txt, font in ((BRAND, f_brand), (HOOK, f_hook)):
        b = d.textbbox((0, 0), txt, font=font)
        heights.append((b, font, txt))
    gap1, gap2 = 12, 16
    total = sum(b[3] - b[1] for b, _, _ in heights) + gap1 + (f_proof.size + gap2)
    y = iy + (EMB - total) // 2

    for (b, font, txt), color in zip(heights, (INK, INK_SOFT)):
        d.text((tx, y - b[1]), txt, font=font, fill=color)
        y += (b[3] - b[1]) + gap1
    y += gap2 - gap1
    b = d.textbbox((0, 0), PROOF, font=f_proof)
    d.text((tx, y - b[1]), PROOF, font=f_proof, fill=INK_SOFT)

    # Harte Zusicherung: nichts darf ueber den Rand hinausragen
    for label, txt, f in (('Marke', BRAND, f_brand), ('Claim', HOOK, f_hook),
                          ('Nachweis', PROOF, f_proof)):
        b = d.textbbox((0, 0), txt, font=f)
        assert tx + b[2] <= W - MARGIN, f'{label} ragt ueber den rechten Rand'
    assert iy >= 0 and y + f_proof.size <= H, 'Text ragt vertikal heraus'

    # Alpha ausschliessen: Play akzeptiert nur JPEG oder 24-Bit-PNG.
    assert canvas.mode == 'RGB', f'unerwarteter Modus {canvas.mode}'
    out_paths = []
    for lang in ('de-DE', 'en-US'):
        d_dir = OUT_DIR / lang / 'images'
        d_dir.mkdir(parents=True, exist_ok=True)
        p = d_dir / OUT_NAME
        canvas.save(p, format='PNG', optimize=True)
        out_paths.append(p)

    # Gegenprobe
    print(f'  Kanalmodus: {canvas.mode} (24-Bit-PNG ohne Alpha, wie gefordert)')
    print()
    print('  Gegenprobe:')
    ok = True
    for p in out_paths:
        with Image.open(p) as chk:
            good = chk.size == (W, H) and chk.mode == 'RGB'
            ok &= good
            rel = p.relative_to(ROOT)
            print(f'    {rel}: {chk.size[0]}x{chk.size[1]}  '
                  f'Modus {chk.mode}  {p.stat().st_size:,} B  '
                  f'-> {"OK" if good else "FEHLER"}')
    print()
    print(f'  Hinweis: Inhalt ist der DEUTSCHIE Claim. Fuer {OUT_NAME} in')
    print('  en-US wird dasselbe deutsche Motiv ausgeliefert - Play nimmt pro')
    print('  Listing die Datei des jeweiligen Sprachordners. Vor einem')
    print('  englischen Listing also HOOK/PROOF auf Englisch umstellen und')
    print('  en-US-Screenshots nachziehen (aktuell 0).')
    print()
    print('OK: 1024x500, 24-Bit-PNG.' if ok else 'FEHLER: Format Grenze gerissen.')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
