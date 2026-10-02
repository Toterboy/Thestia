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
TILES = ROOT / 'test' / 'screenshots' / 'store_v091' / 'tiles'
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
        # Stand vorher "Ohne Stockfoto-Posen". Das ist kein
        # Nutzenversprechen, sondern eine Abgrenzung gegen etwas, das
        # gar nicht zur App gehoert - und "ohne" liest sich wie ein
        # Mangel. Ersetzt durch die tatsaechliche Eigenschaft: die
        # Fragen sind kopierfertig, man muss nichts tippen. Das ist der
        # Grund, warum es eine Eisbrecher-Liste gibt.
        'Antippen, senden, plaudern',
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

# Sprite der echten Statusleisten-Symbole, aus dem Referenz-Screenshot
# geschnitten (siehe tool/make_statusbar_assets.py). Fehlt die Datei,
# wird zurueckgezeichnet - die Rueckfallloesung ist schlechter, aber
# sie existiert, damit ohne Referenz ueberhaupt ein Bild entsteht.
STATUSBAR_SPRITE = ROOT / 'assets' / 'images' / 'statusbar_icons.png'
STATUSBAR_GEOMETRY = ROOT / 'tool' / 'statusbar_geometry.json'
STATUSBAR_ORDER = ('mute', 'wifi', 'signal', 'battery')


def _draw_clock(img, d, cy, color):
    """Zeichnet die Uhrzeit nach den gemessenen Werten der Referenz.

    Die Geometrie steht in tool/statusbar_geometry.json unter "clock" und
    wird von tool/make_statusbar_assets.py aus dem Referenzfoto
    ermittelt. Fehlt sie (kein Sprite im Repository), wird auf eine
    sinnvolle Naeherung zurueckgefallen, damit ueberhaupt eine Uhr da
    ist.
    """
    import json
    w, _h = img.size
    u = float(w)

    text = '3:41'
    width_f = 0.0549
    left_f = 0.0717
    height_f = 0.0211
    if STATUSBAR_GEOMETRY.is_file():
        try:
            geom = json.loads(STATUSBAR_GEOMETRY.read_text(
                encoding='utf-8-sig'))
            clock_geom = geom.get('clock') or {}
            text = clock_geom.get('text') or text
            width_f = float(clock_geom.get('widthFraction', width_f))
            left_f = float(clock_geom.get('leftFraction', left_f))
            height_f = float(clock_geom.get('heightFraction', height_f))
        except (OSError, ValueError):
            pass

    target_w = width_f * u
    # Startgroesse aus der gemessenen Hoehe: Ziffernhoeh ist etwa
    # 0,72 der Schriftgroesse.
    size = max(7, int(height_f * u / 0.72))
    f = None
    for _ in range(4):
        try:
            f = ImageFont.truetype(FONT_REG, size)
        except OSError:
            return False
        bb = d.textbbox((0, 0), text, font=f)
        got = bb[2] - bb[0]
        if got <= 0:
            return False
        if abs(got - target_w) <= 1:
            break
        size = max(7, int(size * target_w / got))
    if f is None:
        return False
    bb = d.textbbox((0, 0), text, font=f)
    # Vertikale Mitte auf cy. PIL liefert die Textbox mit negativem
    # oberem Rand bei Glyphen, die ueber die Grundlinie ragen - deshalb
    # die Mitte aus beiden Kanten und nicht aus th allein.
    top = cy - (bb[1] + bb[3]) / 2
    d.text((left_f * u, top), text, font=f, fill=color)
    return True


