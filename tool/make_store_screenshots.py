"""
tool/make_store_screenshots.py
==============================
Erzeugt MARKETING-Screenshots fuer den Play Store aus den gerenderten
App-Screens (test/screenshots/store_v091/phone/*.png).

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
import re
import sys
import time

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'test' / 'screenshots' / 'store_v091' / 'phone'
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
#
# ACHTUNG - Text ist Produktversprechen, kein Design-Element.
# "In einer Minute startklar" stand hier bis v0.9.2, war aber falsch und
# wurde von der App selbst widerlegt: nach der E-Mail-Bestaetigung
# folgen 8 Seiten Einrichtung (settings_privacy_once_screen.dart,
# _pageCount = 8) und 8 Seiten Onboarding (onboarding_screen.dart,
# _pageCount = 8), dazu ein Pflicht-Foto. Das ist eine Investition von
# mehreren Minuten, keine von einer. Ein Screenshot, der das Gegenteil
# behauptet, ist Marketing-Waffenschmiede.
#
# Kriterien fuer die Badges, in dieser Reihenfolge:
#   1. Nachpruefbar aus dem Code.
#   2. Kein Zeitversprechen, keine Mengenangabe ohne Beleg.
#   3. Erklaert ein echtes Alleinstellungsmerkmal.
SHOTS = {
    '01_willkommen': (
        'Blind Date mit\nSubstanz',
        'Persönlichkeit vor Aussehen: Hör erst zu,\n'
        'und siehst ein Foto erst nach dem Funke.',
        'Kein Foto vor dem Kennenlernen',
    ),
    '02_anmelden': (
        'Erst prüfen,\n'
        'dann freischalten',
        'Mit E-Mail bestätigen, Profil ausfüllen,\n'
        'Geburtsdatum hinterlegen, los.',
        'Foto erst nach dem Funke',
    ),
    '03_entdecken': (
        'Fünf Wege,\n'
        'einen Funken zu zünden',
        'Von Find your Match bis Transit Spark:\n'
        'im Zug nebenan Blickkontakt genügt.',
        'Ende-zu-Ende-verschlüsselt',
    ),
    '04_anpassen': (
        'Dein Stil,\n'
        'deine Farben',
        'Sechs Farbschemata, Hell/System/Dunkel und ein eigener\n'
        'Chat-Hintergrund – alles bleibt erhalten.',
        'Auch 6 Muster im Chat',
    ),
    '05_eisbrecher': (
        '60 Fragen gegen\n'
        'das Schweigen',
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


# Geraetemasse, in den Pixeln des 1080x2400-Quellrendings (mit `scale`
# skaliert).
#
# v0.9.2: Die Werte korrigiert. Vorher BEZEL=36, das sind 3.3% der
# Bildbreite - bei einem echten Pixel-class Geraet liegt der Rand bei
# 8..14 px. Zusammen mit dem dicken, gleichmässigen Rahmen wirkte das
# Geraet wie eine Tafel statt wie ein Telefon. Jetzt 12 px, was einem
# zeitgeraeten Android-Geraet entspricht.
BEZEL = 12
PAD = 40
CAM_R = 11

# System-UI in dp (Source-Render ist 360x800 dp bei dpr 3).
# Der App-Render reserviert seit dem SafeArea-Fix genau diese Insets -
# sie werden hier als echte Elemente gezeichnet, damit der Screen wie
# ein Geraet und nicht wie ein Bild aussieht.
STATUS_BAR_DP = 24
NAV_BAR_DP = 24


def _draw_status_bar(img: Image.Image):
    """Zeichnet die System-Statusleiste: Indikatoren links, Akku rechts.

    Wichtig: der App-Render hat seit dem SafeArea-Fix oben eine Luecke
    (24 dp). Stand dort nichts, wirkte der Screen abgeschnitten - als
    fehle genau der Bereich, an dem das Auge ein Geraet erkennt.

    Der Screen ist bereits auf die Mockup-Groesse skaliert, deshalb wird
    hier gegen die tatsaechliche Bildhoehe gerechnet statt gegen die
    Source-Dp-Werte.

    Zwei Details, die den ersten Versuch unbrauchbar machten:
      * Die Punch-Hole-Kamera sitzt oben MITTEN. Eine dort gezeichnete
        Leiste kollidiert mit ihr - die Leiste ist deshalb auf die
        Seiten verteilt, wie es Material 3 vorgibt.
      * Die Leiste fuellt nur den oberen Drittel des reservierten
        Streifens. Sie wird jetzt auf dessen Mitte gezeichnet.
    """
    d = ImageDraw.Draw(img)
    w, h = img.size
    band = h * (STATUS_BAR_DP / 800.0)   # reservierter Streifen
    if band < 8:
        return
    H = int(band)
    cy = H / 2.0

    # Kein Text in der Mitte: dort ist die Kamera.

    # Uhr links, bewusst nicht die echte Uhrzeit, sondern eine runde
    # Form - sie soll die Position zeigen, nicht eine Behauptung.
    cx, cy = w * 0.085, H / 2
    r = max(2.0, H * 0.10)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 225))

    # Signal-Balken (4 Balken, Hoehen 0.30..0.78 der Leiste)
    bx = w * 0.845
    for i in range(4):
        bh = H * (0.30 + 0.16 * i)
        x0 = bx + i * H * 0.20
        d.rounded_rectangle(
            [x0, cy + H * 0.32 - bh, x0 + H * 0.12, cy + H * 0.32],
            radius=int(H * 0.05), fill=(255, 255, 255, 200))

    # WLAN-Symbol als vereinfachter Bogen.
    # PIL verlangt bei arc/zwei Argumenten Ganzzahlen - hier wird
    # deshalb einmalig auf int gerundet statt an jeder Stelle.
    wx = int(w * 0.925)
    rr = H * 0.30
    d.arc([wx - rr, cy - rr, wx + rr, cy + rr], 210, 330,
          fill=(255, 255, 255, 210), width=max(1, int(H * 0.07)))
    d.arc([wx - rr * 0.55, cy - rr * 0.45, wx + rr * 0.55, cy + rr * 0.8],
          210, 330, fill=(255, 255, 255, 210), width=max(1, int(H * 0.07)))
    d.ellipse([wx - H * 0.05, cy - H * 0.02,
               wx + H * 0.05, cy + H * 0.10],
              fill=(255, 255, 255, 225))

    # Akku
    ax, aw, ah = w * 0.062, H * 0.44, H * 0.24
    d.rounded_rectangle(
        [w - ax - aw, cy - ah / 2, w - ax, cy + ah / 2],
        radius=int(H * 0.05), outline=(255, 255, 255, 220),
        width=max(1, int(H * 0.035)))
    d.rounded_rectangle(
        [w - ax - aw + aw * 0.14, cy - ah * 0.28,
         w - ax - aw * 0.22, cy + ah * 0.28],
        radius=int(H * 0.03), fill=(255, 255, 255, 235))
    d.rounded_rectangle(
        [w - ax + 1, cy - ah * 0.14, w - ax + H * 0.05, cy + ah * 0.14],
        radius=int(H * 0.02), fill=(255, 255, 255, 200))


def _draw_nav_bar(img: Image.Image):
    """Zeichnet die Gesture-Navigation als hellen Strich mittig unten.

    Der Strich bekommt eine dezente scrim-artige Hinterlegung: auf einem
    echten Geraet liegt die Systemleiste ueber dem App-Inhalt, und ohne
    den dunklen Saum verschwindet der Strich auf hellen Kacheln. Der
    Saum ist sehr weich und nur so breit wie der reservierte Streifen.
    """
    d = ImageDraw.Draw(img)
    w, h = img.size
    band = h * (NAV_BAR_DP / 800.0)
    if band < 6:
        return
    cy = h - band / 2.0

    # Weicher Saum, damit der Strich auf hellem Inhalt lesbar bleibt.
    scrim = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(scrim).rectangle(
        [0, int(h - band * 1.5), w, h], fill=(0, 0, 0, 42))
    img.alpha_composite(scrim.filter(ImageFilter.GaussianBlur(band * 0.35)))

    d = ImageDraw.Draw(img)
    bw, bh = w * 0.28, max(2.0, band * 0.11)
    d.rounded_rectangle(
        [w / 2 - bw / 2, cy - bh / 2, w / 2 + bw / 2, cy + bh / 2],
        radius=int(bh / 2), fill=(255, 255, 255, 205))


def phone_mockup(screen: Image.Image, scale=1.0):
    """Natuerliches Smartphone-Mockup.

    Rundum gleiche, sichtbare Randbreite, echte Punch-Hole-Kamera mit
    dunklem Ring, Linse und Glanzpunkt, weicher Schlagschatten. Sieht aus wie
    ein Handy und nicht wie eine Folie.
    """
    w, h = screen.size
    b = BEZEL * scale
    bs = bt = bb = b
    pad = PAD * scale
    radius_out = 54 * scale
    radius_in = 42 * scale

    body_w, body_h = int(w + 2 * bs), int(h + bt + bb)
    pad_i = int(pad)
    canvas = Image.new('RGBA', (body_w + 2 * pad_i, body_h + 2 * pad_i), (0, 0, 0, 0))

    # Weicher Schlagschatten unter dem Geraet
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad_i - 5 * scale, pad_i + 12 * scale,
         pad_i + body_w + 5 * scale, pad_i + body_h + 20 * scale],
        radius=radius_out, fill=(18, 0, 36, 130))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20 * scale)))

    # Geraetekorpus (Graphit, heller Rand)
    body = Image.new('RGBA', (body_w, body_h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, body_w - 1, body_h - 1], radius=radius_out,
        fill=(26, 19, 38, 255), outline=(255, 255, 255, 78),
        width=max(2, int(2 * scale)))

    # Screen mit gerundeten Ecken
    scr = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    scr.paste(screen.convert('RGBA'), (0, 0), rounded_mask((w, h), radius_in))
    # System-UI auf den Screen zeichnen. Der App-Render reserviert diese
    # Insets seit dem SafeArea-Fix, zeigt aber selbst nichts - ohne sie
    # bleibt oben und unten ein leerer Streifen, der wie abgeschnitten
    # wirkt. Gezeichnet wird NACH dem Einfuegen, damit die Kacheln des
    # Randes nicht darueberliegen.
    _draw_status_bar(scr)
    _draw_nav_bar(scr)
    body.alpha_composite(scr, (int(bs), int(bt)))

    d = ImageDraw.Draw(body)

    # Punch-Hole-Kamera mittig im oberen Rand: dunkler Rand, dunkelblaue
    # Linse, kleiner Glanzpunkt. Wichtig: opake Farben auf einer eigenen Ebene
    # - alpha_composite mischt, ImageDraw auf dem Korpus wuerde ihn durchbohren.
    cr = int(CAM_R * scale)
    cx, cy = int(body_w / 2), int(bt / 2)
    side = 2 * cr + 2
    cam = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    dc = ImageDraw.Draw(cam)
    dc.ellipse([1, 1, side - 2, side - 2], fill=(8, 6, 12, 255))
    inset = max(1, int(cr * 0.32))
    dc.ellipse([inset, inset, side - 1 - inset, side - 1 - inset],
               fill=(28, 34, 56, 255))
    mid = max(1, int(cr * 0.66))
    dc.ellipse([mid, mid, side - 1 - mid, side - 1 - mid], fill=(9, 12, 24, 255))
    dc.ellipse([int(cr * 1.05), int(cr * 0.75), int(cr * 1.7), int(cr * 1.4)],
               fill=(150, 155, 175, 255))
    body.alpha_composite(cam, (cx - cr - 1, cy - cr - 1))

    canvas.alpha_composite(body, (pad_i, pad_i))
    return canvas


def fit_scale(shot: Image.Image, box_h: int, box_w: int = 10 ** 9):
    """Scale, damit Screen + Bezel + Schattenplatz in box_h/box_w passen."""
    h = shot.height + 2 * (BEZEL + PAD)
    w = shot.width + 2 * (BEZEL + PAD)
    return min(box_h / h, box_w / w)


def round_corners(img: Image.Image, radius: int):
    """Beschneidet das fertige Bild auf abgerundete Ecken (aussen transparent)."""
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img.convert('RGBA'), (0, 0), rounded_mask(img.size, radius))
    return out


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
    f_head = ImageFont.truetype(FONT_BOLD, 70)
    f_sub = ImageFont.truetype(FONT_REG, 34)
    y = 110
    y = draw_lines(draw, None, headline, f_head, (255, 255, 255, 255), 18,
                   W // 2, y)
    y += 26
    y = draw_lines(draw, None, subline, f_sub, (255, 255, 255, 226), 13,
                   W // 2, y)

    # --- Phone-Mockup: Hoehe an den Restkasten anpassen ------------------
    mock_h = H - y - 170
    scale = fit_scale(shot, mock_h, W - 120)
    tw, th = int(shot.width * scale), int(shot.height * scale)
    scr = shot.resize((tw, th), Image.LANCZOS)
    phone = phone_mockup(scr, scale=scale)
    px = (W - phone.width) // 2
    py = y + 30
    bg.alpha_composite(phone, (px, py))

    # --- Badge unter dem Geraet -------------------------------------------
    by = min(py + phone.height + 18, H - 100)
    badge_pill(bg, badge, W // 2, by)
    return round_corners(bg, 56)


def compose_wqhd(shot: Image.Image, headline: str, subline: str, badge: str):
    W, H = 2560, 1440
    bg = gradient((W, H), 25).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    # Phone links: Hoehe so skalieren, dass es mit Rand sicher passt
    # (Mockup = Screen + Bezel + 2xSchattenabstand).
    margin = 60
    scale = fit_scale(shot, H - 2 * margin, 1000)
    tw, th = int(shot.width * scale), int(shot.height * scale)
    scr = shot.resize((tw, th), Image.LANCZOS)
    phone = phone_mockup(scr, scale=scale)
    px = 130
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
    return round_corners(bg, 56)


def save_png(img: Image.Image, path: pathlib.Path, tries: int = 6):
    """PNG schreiben mit Retry.

    Windows-Defender/Indexer haelt die neu geschriebene Datei manchmal
    kurzzeitig offen; dann schlaegt das Speichern mit Errno 22 fehl.
    """
    last = None
    for attempt in range(tries):
        try:
            img.save(path, optimize=True)
            return
        except OSError as e:  # Datei temporaer gesperrt
            last = e
            time.sleep(0.4 * (attempt + 1))
    raise last


def _check_claims():
    """Sperrt Textversprechen, die der Code nicht einloest.

    Bis v0.9.2 stand in den Shots "In einer Minute startklar" und
    "Kostenlos. Fuer immer." Beides war unbelegbar bzw. falsch - der
    Registrierungsweg dauert nach der E-Mail-Bestaetigung 8 Setup- und
    8 Onboarding-Seiten. Der Fehler war nicht der schlechte Text,
    sondern dass niemand pruefen konnte, dass er stimmt.

    Diese Liste ist bewusst eine Positivliste: sie erlaubt Formulie-
    rungen, deren Richtigkeit aus dem Quellcode hervorgeht, und
    blockiert die beiden Arten von Aussagen, die erfahrungsgemaess falsch
    werden - Zeitversprechen und unbegruendete Mengenangaben.
    """
    forbidden = [
        # Zeitversprechen. "einer/eine Minute", "eine Minute", "Minuten"
        # in jeder Form - der Zwischenwort-Abstand ist gewolft offen.
        (r'\b(in|einer|eine)?\s*minut', 'Zeitversprechen ohne Beleg'),
        (r'\bsofort\b', '"sofort" ist ein Zeitversprechen'),
        (r'\bsekunden?\b', 'Zeitversprechen ohne Beleg'),
        (r'\bkostenlos', '"kostenlos" ist eine Preiszusage, keine Funktion'),
        (r'\bunbegrenzt', '"unbegrenzt" ist eine Ressourcen-Zusage'),
        (r'\bnie\s+gelöscht', 'Datenloesch-Zusage'),
        (r'\bsicher\b(?!heit)', '"sicher" ohne Bezug ist eine Behauptung'),
        (r'\b\d+\s*%\s*(sicher|verschlüsselt)',
         'Prozentangabe zur Verschluesselung ist nicht belegbar'),
    ]
    problems = []
    for name, (headline, subline, badge) in SHOTS.items():
        blob = ' '.join((headline, subline, badge))
        for pattern, why in forbidden:
            m = re.search(pattern, blob, re.I)
            if m:
                problems.append(
                    f'{name}: "{m.group(0)}" - {why}')
    return problems


def main():
    if not SRC.exists():
        sys.exit('Keine App-Screens gefunden. Erst rendern:\n'
                 '  $env:STORE_SHOTS="1"; flutter test --update-goldens '
                 'test/screenshots/store_v091_shots_test.dart')

    problems = _check_claims()
    if problems:
        print('STORE-SCREENSHOT-TEXT abgelehnt:', file=sys.stderr)
        for p in problems:
            print('  X', p, file=sys.stderr)
        print('\nDer Text ist ein Produktversprechen. Wenn die Aussage '
              'zutrifft,\ndarf sie NICHT einfach hier erlaubt werden - '
              'sie muss im Kommentar\nzu SHOTS begruendet werden, damit '
              'sie beim naechsten Review wiedergeprueft wird.',
              file=sys.stderr)
        sys.exit(1)

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
        for d, im in ((OUT_9x16, a), (OUT_WQHD, b), (OUT_FASTLANE, a)):
            save_png(im, d / f'{name}.png')
        print(f'  {name}: 9x16 {a.size} + wqhd {b.size}')

    print('Fertig.')


if __name__ == '__main__':
    main()
