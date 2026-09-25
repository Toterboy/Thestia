"""
tool/make_store_screenshots.py
==============================
Erzeugt MARKETING-Screenshots fuer den Play Store aus den gerenderten
App-Screens (test/screenshots/store_v091/9x16/*.png).

Statt nackter UI-Dumps: Markenverlauf als Hintergrund, echtes
Phone-Mockup (Rahmen + Schatten) und eine Nutzen-Headline darueber.
Das ist das, was im Store wirklich ankommt - ein Feature-Spiegelbild
ueberzeugt niemanden zum Installieren.

Aufruf:
    python tool/make_store_screenshots.py

Ausgabe:
    releases/testapk/screenshots/marketing/9x16/*.png   (1080x1920)
    releases/testapk/screenshots/marketing/wqhd/*.png   (2560x1440)
    fastlane/metadata/android/de-DE/images/phoneScreenshots/*.png (9x16)

Voraussetzung: die App-Screens vorher rendern -
    $env:STORE_SHOTS="1"; flutter test --update-goldens test/screenshots/store_v091_shots_test.dart
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'test' / 'screenshots' / 'store_v091' / '9x16'
OUT_9x16 = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing' / '9x16'
OUT_WQHD = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing' / 'wqhd'
OUT_FASTLANE = (ROOT / 'fastlane' / 'metadata' / 'android' / 'de-DE'
                / 'images' / 'phoneScreenshots')

# Markenfarben (aus thestia_icon_base.png gezogen)
BRAND = [(0xFF, 0x2E, 0x74), (0xD1, 0x18, 0xB4), (0x6D, 0x1E, 0xC4),
         (0x3B, 0x14, 0x6B)]

FONT_BOLD = r'C:\Windows\Fonts\segoeuib.ttf'
FONT_REG = r'C:\Windows\Fonts\segoeui.ttf'

# Datei -> (Headline, Subline, Badge)
SHOTS = {
    '01_willkommen': (
        'Blind Date mit\nSubstanz',
        'Persönlichkeit vor Aussehen: Hör erst zu,\n'
        'und siehst ein Foto erst nach dem Funke.',
        'Kostenlos. Für immer.',
    ),
    '02_anmelden': (
        'In einer Minute\nstartklar',
        'Keine Abos, keine Werbung, kein Daten-Hammer.\n'
        'Einfach registrieren und loslegen.',
        'Open Source (AGPLv3)',
    ),
    '03_entdecken': (
        'Fünf Wege,\neinen Funken zu zünden',
        'Von Find your Match bis Transit Spark:\n'
        'im Zug nebenan Blickkontakt genügt.',
        'E2E-verschlüsselt',
    ),
    '04_chat_hintergrund': (
        'Deine Chats,\ndein Stil',
        'Muster oder eigenes Bild – und trotzdem\n'
        'endet-zu-ende verschlüsselt.',
        '6 Muster + eigenes Bild',
    ),
    '05_eisbrecher': (
        '60 Fragen gegen\ndas Schweigen',
        'Eisbrecher für den ersten Chat: antippen,\n'
        'senden, plaudern. In 10 Kategorien.',
        'Ohne Stockfoto-Posen',
    ),
}


def gradient(size, angle=35.0):
    """Diagonaler Markenverlauf (Bresenham-artig, ohne numpy)."""
    import math
    w, h = size
    img = Image.new('RGB', (w, h))
    px = img.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    # Projektionsspanne fuer die Farbverlaeufe
    proj = [(x * dx + y * dy) for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
    lo, hi = min(proj), max(proj)
    span = (hi - lo) or 1
    seg = (len(BRAND) - 1)
    for y in range(h):
        base = y * dy
        for x in range(w):
            t = ((x * dx + base) - lo) / span * seg
            i = min(int(t), seg - 1)
            f = t - i
            c0, c1 = BRAND[i], BRAND[i + 1]
            px[x, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3))
    return img


def rounded_mask(size, radius, supersample=4):
    w, h = size
    m = Image.new('L', (w * supersample, h * supersample), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, w * supersample - 1, h * supersample - 1],
        radius=radius * supersample, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def phone_mockup(screen: Image.Image, scale=1.0):
    """Rahmen + Schatten um den Screen-Screenshot."""
    w, h = screen.size
    bezel = int(round(14 * scale))
    radius_out = int(round(64 * scale))
    radius_in = int(round(46 * scale))
    pad = int(round(30 * scale))          # Schattenabstand

    body_w, body_h = w + 2 * bezel, h + 2 * bezel
    canvas = Image.new('RGBA', (body_w + 2 * pad, body_h + 2 * pad), (0, 0, 0, 0))

    # Weicher Schlagschatten unter dem Geraet
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad - int(6 * scale), pad + int(10 * scale),
         pad + body_w + int(6 * scale), pad + body_h + int(18 * scale)],
        radius=radius_out, fill=(20, 0, 40, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18 * scale)))

    # Geraetekorpus (dunkles Graphit mit hellem Rand)
    body = Image.new('RGBA', (body_w, body_h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, body_w - 1, body_h - 1], radius=radius_out,
        fill=(26, 18, 40, 255), outline=(255, 255, 255, 60),
        width=max(2, int(2 * scale)))

    # Screen: Ecken oben leicht gerundet (wie ein Modern-Handy)
    scr_mask = rounded_mask((w, h), radius_in)
    scr = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    scr.paste(screen.convert('RGBA'), (0, 0), scr_mask)
    body.alpha_composite(scr, (bezel, bezel))

    # Notch/Dynamic-Island
    d = ImageDraw.Draw(body)
    iw = int(round(150 * scale))
    ih = int(round(40 * scale))
    d.rounded_rectangle(
        [(body_w - iw) // 2, bezel + int(round(8 * scale)),
         (body_w + iw) // 2, bezel + ih + int(round(8 * scale))],
        radius=ih // 2, fill=(20, 14, 30, 235))

    canvas.alpha_composite(body, (pad, pad))
    return canvas


def draw_lines(draw, xy, text, font, fill, line_gap, anchor_x, y, align='center'):
    """Zeichnet einen mehrzeiligen Textblock; gibt die neue y-Position zurueck."""
    for line in text.split('\n'):
        bbox = draw.textbbox((0, 0), line, font=font)
        w = bbox[2] - bbox[0]
        x = anchor_x - w / 2 if align == 'center' else anchor_x
        draw.text((x, y), line, font=font, fill=fill)
        y += (bbox[3] - bbox[1]) + line_gap
    return y


def badge_pill(bg, text, cx, top, font_path=FONT_BOLD, size=34, pad_x=72,
               pad_y=17):
    """Transparentes Abzeichen-Pill MIT Text (alpha-korrekt geblendet).

    Wichtig: ImageDraw auf einem RGBA-Bild ERSETZT die Pixel inkl. Alpha -
    ein fill=(255,255,255,46) wuerde thus deckend weiss. Deshalb wird die
    Form auf einer eigenen Ebene gezeichnet und per alpha_composite
    darueber gelegt.
    """
    layer = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(font_path, size)
    bb = d.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    w, h = tw + 2 * pad_x, th + 2 * pad_y
    x0, y0 = int(cx - w / 2), int(top)
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=h // 2,
                        fill=(255, 255, 255, 52),
                        outline=(255, 255, 255, 130), width=2)
    d.text((cx - tw / 2 - bb[0], y0 + pad_y - bb[1]), text, font=font,
           fill=(255, 255, 255, 250))
    bg.alpha_composite(layer)


def compose_9x16(shot: Image.Image, headline: str, subline: str, badge: str):
    W, H = 1080, 1920
    bg = gradient((W, H), 40).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    # --- Textblock oben -------------------------------------------------
    f_head = ImageFont.truetype(FONT_BOLD, 74)
    f_sub = ImageFont.truetype(FONT_REG, 36)
    y = 130
    y = draw_lines(draw, None, headline, f_head, (255, 255, 255, 255), 20, W // 2, y)
    y += 30
    y = draw_lines(draw, None, subline, f_sub, (255, 255, 255, 226), 14, W // 2, y)

    # --- Phone-Mockup ---------------------------------------------------
    scale = 0.55
    tw, th = int(1080 * scale), int(1920 * scale)
    scr = shot.resize((tw, th), Image.LANCZOS)
    phone = phone_mockup(scr, scale=scale)
    px = (W - phone.width) // 2
    py = y + 40
    bg.alpha_composite(phone, (px, py))

    # --- Badge unter dem Geraet -------------------------------------------
    by = min(py + phone.height + 26, H - 100)
    badge_pill(bg, badge, W // 2, by)
    return bg.convert('RGB')


def compose_wqhd(shot: Image.Image, headline: str, subline: str, badge: str):
    W, H = 2560, 1440
    bg = gradient((W, H), 25).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    # Phone links: Hoehe so skalieren, dass es mit Rand sicher passt
    # (Mockup = Screen + 2xBezel + 2xSchattenabstand).
    margin = 70
    scale = (H - 2 * margin) / (1920.0 + 2 * (14 + 30))
    tw, th = int(1080 * scale), int(1920 * scale)
    scr = shot.resize((tw, th), Image.LANCZOS)
    phone = phone_mockup(scr, scale=scale)
    px = 120
    py = (H - phone.height) // 2
    bg.alpha_composite(phone, (px, py))

    # Text rechts vom Geraet, linksbuendig (breite Headlines wuerden sonst
    # ueber den Geraeterand hinausragen).
    f_head = ImageFont.truetype(FONT_BOLD, 78)
    f_sub = ImageFont.truetype(FONT_REG, 38)
    tx = px + phone.width + 100
    y = max(200, (H - 400) // 2)
    y = draw_lines(draw, None, headline, f_head, (255, 255, 255, 255), 20,
                   tx, y, align='left')
    y += 24
    y = draw_lines(draw, None, subline, f_sub, (255, 255, 255, 226), 14,
                   tx, y, align='left')
    y += 40
    # Badge an der Textkante ausrichten
    f_badge = ImageFont.truetype(FONT_BOLD, 36)
    bb = draw.textbbox((0, 0), badge, font=f_badge)
    bw = bb[2] - bb[0] + 2 * 68
    layer = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [tx, y, tx + bw, y + bb[3] - bb[1] + 40],
        radius=(bb[3] - bb[1] + 40) // 2,
        fill=(255, 255, 255, 52), outline=(255, 255, 255, 130), width=2)
    ImageDraw.Draw(layer).text(
        (tx + 68 - bb[0], y + 20 - bb[1]), badge, font=f_badge,
        fill=(255, 255, 255, 250))
    bg.alpha_composite(layer)
    return bg.convert('RGB')


def main():
    if not SRC.exists():
        sys.exit('Keine App-Screens gefunden. Erst rendern:\n'
                 '  $env:STORE_SHOTS="1"; flutter test --update-goldens '
                 'test/screenshots/store_v091_shots_test.dart')
    for d in (OUT_9x16, OUT_WQHD, OUT_FASTLANE):
        d.mkdir(parents=True, exist_ok=True)

    for name, (headline, subline, badge) in SHOTS.items():
        src = SRC / f'{name}.png'
        if not src.exists():
            print('  fehlt:', src.name)
            continue
        shot = Image.open(src)
        a = compose_9x16(shot, headline, subline, badge)
        b = compose_wqhd(shot, headline, subline, badge)
        a.save(OUT_9x16 / f'{name}.png', optimize=True)
        b.save(OUT_WQHD / f'{name}.png', optimize=True)
        a.save(OUT_FASTLANE / f'{name}.png', optimize=True)
        print(f'  {name}: 9x16 {a.size} + wqhd {b.size}')

    print('Fertig.')


if __name__ == '__main__':
    main()