def _paste_status_bar_icons(img, cy, tint, draw):
    """Setzt die echten Symbole aus dem Sprite ein. True bei Erfolg.

    Der MASSSTAB ist der Quotient aus den Bildbreiten, nicht eine
    geratene Prozentangabe. Das ist der Unterschied zwischen "Aehnlich"
    und "skaliert":

      * Die gezeichnete Fassung setzte den Cluster auf geratene 30 % der
        Bildbreite und die Symbole auf 3,5 % Hoehe. Gemessen sind es
        18,99 % und 2,32 %. Die Zeichnung war also um die Haelfte zu
        gross - unabhaengig davon, wie korrekt die Formen waren.
      * Mit dem Quotienten gilt fuer jedes Zielbild: dasselbe
        Verhaeltnis wie auf dem Geraet des Nutzers.

    Der AKKU wird gezeichnet, nicht aus dem Sprite genommen. Das Sprite
    enthaelt eine Silhouette, und im Akku ist die Silhouette ein
    gefuelltes Rechteck - die Prozentzahl verschwindet darin. Sie ist
    aber der eigentliche Inhalt des Symbols, also wird sie wieder
    gezeichnet, jetzt mit den gemessenen Proportionen statt mit
    geratenen. Die Proportionen kommen aus derselben Datei wie die der
    uebrigen Symbole, damit der Akku nicht auffaellt.
    """
    import json
    if not STATUSBAR_SPRITE.is_file() or not STATUSBAR_GEOMETRY.is_file():
        return False
    try:
        geom = json.loads(STATUSBAR_GEOMETRY.read_text(encoding='utf-8'))
        sprite = Image.open(STATUSBAR_SPRITE).convert('RGBA')
    except (OSError, ValueError, KeyError):
        return False

    boxes = geom.get('sprite') or {}
    widths = geom.get('iconWidthFraction') or {}
    if any(n not in boxes or n not in widths for n in STATUSBAR_ORDER):
        return False

    target = tuple(tint[:3])
    w, h = img.size
    u = float(w)

    ref_w = float(geom['sourceSize'][0])
    scale = u / ref_w                      # exakt: Verhaeltnis der Breiten
    gap = float(geom.get('gapFraction', 0.015)) * u
    right_margin = float(geom.get('rightMarginFraction', 0.06)) * u
    height = float(geom.get('iconHeightFraction', 0.023)) * u

    cursor = w - right_margin

    for name in reversed(STATUSBAR_ORDER):
        icon_w = widths[name] * u
        b = boxes[name]
        tile = sprite.crop((b['x'], b['y'], b['x'] + b['w'], b['y'] + b['h']))

        if name == 'battery':
            _draw_reference_battery(
                draw, cursor, cy, icon_w, height, target, gap)
        else:
            # Hintergrundfarbe aus dem Ausschnitt schaetzen, Maske
            # bilden, DANN den transparenten Rand wegschneiden - und
            # zwar ueber die Alphabbox, nicht ueber eine feste
            # Padding-Zahl.
            #
            # Feste Zahl war der Fehler: der Sprite-Ausschnitt ist
            # 2*padding+1 = 11 Pixel hoch, ein 5-Pixel-Beschnitt oben
            # und unten laesst EINE Zeile uebrig. Das ist die
            # Mittellinie des Icons, und die sieht aus wie vier kurze
            # Striche. Die Alphabbox schneidet genau das ab, was
            # unsichtbar ist, und sonst nichts.
            bg = _estimate_background(tile)
            mask = _icon_mask(tile, bg)
            box = mask.getbbox()
            if box is None:
                cursor -= icon_w + gap
                continue
            mask = mask.crop(box)
            tw = max(1, int(round(icon_w)))
            th = max(1, int(round(mask.size[1] * tw / mask.size[0])))
            mask = mask.resize((tw, th), Image.LANCZOS)
            recolored = Image.merge('RGBA', (
                Image.new('L', mask.size, target[0]),
                Image.new('L', mask.size, target[1]),
                Image.new('L', mask.size, target[2]),
                mask,
            ))
            img.alpha_composite(
                recolored, (int(cursor - tw), int(cy - th / 2)))
        cursor -= icon_w + gap

    return True


def _estimate_background(tile):
    """Mittlere Randfarbe eines Sprite-Ausschnitts.

    Der Rand ist per Definition nur Polster und damit nur Hintergrund -
    unabhaengig vom Motiv des Referenzfotos.
    """
    w, h = tile.size
    edge = []
    step = max(1, h // 6)
    for yy in range(0, h, step):
        edge.append(tile.getpixel((0, yy)))
        edge.append(tile.getpixel((w - 1, yy)))
    for xx in range(0, w, step):
        edge.append(tile.getpixel((xx, 0)))
        edge.append(tile.getpixel((xx, h - 1)))
    if not edge:
        return (255, 255, 255)
    return (sum(p[0] for p in edge) / len(edge),
            sum(p[1] for p in edge) / len(edge),
            sum(p[2] for p in edge) / len(edge))


def _draw_reference_battery(draw, right, cy, icon_w, height, target, gap):
    """Akku mit den aus der Referenz gemessenen Proportionen.

    Die Proportionen kommen aus `statusbar_geometry.json`: Breite
    5,06 % der Bildbreite, Hoehe der Iconfeldhoehe. Das Seitenverhaeltnis
    von rund 2:1 ist damit ebenfalls gemessen und nicht geraten -
    die gezeichnete Fassung lag bei 3,4:1 und war deshalb sichtbar zu
    breit.
    """
    body_h = height * 0.78
    body_w = icon_w - gap * 0.9          # der Kontaktstift ist schmaler
    x1 = right - gap * 0.9
    x0 = x1 - body_w
    y0 = cy - body_h / 2
    stroke = max(1, int(height * 0.075))

    draw.rounded_rectangle(
        [x0, y0, x1, y0 + body_h],
        radius=body_h * 0.30, outline=target, width=stroke)
    # Kontaktstift nach rechts
    nub_w = gap * 0.9
    draw.rounded_rectangle(
        [x1 + 1, cy - body_h * 0.20, x1 + nub_w, cy + body_h * 0.20],
        radius=max(1, int(body_h * 0.10)), fill=target)

    # Prozentzahl. Sie ist der eigentliche Inhalt dieses Symbols - ohne
    # sie waere der Akku nur eine Form. Deshalb wird sie gezeichnet
    # statt der Silhouette aus dem Sprite genommen zu werden, wo sie
    # im gefuellten Rechteck verschwindet.
    try:
        f = ImageFont.truetype(FONT_BOLD, max(6, int(body_h * 0.62)))
        bb = draw.textbbox((0, 0), '70', font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        if tw <= body_w - 2 * stroke:
            draw.text(
                (x0 + (body_w - tw) / 2 - bb[0],
                 cy - th / 2 - bb[1]),
                '70', font=f, fill=target)
    except OSError:
        pass


def _icon_mask(tile, bg):
    """Harte Silhouettenmaske eines Symbols aus dem Referenzfoto.

    `bg` ist die geschaetzte Hintergrundfarbe des Fotos; Abweichung von
    ihr ist das Signal, nicht die absolute Helligkeit.

    Erster Versuch war "Abstand zu Weiss" als Deckkraft. Das
    funktioniert nur auf weissem Grund. Die Referenz des Nutzers ist
    ein Foto, und ein Himmelspixel liegt 185 Einheiten von Weiss weg,
    bekam also Deckkraft 194 und blieb als graue Box stehen.

    Danach wird binarisiert statt weich skaliert: die Referenz ist ein
    auf 474 px verkleinerter Ausschnitt eines 1080-px-Screens, ihre
    Symbole sind etwa 11 px hoch. Weich hochskaliert wird daraus
    grauer Matsch mit Halo, der wie die alte Zeichnung aussieht, nur
    blasser. Als Silhouette ist die Form exakt die des Originals, und
    die Kanten werden beim Skalieren wieder sauber.
    """
    wpx, hpx = tile.size
    br, bg_, bb = bg

    raw = Image.new('L', tile.size, 0)
    src = tile.load()
    rp = raw.load()
    for yy in range(hpx):
        for xx in range(wpx):
            r, g, b, _a = src[xx, yy]
            dev = abs(r - br) + abs(g - bg_) + abs(b - bb)
            rp[xx, yy] = 0 if dev < 45 else min(255, int(dev * 2))

    # Oeffnung: entfernt einzelne verirrte Pixel aus dem
    # Anti-Aliasing, ohne die echten Striche anzutasten.
    cleaned = raw.filter(ImageFilter.MaxFilter(3)).filter(
        ImageFilter.MinFilter(3))
    return cleaned.point(lambda v: 255 if v > 128 else 0)


def _draw_status_bar(img: Image.Image, clock='3:41', percent='70'):
    """Zeichnet die System-Statusleiste nach dem Geraet des Nutzers.

    ZWEI WEGE, und der erste ist der richtige:

    1. Sprite aus dem echten Referenz-Screenshot. Ist
       `assets/images/statusbar_icons.png` vorhanden (erzeugt von
       `tool/make_statusbar_assets.py`), werden die Original-Symbole
       pixelgenau eingesetzt. Handgezeichnete Naeherungen sind der
       Grund, warum die Leiste dreimal nicht gepasst hat: Android-
       Symbole sind Vektorpfade mit eigenen Kurven, und ein
       nachgezeichneter Bogen ist nie derselbe Bogen.

    2. Ohne Sprite wird zurueckgezeichnet, nach den Verhaeltnissen aus
       der Referenz (Cluster 30 % der Bildbreite, Uhr 7 %, linker Rand
       6,5 %, rechter Rand 3,9 %). Das ist die zweite Schicht und sie
       ist deutlich schlechter - sie existiert nur, damit ohne
       Referenzdatei ueberhaupt etwas dasteht.

    Die Anordnung ist in beiden Faellen gleich, von links nach rechts:

        [3:41]  ......  [Stumm] [WLAN] [Signal] [Akku mit 70]
    """
    d = ImageDraw.Draw(img)
    w, h = img.size
    band = h * (STATUS_BAR_DP / 800.0)
    if band < 10:
        return
    cy = band / 2.0

    ICON = (38, 34, 44, 245)
    u = float(w)

    def font(path, px):
        try:
            return ImageFont.truetype(path, max(7, int(px)))
        except OSError:
            return None

    # --- Uhrzeit links -------------------------------------------------
    # Nach den GEMESSENEN Werten, nicht nach einer Schriftgroesse.
    #
    # Bisher stand hier u*0.030 als Schriftgroesse. Gemessen ist die Uhr
    # aber 5,49 % BREIT und 2,11 % hoch, mit einem linken Rand von
    # 7,17 %. Aus einer Schriftgroesse folgt keine Breite - je nach
    # Zeichensatz ist derselbe Wert 20 % breiter. Deshalb wird die
    # Schriftgroesse so lange nachgezogen, bis die gerenderte Breite
    # passt; drei Schritte reichen fuer jede Ziffernfolge.
    #
    # Zusaetzlich FONT_REG statt FONT_BOLD. Die Referenzschrift ist
    # sichtbar leichter; die fette Variante war der zweite Grund, warum
    # die Leiste neben echten Android-Symbolen nicht stimmte.
    # Die Uhr wird IMMER gezeichnet. Zurueckgegeben wird nur, ob der
    # Sprite-Einsatz klappt - dann braucht es die gezeichneten Symbole
    # nicht mehr. Ein `return` nach der Uhr (Stand vor diesem Fix)
    # hat die Symbole uebersprungen: die Leiste zeigte nur die Uhr.
    _draw_clock(img, d, cy, ICON)
    if _paste_status_bar_icons(img, cy, ICON, d):
        return

    def centered(text, fnt, fill, left, width):
        """Text horizontal in [left, left+width] und vertikal auf cy zentrieren."""
        if fnt is None:
            return
        bb = d.textbbox((0, 0), text, font=fnt)
        d.text((left + (width - (bb[2] - bb[0])) / 2 - bb[0],
                cy - (bb[3] - bb[1]) / 2 - bb[1]), text, font=fnt, fill=fill)

    # --- Cluster rechts, vom Rand rueckwaerts ----------------------------
    # Reihenfolge und Breiten aus der Referenz. Der Akku ist eine breite,
    # flache Pille MIT der Prozentzahl darin - kein gefuellter Balken und
    # keine Zahl daneben.
    gap = u * 0.013
    icon_h = u * 0.035          # Hoehe der Signalbaenke = hoechste Glyphe
    stroke = max(1, int(u * 0.0035))

    # Akku ganz rechts: Pille mit Prozentzahl, Kontaktstift nach rechts.
    bat_h = icon_h * 0.92
    bat_w = u * 0.108
    nub_w = u * 0.008
    bat_x1 = int(u * (1 - 0.039) - nub_w)
    bat_x0 = bat_x1 - int(bat_w)
    bat_y0 = int(cy - bat_h / 2)
    d.rounded_rectangle([bat_x0, bat_y0, bat_x1, bat_y0 + int(bat_h)],
                        radius=int(bat_h * 0.34), outline=ICON, width=stroke)
    d.rounded_rectangle([bat_x1 + 1, int(cy - bat_h * 0.22),
                         bat_x1 + int(nub_w), int(cy + bat_h * 0.22)],
                        radius=max(1, int(bat_h * 0.10)), fill=ICON)
    f_pct = font(FONT_BOLD, bat_h * 0.78)
    centered(percent, f_pct, ICON, bat_x0, bat_w)

    # Signal: vier aufsteigende Balken, links vom Akku.
    sig_w = u * 0.055
    sig_x1 = bat_x0 - gap
    bar_gap = u * 0.006
    bar_w = (sig_w - 3 * bar_gap) / 4
    for i in range(4):
        bh = icon_h * (0.34 + 0.22 * i)
        bx = sig_x1 - sig_w + i * (bar_w + bar_gap)
        d.rounded_rectangle([bx, cy + icon_h / 2 - bh,
                             bx + bar_w, cy + icon_h / 2],
                            radius=max(1, int(bar_w * 0.35)), fill=ICON)

    # WLAN: zwei Boegen und Punkt, links vom Signal.
    wifi_w = u * 0.039
    wifi_h = icon_h * 0.86
    wx = int(sig_x1 - sig_w - gap - wifi_w)
    dot_r = icon_h * 0.10
    dcx, dcy = wx + wifi_w / 2, cy + icon_h / 2 - dot_r * 0.6
    for k in (0.55, 1.0):
        r = wifi_h * 0.62 * k
        d.arc([dcx - r, dcy - r, dcx + r, dcy + r], 212, 328,
              fill=ICON, width=stroke)
    d.ellipse([dcx - dot_r, dcy - dot_r, dcx + dot_r, dcy + dot_r],
              fill=ICON)

    # Stumm: Lautsprecher mit Schraegstrich, links vom WLAN.
    mute_w = u * 0.028
    sx = int(wx - gap - mute_w)
    my = cy + icon_h * 0.06
    mh = icon_h * 0.46          # halbe Hoehe des Lautsprechers
    d.rectangle([sx, my - mh * 0.55, sx + mute_w * 0.20, my + mh * 0.55],
                fill=ICON)
    d.polygon([(sx + mute_w * 0.20, my - mh * 0.55),
               (sx + mute_w * 0.58, my - mh * 1.15),
               (sx + mute_w * 0.58, my + mh * 1.15),
               (sx + mute_w * 0.20, my + mh * 0.55)], fill=ICON)
    d.line([(sx - mute_w * 0.16, my + mh * 1.05),
            (sx + mute_w * 0.74, my - mh * 1.15)],
           fill=ICON, width=max(1, int(icon_h * 0.11)))


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
    # Wie bei der Statusleiste: die Leiste liegt auf der hellen App, nicht
    # auf dem Verlauf. Der weiche Saum bleibt (er hebt den Strich auf
    # bunten Kacheln ab), der Strich selbst ist aber deckend dunkel.
    bw, bh = w * 0.28, max(2.0, band * 0.11)
    d.rounded_rectangle(
        [w / 2 - bw / 2, cy - bh / 2, w / 2 + bw / 2, cy + bh / 2],
        radius=int(bh / 2), fill=(45, 38, 50, 210))


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


def app_tile(shot: Image.Image, box_h: int, box_w: int, corner_ratio=0.055):
    """Skaliert den App-Screen auf den Kasten und zeichnet die System-UI.

    v0.9.2: Ersetzt phone_mockup(). Das Geraet ist entfallen, der
    App-Screen steht direkt und abgerundet auf dem Verlauf.

    Die System-UI (Statusleiste, Gesture-Navigation) wird HIER gezeichnet
    und nicht mehr im Mockup - sonst fehlt sie nach dessen Wegfall
    komplett, und ein Screenshot ohne Statusleiste wirkt wie ein Bild
    statt wie ein Geraet. Der App-Render reserviert diese Streifen seit
    dem SafeArea-Fix, zeigt aber selbst nichts; sie werden deshalb
    zusaetzlich gemalt.

    corner_ratio: Eckenradius als Anteil der Breite. Ohne Mockup ist die
    Kachel das einzige abgerundete Element und traegt damit die
    Komposition - der Radius ist bewusst grosszuegig gewaehlt.
    """
    scale = min(box_h / shot.height, box_w / shot.width)
    tw, th = int(shot.width * scale), int(shot.height * scale)
    scr = shot.resize((tw, th), Image.LANCZOS)
    _draw_status_bar(scr)
    _draw_nav_bar(scr)
    return _round_image(scr, int(tw * corner_ratio))


def _round_image(img: Image.Image, radius: int) -> Image.Image:
    """Schneidet ein Bild auf abgerundete Ecken (RGBA, Radius in px).

    Anders als round_corners() wird hier NICHTS transparent ausserhalb
    gemacht - der App-Screen liegt auf dem Markenverlauf und soll mit
    seinen runden Ecken darauf schweben. transparent wuerde den
    Verlauf durchscheinen lassen und die Kachel wirkt hinein geschnitten.
    """
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img.convert('RGBA'), (0, 0), rounded_mask(img.size, radius))
    return out


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


def _crop_tile(img):
    """Schneidet aus dem Golden-Export genau die Kachel heraus.

    matchesGoldenFile erfasst immer den ganzen Screenshot-Frame, nicht
    das Widget. Der Export einer Einzel-Kachel ist deshalb 360x800
    (die View) mit der Kachel mittig darin und viel leerem Rand drum.

    Gesucht wird nach der Kachelkontur: Das erste von oben kommende
    breite Band heller Pixel ist die Kachel, ihr Ende ist das letzte
    solche Band. Alles darueber (Scaffold-Hintergrund) und darunter wird
    abgeschnitten.

    Bewusst ueber Pixel und nicht ueber eine gemeldete Groesse: die
    Kachelgroesse haengt am Inhalt der jeweiligen Modus-Beschreibung
    und ist deshalb pro Kachel verschieden (im Zwischenstand zwischen
    136 und 256 px Hoehe gemessen).
    """
    im = img.convert('RGB')
    w, h = im.size
    px = im.load()

    # Die Kachel ist EXAKT weiss (255,255,255); der Scaffold drumher ist
    # (247,247,251). Beide sind "hell" - deshalb wird nicht auf
    # Helligkeit, sondern auf exaktes Weiss geprueft. Mit einem
    # Schwellwert >700 lag die ganze View als Kachel da und der Crop
    # lief ins Leere.
    def is_card(x, y):
        r, g, b = px[x, y]
        return r >= 252 and g >= 252 and b >= 252

    # Vertikal: Zeilen, in denen ein nennenswerter Anteil der Breite
    # zur Kachel gehoert.
    rows = []
    for y in range(h):
        n = sum(1 for x in range(0, w, 4) if is_card(x, y))
        if n / len(range(0, w, 4)) > 0.5:
            rows.append(y)
    if not rows:
        return im
    top, bot = min(rows), max(rows)

    # Seitlich: Spalten, die ueber die Kachel-Hoehe weitgehend weiss sind.
    mid = range(top, bot + 1, 4)
    xs = [x for x in range(w)
          if sum(1 for y in mid if is_card(x, y)) > 0.6 * len(list(mid))]
    if not xs:
        return im
    left, right = min(xs), max(xs)
    return im.crop((left, top, right + 1, bot + 1))


def _card_shadow(img, radius, opacity=52, blur=16, dy=8):
    """Kachel mit weichem Schatten, auf einer groesseren Flaeche.

    Die Kacheln liegen auf dem gesättigten Markenverlauf. Ohne Schatten
    heben sie sich nur durch die Helligkeit ab und wirken eingeklebt.

    Wichtig: zurueckgegeben wird die Kachel INKLUSIVE Schatten, nicht
    nur der Schatten. Die erste Fassion lieferte nur die Schattenebene
    zurueck - die Kacheln fehlten dadurch in beiden fertigen Bildern,
    ohne Fehlermeldung, weil alpha_composite mit einem transparenten
    Bild stillschweigend nichts tut.

    Rueckgabe: (bild, x_offset, y_offset) - das Bild ist um pad links/
    oben und um dy unten groesser als die Kachel.
    """
    w, h = img.size
    pad = int(blur * 2)
    total = (w + 2 * pad, h + 2 * pad + dy)

    # 1) Schattenebene
    shadow = Image.new('RGBA', total, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad, pad + w, pad + h], radius=radius,
        fill=(18, 0, 32, opacity))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    # 2) Kachel OBEN AUF den Schatten legen - nicht daneben.
    out = shadow
    out.alpha_composite(img.convert('RGBA'), (pad, pad))
    return out, pad, pad


# Die echte Modus-Kachel ist eine Card mit 16 dp Eckradius
# (swipe_mode_selection_screen.dart). Der Golden-Export schneidet nur die
# exakt weissen Pixel heraus und verliert damit genau diese Rundung -
# die Kacheln wirkten dadurch wie aufgeklebte Rechtecke. Der Radius wird
# hier aus der Kachelbreite zurueckgerechnet, damit die Kachel im fertigen
# Bild exakt so rund ist wie in der App.
TILE_RADIUS_DP = 16
TILE_WIDTH_DP = 312


def _round_tile(tile, col_w):
    """Kachel auf die Zielbreite bringen und mit dem echten Radius runden."""
    r = max(2, int(round(col_w * TILE_RADIUS_DP / TILE_WIDTH_DP)))
    return round_corners(tile, r)


def _tile_scale(tiles, max_w, avail_h, gap):
    """Groesster gemeinsamer Skalierungsfaktor fuer alle Kacheln.

    Begrenzt von der Breite (max_w) und von der Hoehe (avail_h inklusive
    der Abstaende). Beide Grenzen sind noetig: eine Kachel, die nur in die
    Breite passt, wuerde unten aus dem Bild laufen oder die naechste
    ueberdecken.
    """
    widest = max(t.width for t in tiles)
    total_h = sum(t.height for t in tiles)
    by_w = max_w / widest
    by_h = (avail_h - (len(tiles) - 1) * gap) / total_h
    return min(by_w, by_h)


def _place_tiles(bg, tiles, y, avail_h, max_w, gap, x=None, center_w=0):
    """Kacheln untereinander ab y setzen, zentriert im Restfeld.

    `x` setzt die Kacheln auf eine feste linke Kante (16:9 nutzt das fuer
    die Textspalte). `center_w` mittelt sie stattdessen in dieser Breite -
    im 9:16-Bild ist die Mitte die einzige sinnvolle Wahl, weil die
    Kachelbreite erst aus der Hoehenbegrenzung entsteht.

    Gibt die tatsaechliche Kantenbreite zurueck, damit der Aufrufer den
    Textblock daneben setzen kann.
    """
    k = _tile_scale(tiles, max_w, avail_h, gap)
    col_w = int(round(max(t.width for t in tiles) * k))
    block_h = int(round(sum(t.height for t in tiles) * k)) \
        + (len(tiles) - 1) * gap

    if center_w:
        x = (center_w - col_w) // 2
    ty = y + max(0, (avail_h - block_h) // 2)
    radius = max(2, int(round(col_w * TILE_RADIUS_DP / TILE_WIDTH_DP)))
    for t in tiles:
        tile = t.resize((col_w, max(1, int(round(t.height * k)))),
                        Image.LANCZOS)
        card, dp, dpy = _card_shadow(_round_tile(tile, col_w), radius)
        bg.alpha_composite(card, (x - dp, ty - dpy))
        ty += tile.height + gap
    return col_w


def compose_modes(tiles, headline: str, subline: str, badge: str):
    """9:16: die fuenf echten Modus-Kacheln als grosse Liste.

    v0.9.2, dritter Durchgang. Zwei vorherige Fassungen waren falsch:

      * Kompletter Screen im Geraet - alle fuenf Modi passten nur, wenn
        die Schrift auf 0.64 verkleinert wurde, also kleiner als in allen
        anderen Store-Bildern.
      * Losgeloste Kacheln in zwei Spalten und drei Reihen. Die Kacheln
        waren dabei nur 460 px breit (43 % der Bildbreite) und der
        Crop hatte ihnen die runden Ecken genommen. Dazu verteilte der
        Faktor die Reihen ueber die ganze Bildhoehe, sodass zwischen
        den Kacheln riesige leere Streifen standen.

    Jetzt: eine Spalte, fuenf Kacheln ueber die volle Bildbreite, so
    gross wie die Hoehe zulaesst. Das ist genau die Liste, die die App
    zeigt - und die Kacheln sind mit rund 830 px gut doppelt so breit
    wie vorher, mit gerundeten Ecken und ohne tote Flaechen.
    """
    W, H = 1080, 1920
    bg = gradient((W, H), 40).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    f_head = ImageFont.truetype(FONT_BOLD, 62)
    f_sub = ImageFont.truetype(FONT_REG, 30)
    y = 104
    y = draw_lines(draw, None, headline, f_head, (255, 255, 255, 255), 14,
                   W // 2, y)
    y += 20
    y = draw_lines(draw, None, subline, f_sub, (255, 255, 255, 226), 10,
                   W // 2, y)

    margin = 60
    gap = 28
    badge_top = H - 136
    _place_tiles(bg, tiles, y + 34, badge_top - y - 70, W - 2 * margin, gap,
                 center_w=W)

    badge_pill(bg, badge, W // 2, badge_top)
    return round_corners(bg, 56)


def compose_modes_wqhd(tiles, headline: str, subline: str, badge: str):
    """16:9: Kacheln links, Text rechts - wie compose_wqhd, aber mit
    Kacheln statt eines Geraets.

    Die Kacheln werden mit derselben Hoehenbegrenzung gesetzt wie im
    9:16-Bild. Vorher lag die Spaltenbreite fest bei 900 px, wodurch die
    hohe Transit-Spark-Kachel aus ihrer Zeile in die darunterliegende
    ragte.
    """
    W, H = 2560, 1440
    bg = gradient((W, H), 25).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    margin = 90
    gap = 26
    col_w = _place_tiles(bg, tiles, margin, H - 2 * margin, 980, gap,
                         x=margin)

    f_head = ImageFont.truetype(FONT_BOLD, 78)
    f_sub = ImageFont.truetype(FONT_REG, 38)
    tx = margin + col_w + 90
    y = max(200, (H - 400) // 2)
    y = draw_lines(draw, None, headline, f_head, (255, 255, 255, 255), 20,
                   tx, y, align='left')
    y += 24
    y = draw_lines(draw, None, subline, f_sub, (255, 255, 255, 226), 14,
                   tx, y, align='left')
    y += 40
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

    # --- App-Bild: direkt, ohne Mockup-Rahmen ---------------------------
    # v0.9.2: Das Geraet-Mockup ist entfallen. Es war ein Fremdkoerper:
    # Rand, Schatten, Punch-Hole-Kamera und System-UI sind Dinge, die der
    # Store ohnehin ergaenzt, und auf dem Mockup wirkte der echte Screen
    # wie eine eingepasste Miniatur. Jetzt steht der App-Screen selbst
    # gross und abgerundet da - die Flaeche gehoert dem Produkt.
    box_h = H - y - 150
    box_w = W - 150
    scr = app_tile(shot, box_h, box_w, corner_ratio=0.055)
    tw, th = scr.size
    px = (W - tw) // 2
    py = y + 34
    bg.alpha_composite(scr, (px, py))

    # --- Badge unter dem Bild --------------------------------------------
    by = min(py + th + 22, H - 100)
    badge_pill(bg, badge, W // 2, by)
    return round_corners(bg, 56)


def compose_wqhd(shot: Image.Image, headline: str, subline: str, badge: str):
    W, H = 2560, 1440
    bg = gradient((W, H), 25).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    # App-Bild links, ohne Mockup. Hoehe so skalieren, dass es mit Rand
    # sicher passt; Breite ist bewusst gedeckelt, sonst waere der Screen
    # bei 20:9 sehr schmal und der Text bekame zu wenig Platz.
    margin = 60
    box_h, box_w = H - 2 * margin, 1020
    scr = app_tile(shot, box_h, box_w, corner_ratio=0.045)
    tw, th = scr.size
    px = 130
    py = (H - th) // 2
    bg.alpha_composite(scr, (px, py))

    # Text rechts vom Bild, linksbuendig (breite Headlines wuerden sonst
    # ueber den Bildrand hinausragen).
    f_head = ImageFont.truetype(FONT_BOLD, 78)
    f_sub = ImageFont.truetype(FONT_REG, 38)
    tx = px + tw + 90
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
        if name == '03_entdecken' and TILES.exists():
            # Sonderfall: nicht der Screen, sondern die einzelnen
            # Modus-Kacheln (siehe compose_modes).
            tiles = sorted(TILES.glob('tile_*.png'),
                           key=lambda p: int(p.stem.split('_')[1]))
            if tiles:
                a = compose_modes([_crop_tile(Image.open(t)) for t in tiles],
                                  headline, subline, badge)
                b = compose_modes_wqhd(
                    [_crop_tile(Image.open(t)) for t in tiles],
                    headline, subline, badge)
                for d, im in ((OUT_9x16, a), (OUT_WQHD, b),
                              (OUT_FASTLANE, a)):
                    save_png(im, d / f'{name}.png')
                print(f'  {name}: 9x16 {a.size} + wqhd {b.size} '
                      f'({len(tiles)} Kacheln)')
                continue
            print('  03_entdecken: keine Kacheln gefunden, Fallback auf '
                  'den Screen')
        shot = Image.open(src)
        a = compose_9x16(shot, headline, subline, badge)
        b = compose_wqhd(shot, headline, subline, badge)
        for d, im in ((OUT_9x16, a), (OUT_WQHD, b), (OUT_FASTLANE, a)):
            save_png(im, d / f'{name}.png')
        print(f'  {name}: 9x16 {a.size} + wqhd {b.size}')

    print('Fertig.')


if __name__ == '__main__':
    main()
