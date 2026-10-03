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

import json
import math
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
        # Vorher: "Mit E-Mail bestätigen, Profil ausfüllen,
        # Geburtsdatum hinterlegen, los."
        #
        # Das passte nicht mehr zum Bild. Die Kachel zeigt nur
        # E-Mail-Feld, Passwort-Feld, Kontrollkästchen und
        # "Einloggen" - dort steht kein Geburtsdatum, und der Satz
        # versprach einen Schritt, den man auf dem Bild nicht findet.
        # Aufgetrennt in einen Teil, den das Bild zeigt, und einen,
        # der danach kommt.
        'Anmelden mit E-Mail und Passwort.\n'
        'Profilangaben gibst du später.',
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

# Anzeigewerte der nachgeahmten Systemleiste. Beides sind bewusste
# Festlegungen des Nutzers, keine Messung:
#   * 100 % statt des in der Referenz stehenden 70 - ein halbvoller
#     Akku sieht auf einem Screenshot nach Sorge aus.
#   * eine gerade Uhrzeit. Aus demselben Grund: 3:41 ist eine
#     Zufallszeit und wirkt wie ein Screenshot vom falschen Moment.
BATTERY_PERCENT = '100'
CLOCK_TEXT = '12:00'

# Randstaerke des Akkukoerpers, als Anteil seiner Hoehe.
#
# Das ist eine RENDERENTSCHEIDUNG und keine Messung: der Akku ist auf
# 474 px ein gefuellter Fleck von 14 px Hoehe ohne leere Mitte, die
# Innenkante des Rahmens ist im Foto nicht sichtbar. Ein Versuch, sie
# zu messen, lieferte konsequent die volle Koerperbreite statt einer
# Randstaerke. Der Wert folgt der Rueckmeldung "die Raender duerfen
# minimal dicker"; vorher stand hier 0,085.
BATTERY_STROKE_RATIO = 0.13
# Vorheriger Wert des Akkurandes. Die Differenz ist der Zuwachs, um den
# die RENDERUNG insgesamt vergroessert wurde. Die Uhr benutzt exakt
# denselben Zuwachs (Nutzerwunsch: "so viel dicker, wie der Akku
# dicker geworden ist"), damit beide nicht auseinanderlaufen.
BATTERY_STROKE_RATIO_PREV = 0.085
BATTERY_STROKE_GROWTH = BATTERY_STROKE_RATIO - BATTERY_STROKE_RATIO_PREV

# ZWEI VARIANTEN, bewusst nebeneinander (Nutzerwunsch):
#
#   1. MIT nachgeahmter Systemleiste. Die Icons werden aus einem Foto
#      des Geraetes extrahiert (make_statusbar_assets.py).
#   2. OHNE Systemleiste. Keine nachgeahmten Symbole - der Store legt
#      seine eigene Statusleiste ohnehin ueber das Bild.
#
# Welche besser aussieht, ist eine Sache des Auges und nicht messbar.
# Deshalb werden beide erzeugt und getrennt abgelegt, statt im
# Quelltext umgeschaltet zu werden - dann ist der Vergleich moeglich,
# ohne dass man weiss, welcher Lauf gerade der aktuelle ist.
OMIT_SYSTEM_UI = False
OUT_9x16_OHNE = OUT_9x16.with_name('9x16-ohne-systemleiste')
OUT_WQHD_OHNE = OUT_WQHD.with_name('wqhd-ohne-systemleiste')

# DRITTE Variante: Kacheln ohne Geraet und ohne Statusleiste.
#
# Der Unterschied zu "ohne-systemleiste" ist nicht die Statusleiste,
# sondern die Komposition: dort steht der App-Screen weiterhin in
# einem abgerundeten Geraetefeld, hier liegt er als einzelne Kachel
# direkt auf dem Markenverlauf - genau wie die fuenf Moduskacheln in
# 03_entdecken. Die vier uebrigen Screens sind so gebaut, dass alle
# fuenf Bilder dieselbe Sprache sprechen.
#
# Die bisherigen zwei Varianten bleiben unberuehrt; es come adds. Der
# Store-Upload bleibt eine Entscheidung des Nutzers, deshalb wird
# hier nichts nach fastlane kopiert.
OUT_9x16_KACHELN = OUT_9x16.with_name('9x16-kacheln')
OUT_WQHD_KACHELN = OUT_WQHD.with_name('wqhd-kacheln')


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

    text = CLOCK_TEXT
    width_f = 0.0549
    left_f = 0.0717
    height_f = 0.0211
    geom = {}
    if STATUSBAR_GEOMETRY.is_file():
        try:
            geom = json.loads(STATUSBAR_GEOMETRY.read_text(
                encoding='utf-8-sig'))
            clock_geom = geom.get('clock') or {}
            text = CLOCK_TEXT
            width_f = float(clock_geom.get('widthFraction', width_f))
            left_f = float(clock_geom.get('leftFraction', left_f))
            height_f = float(clock_geom.get('heightFraction', height_f))
        except (OSError, ValueError):
            geom = {}

        # Akkukoerperhoehe, fuer die Strichstaerke der Uhr weiter unten.
    body_h = float((geom.get('battery') or {}).get(
        'bodyHeightFraction', 0.0295)) * u

    # MINDESTENS so gross wie die uebrigen Symbole (Nutzerwunsch).
    #
    # Gemessen ist die Uhr mit 2,11 % der Bildbreite, die uebrigen
    # Symbole sind 2,74 % (WLAN, Mobilfunk) bis 2,95 % (Akku). Die Uhr
    # war das kleinste Element der Leiste und wirkte als zweiter
    # Grafikstil.
    #
    # Fuehrendes Mass ist die HOEHE, nicht die Breite. Ein erster
    # Versuch skalierte die Breite mit - damit wurde die Uhr 43 px
    # breit, aber nur 15 px hoch, waehrend die Symbole 16 bis 20 px
    # messen. Grund: die Hoehe folgt nicht aus der Breite, sondern aus
    # der Schrift, und der Ziffern-Doppelpunkt hat ein anderes
    # Verhaeltnis als die Ziffern. Es gibt bei einer Schrift also nur
    # EINE frei waehlbare Groesse - wenn die Breite das Ziel
    # vorgibt, ist die Hoehe eine Folge und nicht ein Wunsch.
    #
    # Die gemessene Uhrbreite (5,49 %) ist damit ueberholt. Sie ist
    # das Mass aus dem Foto, in dem die Uhr sichtbar KLEINER war als
    # die Symbole - genau das wird hier geaendert. Neu gemessen wird
    # nichts; neu entschieden wird, welche Groesse gilt.
    sym_h = max(
        float((geom.get('battery') or {}).get('bodyHeightFraction', 0.0295)),
        float((geom.get('wifi') or {}).get('relHeight', 0.0274)),
        max((float(b['dyTopFraction']) + float(b['hFraction'])
             for b in ((geom.get('signal') or {}).get('bars') or [])),
            default=0.0),
    )
        # Nie kleiner als das Foto, falls die Geometrie fehlt.
    target_h = max(sym_h, height_f) * u

    # STRICHSTAERKE der Uhr, aus dem Akku-Zuwachs abgeleitet. Die
    # Ziffern sind im Referenzfoto duenn, und duenner als die
    # Nachbar-Symbole wirkt die Uhr als zweiter Grafikstil. Sie soll
    # deshalb um genau so viel zunehmen wie der Akkurand:
    #
    #     Zuwachs = (0,13 - 0,085) * Akkukoerperhoehe
    #
    # Beide Werte kommen aus derselben Geometriedatei und sind in
    # derselben Einheit gerechnet (Anteil der Bildbreite). Die
    # Ziffernhoeh der Uhr und die Akkukoerperhoehe sind bewusst
    # verschiedene Bezugsgrossen - "so viel wie beim Akku" heisst
    # derselbe absolute Zuwachs, nicht dieselbe relative Zahl.
    stroke_px = max(1, int(round(BATTERY_STROKE_GROWTH * body_h)))

    # Schriftgroesse so lange nachziehen, bis die GERENDERTE Ziffernhoehe
    # das Ziel trifft. Der Strich waechst nach aussen und wird
    # mitgemessen, sonst waere die Uhr am Ende niedriger als geplant.
    #
    # Frueher wurde auf die Breite nachgezogen. Das ergab eine 43 px
    # breite, aber nur 15 px hohe Uhr neben 16 bis 20 px hohen Symbolen -
    # die Breite war dann das Ziel und die Hoehe bloss eine Folge davon.
    size = max(7, int(target_h / 0.72))
    f = None
    for _ in range(5):
        try:
            f = ImageFont.truetype(FONT_REG, size)
        except OSError:
            return False
        bb = d.textbbox((0, 0), text, font=f, stroke_width=stroke_px)
        got_h = bb[3] - bb[1]
        if got_h <= 0:
            return False
        if abs(got_h - target_h) <= 1:
            break
        size = max(7, int(size * target_h / got_h))
    if f is None:
        return False
    bb = d.textbbox((0, 0), text, font=f, stroke_width=stroke_px)
    # Vertikale Mitte auf cy. PIL liefert die Textbox mit negativem
    # oberem Rand bei Glyphen, die ueber die Grundlinie ragen - deshalb
    # die Mitte aus beiden Kanten und nicht aus th allein.
    top = cy - (bb[1] + bb[3]) / 2
    d.text((left_f * u, top), text, font=f, fill=color,
           stroke_width=stroke_px, stroke_fill=color)
    return True


def _paste_status_bar_icons(img, cy, tint, draw):
    """Zeichnet die Symbole der nachgeahmten Statusleiste. True bei Erfolg.

    Der MASSSTAB ist der Quotient aus den Bildbreiten, nicht eine
    geratene Prozentangabe. Das ist der Unterschied zwischen "Aehnlich"
    und "skaliert": mit dem Quotienten gilt fuer jedes Zielbild dasselbe
    Verhaeltnis wie auf dem Geraet des Nutzers.

    ALLE drei Symbole werden gezeichnet, nicht eingeklebt. Das ist eine
    Aenderung aus einem konkreten Grund: als 13-px-Sprite in eine
    1080-px-Kachel hochskaliert bleibt das Ergebnis pixelig, egal wie
    sauber der Ausschnitt war. Gezeichnet wird mit den im Referenzfoto
    gemessenen Proportionen, darum ist die Form scharf und die Groesse
    trotzdem gemessen:

      * WLAN   zwei Boegen und ein Punkt, alle drei Abstaende gemessen
      * Signal vier getrennte Balken auf gemeinsamer Grundlinie
      * Akku   Koerper, Stift und Prozentzahl gemessen

    Stumm (Lautsprecher mit Schraegstrich) entfaellt. In 11 Pixeln
    Hoehe ist die Kontur nicht wiederzuerkennen; auf dem fertigen Bild
    las sie sich als Wecker. Ein Symbol wegzulassen ist ehrlicher, als
    eines hinzumalen, das nicht mehr das Original ist (Nutzerwunsch).

    Reihenfolge und Abstaende stehen als "cluster"/"gaps" in der
    Geometriedatei - von rechts nach links gezeichnet, damit die
    rechte Kante des Akkus am gemessenen rechten Rand sitzt.
    """
    import json
    if not STATUSBAR_SPRITE.is_file() or not STATUSBAR_GEOMETRY.is_file():
        return False
    try:
        geom = json.loads(STATUSBAR_GEOMETRY.read_text(encoding='utf-8'))
    except (OSError, ValueError, KeyError):
        return False

    cluster = geom.get('cluster') or []
    gaps = geom.get('gaps') or []
    if not cluster or len(gaps) != len(cluster) - 1:
        return False

    target = tuple(tint[:3])
    w, h = img.size
    u = float(w)

    right_margin = float(geom.get('rightMarginFraction', 0.06)) * u
    cursor = w - right_margin

    # Oberkante des Iconfelds. `cy` ist die Mitte des Statusleisten-
    # Bandes, die Messwerte in der Geometrie sind aber vom OBEREN Rand
    # des jeweiligen Iconfelds aus gemessen. Ohne diese Umrechnung
    # hing der ganze Cluster um halbe Symbolhoehe zu tief und stiess im
    # Screenshot an den Text darunter ("Ueberspringen").
    heights = []
    wifi_h = float(((geom.get('wifi') or {}).get('relHeight', 0)) * u)
    if wifi_h:
        heights.append(wifi_h)
    sig_bars = ((geom.get('signal') or {}).get('bars') or [])
    for bar in sig_bars:
        heights.append((float(bar['dyTopFraction'])
                        + float(bar['hFraction'])) * u)
    icon_top = cy - (max(heights) / 2.0 if heights else 0.0)

    for i in range(len(cluster) - 1, -1, -1):
        entry = cluster[i]
        name = entry['name']
        icon_w = float(entry['w']) * u

        if name == 'battery':
            _draw_reference_battery(draw, cursor, cy, target, geom, u)
        elif name == 'wifi':
            if not _draw_reference_wifi(draw, cursor, icon_top, target,
                                        geom, u):
                return False
        elif name == 'signal':
            if not _draw_reference_signal(draw, cursor, icon_top, target,
                                          geom, u):
                return False
        else:
            return False

        cursor -= icon_w
        if i > 0:
            cursor -= float(gaps[i - 1]) * u

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


def _draw_reference_battery(draw, right, cy, tint, geom, u):
    """Akku mit den aus der Referenz gemessenen Proportionen.

    Alle vier Werte kommen aus statusbar_geometry.json und wurden im
    Referenzfoto gemessen:

      Koerper 4,85 % der Bildbreite breit, 2,95 % hoch
      Stift   0,42 % breit, 1,48 % hoch

    Der Stift war vorher mit dem Icon-Abstand gezeichnet, also rund ein
    Drittel so breit wie der Koerper - das war das "komisch lange
    Ende". Er ist jetzt knapp ein Elftel des Koerpers und halb so hoch,
    genau wie im Original.
    """
    b = geom.get('battery') or {}
    body_w = float(b.get('bodyWidthFraction', 0.0485)) * u
    body_h = float(b.get('bodyHeightFraction', 0.0295)) * u
    nub_w = float(b.get('nubWidthFraction', 0.0042)) * u
    nub_h = float(b.get('nubHeightFraction', 0.0148)) * u

    # `right` ist die rechte Kante des ICONFELDS (inklusive Stift).
    x1 = right - nub_w
    x0 = x1 - body_w
    y0 = cy - body_h / 2
    stroke = max(1, int(round(BATTERY_STROKE_RATIO * body_h)))

    draw.rounded_rectangle(
        [x0, y0, x1, y0 + body_h],
        radius=body_h * 0.28, outline=tint,
        width=max(1, int(round(BATTERY_STROKE_RATIO * body_h))))
    if nub_w >= 1:
        draw.rounded_rectangle(
            [x1 + 1, cy - nub_h / 2, right, cy + nub_h / 2],
            radius=max(1, int(nub_h * 0.25)), fill=tint)

    # Prozentzahl. Sie ist der eigentliche Inhalt dieses Symbols - ohne
    # sie waere der Akku nur eine Form. Deshalb wird sie gezeichnet
    # statt der Silhouette aus dem Sprite genommen zu werden, wo sie
    # im gefuellten Rechteck verschwindet.
    try:
        f = ImageFont.truetype(FONT_BOLD, max(6, int(body_h * 0.60)))
        bb = draw.textbbox((0, 0), BATTERY_PERCENT, font=f)
        tw = bb[2] - bb[0]
        if tw <= body_w - 2 * stroke - 1:
            draw.text((x0 + (body_w - tw) / 2 - bb[0],
                       cy - (bb[1] + bb[3]) / 2),
                      BATTERY_PERCENT, font=f, fill=tint)
    except OSError:
        pass


def _draw_reference_signal(draw, right, top, tint, geom, u):
    """Signal aus vier gemessenen Balken. True bei Erfolg.

    Im Referenzfoto sind es vier getrennte Rechtecke auf einer
    gemeinsamen Grundlinie: x=386..388, 391..393, 395..398, 400..402,
    Oberkanten bei y=36, 34, 32, 29. Genau diese Rechtecke werden
    gezeichnet - als Vektor, nicht als 13-px-Bild.

    Das ist der Unterschied zu den drei vorherigen Versuchen: die
    Form ist nicht geraten, sondern abgelesen, und sie ist scharf, weil
    sie nicht aus Pixeln besteht. Die Grundlinie ist die Oberkante des
    Signal-Iconfelds, die Balken waechsen nach links oben.
    """
    # AUFSTEIGEND, gleiche Breiten, gleiche Abstaende.
    #
    # Aufsteigend ist die Orientierung der Referenz: x=386 ist der
    # kuerzeste Balken (Oberkante y=36), x=402 der hoechste (y=29).
    # Ein zwischenzeitlicher Versuch, die Balken zu SPIEGELN, beruhte
    # auf einem Missverstaendnis von "anders herum" und wurde
    # zurueckgenommen - die Referenz stimmt bereits.
    #
    # Die Abstaende im Foto sind ungleich: die Balken sind 3, 3, 4 und
    # 3 px breit, die Luecken dazwischen 2, 1 und 1 px. Auf 17 px
    # Gesamtbreite faellt das als unruhig auf. Deshalb werden Breite
    # und Abstand gemittelt und gleich verteilt; die Gesamtspannweite
    # bleibt die gemessene, die Hoehen bleiben gemessen.
    sig = sorted((geom.get('signal') or {}).get('bars') or [],
                 key=lambda b: float(b['dxFraction']))
    if not sig:
        return False

    icon_w = float(((geom.get('cluster') or [{}])[-2] or {}).get('w', 0.0)) * u
    bar_w = (sum(float(b['wFraction']) for b in sig) / len(sig)) * u
    gap = (icon_w - bar_w * len(sig)) / max(1, len(sig) - 1)
    if gap < 0:
        bar_w = icon_w / len(sig)
        gap = 0.0

    x0 = right - icon_w
    # Gemeinsame Grundlinie. Im Foto enden drei Balken bei y=41 und der
    # hoechste bei y=40 - eine Folge davon, dass die Tinte rechts einen
    # Pixel kuerzer ist. Uebernommen sah die Treppe schief aus, also
    # werden alle Balken auf die tiefste Unterkante gestellt.
    baseline = max(float(b['dyTopFraction']) + float(b['hFraction'])
                   for b in sig) * u
    for i, bar in enumerate(sig):
        bx0 = x0 + i * (bar_w + gap)
        # dyTopFraction ist icon-relativ gemessen: die Oberkante des
        # Iconfelds ist `top`, die Balken waechsen von dort nach unten.
        y1 = top + baseline
        y0 = y1 - float(bar['hFraction']) * u
        # Ecken minimal abrunden, damit die Balken nicht als Tabelle
        # aussehen - Android zeichnet sie mit einem kleinen Radius.
        r = min((y1 - y0) * 0.28, bar_w * 0.45)
        if r >= 0.5:
            draw.rounded_rectangle([bx0, y0, bx0 + bar_w, y1],
                                   radius=r, fill=tint)
        else:
            draw.rectangle([bx0, y0, bx0 + bar_w, y1], fill=tint)
    return True


def _draw_reference_wifi(draw, right, top, tint, geom, u):
    """WLAN als drei konzentrische Boegen, OHNE Punkt. True bei Erfolg.

    Drei Boegen, kein Punkt. Die Form ist ein Kreis, nicht eine
    Ellipse, und das laesst sich an den gemessenen Spalten nachweisen:

      Spalte x=364 (linker Rand)  Tinten y=31..33
      Spalte x=372 (Mitte)         Tinten y=29..41
      Spalte x=379 (rechter Rand)  Tinten y=32..33

    Ein Kreis um (372, 40) mit Radius 11 trifft alle drei: bei x=364
    ergibt er y = 40 - Wurzel(121-64) = 32,4 und damit genau die
    gemessenen 31..33 bei einer Strichstaerke von 2,5 px. Bei x=372
    ergibt er y = 29, ebenfalls der gemessene oberste Wert. Der
    Radius ist also die Strecke vom Punktmittelpunkt nach oben, nicht
    die halbe Iconbreite - der Fan ist hoeher als breit, seine Arme
    werden erst durch den Winkelbereich beschnitten.

    Daraus folgt der Winkelbereich: so geschnitten, dass der
    Aussenbogen genau die gemessene Iconbreite fuellt. Das ist zugleich
    die flachste moegliche Form - ein flacherer Bogen waere im
    gemessenen Kasten nicht unterzubringen, ohne die Breite zu
    verlassen oder die Oberkante zu verfehlen.

    Drei Boegen, nicht zwei: mit dem gemessenen Radius und der
    Strichstaerke aus der Referenz passen genau drei uebereinander, und
    "es fehlt ein Strich" war die Rueckmeldung dazu.

    Der innerste Bogen laeuft nach unten in einer Spitze aus - eine Art
    Dreieck, dessen Oberkante genau der Bogen bleibt. Ohne Punkt
    (Nutzerwunsch), aber nicht als leerer Raum: die Spitze fuellt den
    Platz, den der Punkt in der Referenz einnimmt.
    """
    w_geom = geom.get('wifi') or {}
    if 'relHeight' not in w_geom:
        return False

    # Achtung: `cluster[i]['w']` ist ein ANTEIL der Bildbreite, kein
    # Pixelwert. Ohne die Umrechnung mit u war der Radius 0,017 px und
    # damit kleiner als die Strichstaerke - alle Boegen wurden still
    # uebersprungen und nur der Punkt blieb uebrig, an falscher Stelle.
    icon_w = float(((geom.get('cluster') or [{}])[0] or {}).get('w', 0.0)) * u
    if icon_w <= 0:
        return False

    height = float(w_geom['relHeight']) * u
    # Die gemessene Strichstaerke (0,53 % der Bildbreite) sind rund 19 %
    # der Symbolhoehe. Auf 11 % zu deckeln war eine eigene Erfindung und
    # machte die Straeche zu duenn - zurueck auf den Messwert, nur bei
    # 20 % gedeckelt, damit ein blasser Messwert nicht ueberlaeuft.
    stroke = min(float(w_geom.get('relStroke', 0.004)) * u, height * 0.20)
    dot_r = float(w_geom.get('relDotRadius', 0.003)) * u
    dot_cx = right - icon_w + float(w_geom['relDotCentreX']) * u
    top = top + float(w_geom['relTop']) * u
    dot_cy = top + height - dot_r
    stroke_i = max(1, int(round(stroke)))

    # Radius des Aussenbogens: vom Punktmittelpunkt bis zur Oberkante.
    r_outer = height - dot_r
    half = icon_w / 2.0
    # Winkel so, dass der Aussenbogen die halbe Iconbreite genau
    # erreicht. PIL zaehlt Grad im Uhrzeigersinn ab 3 Uhr, die Oberseite
    # liegt bei 270.
    dev = math.degrees(math.acos(max(-1.0, min(1.0, half / r_outer))))
    start, end = 270.0 - dev, 270.0 + dev

    # Der Fan fuellt seinen Kasten von oben bis unten: Aussenbogen an
    # die Oberkante, Spitze an die Unterkante.
    #
    # Vorher wurde die Mitte des Fanbands mittiert, weil die Boegen ohne
    # Punkt nur die oberen 3,5 px des Kastens belegten und darunter 9 px
    # leer blieben. Mit der Spitze ist das gemittelt nicht mehr noetig
    # und sogar schaedlich: der Bogen saehe dann oben angeklebt aus und
    # die Spitze haette nur 1,8 px Laenge - ein Punkt, kein Dreieck.
    # Die Oberkante des Aussenbogens liegt auf stroke/2, damit der
    # Strich nicht ueber den Kasten hinausragt.
    apex_y = top + stroke / 2.0
    arc_cy = apex_y + r_outer

    # Die Boegen als Strich, der INNERSTE mit einer Spitze nach unten
    # (Nutzerwunsch): der unterste kleine Halbkreis laeuft nicht als
    # Bogen aus, sondern er endet in einer Spitze - eine Art Dreieck,
    # dessen Oberkante genau dieser Bogen bleibt.
    #
    # Dazu wird der innerste Bogen als geschlossene Form gezeichnet:
    # Bogenpunkte von `start` bis `end`, dann eine Spitze. Die beiden
    # aeusseren bleiben normale Boegen. Die Spitze reicht bis zur
    # Unterkante des Iconfelds - an ihre Stelle fiel sonst die Flaeche,
    # die vorher der Punkt einnahm (siehe _draw_reference_wifi).
    step = stroke * 1.5
    radii = []
    r = r_outer
    while r > stroke_i:
        radii.append(r)
        r -= step

    for r_mid in radii[:-1]:
        draw.arc([dot_cx - r_mid, arc_cy - r_mid,
                  dot_cx + r_mid, arc_cy + r_mid],
                 start=start, end=end, fill=tint, width=stroke_i)

    if radii:
        r_in = radii[-1]
        spike_tip = top + height
        pts = []
        steps = 24
        for i in range(steps + 1):
            ang = math.radians(start + (end - start) * i / steps)
            pts.append((dot_cx + r_in * math.cos(ang),
                        arc_cy + r_in * math.sin(ang)))
        pts.append((dot_cx, spike_tip))
        draw.polygon(pts, fill=tint)
        # Der Bogen darueber noch einmal als Strich, damit die
        # Oberkante der Form dieselbe Staerke hat wie die beiden
        # aeusseren Boegen und nicht als Fuellungskante abschneidet.
        draw.arc([dot_cx - r_in, arc_cy - r_in,
                  dot_cx + r_in, arc_cy + r_in],
                 start=start, end=end, fill=tint, width=stroke_i)
    return True


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

    devs = []
    src = tile.load()
    for yy in range(hpx):
        for xx in range(wpx):
            r, g, b, _a = src[xx, yy]
            devs.append(abs(r - br) + abs(g - bg_) + abs(b - bb))
    if not devs:
        return Image.new('L', tile.size, 0)

    # Weiche Maske, KEINE Binarisierung.
    #
    # Zwei Fehler, beide an derselben Stelle:
    #   * Feste Schwelle 45: die Symbole wurden zu dick. An den Raendern
    #     eines 11-px-Symbols liegen viele Anti-Aliasing-Pixel knapp
    #     ueber der Schwelle und verbreitern den Strich beim Binarisieren
    #     um ein Pixel je Seite.
    #   * Relative Schwelle (62 % vom Maximum): zu duenn. Das Maximum
    #     stammt aus Ausreissern, der echte Strich liegt weit darunter
    #     und wird weggeschnitten - uebrig blieben drei Punkte.
    #
    # Die Weichheit ist die ehrliche Uebernahme: die Deckkraft ist die
    # Abweichung vom Hintergrund, normalisiert. Die Strichstaerke ist
    # damit genau die des Originals, unabhaengig davon, wie stark
    # verkleitert die Vorlage ist.
    top = max(devs)
    span = max(1.0, top * 0.75)
    mask = Image.new('L', tile.size, 0)
    mp = mask.load()
    i = 0
    for yy in range(hpx):
        for xx in range(wpx):
            d = devs[i]
            if d < 8:
                mp[xx, yy] = 0
            else:
                mp[xx, yy] = min(255, int(d * 255 / span))
            i += 1

    # Weichzeichnen entfernt vereinzelte Ausreisser, ohne die
    # Strichstaerke zu veraendern (im Gegensatz zu einer Erosion).
    return mask.filter(ImageFilter.GaussianBlur(0.6))


def _draw_status_bar(img: Image.Image, clock=CLOCK_TEXT, percent=BATTERY_PERCENT):
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
    if not OMIT_SYSTEM_UI:
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
    if not OMIT_SYSTEM_UI:
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
               pad_y=17, align='center'):
    """Transparentes Abzeichen-Pill MIT Text (alpha-korrekt geblendet).

    Wichtig: ImageDraw auf einem RGBA-Bild ERSETZT die Pixel inkl. Alpha -
    ein fill=(255,255,255,46) wuerde thus deckend weiss. Deshalb wird die
    Form auf einer eigenen Ebene gezeichnet und per alpha_composite
    darueber gelegt.

    `align` ist 'center' (Pill um cx herum) oder 'left' (Pill beginnt bei
    cx, Text linksbuendig darunter). Der 16:9-Bildaufbau hat eine
    Textspalte und braucht die linke Variante; vorher wurde die Pille
    dort mitten in der Spalte gesetzt und stand quer.
    """
    layer = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(font_path, size)
    bb = d.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    w, h = tw + 2 * pad_x, th + 2 * pad_y
    x0 = int(cx - w / 2) if align == 'center' else int(cx)
    y0 = int(top)
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=h // 2,
                        fill=(255, 255, 255, 52),
                        outline=(255, 255, 255, 130), width=2)
    tx = cx - tw / 2 if align == 'center' else x0 + pad_x
    d.text((tx - bb[0], y0 + pad_y - bb[1]), text, font=font,
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


# System-Insets im App-Export: 24 dp Statusleiste oben, 24 dp
# Gesture-Navigation unten, gerendert mit dpr 3. Das sind die Werte aus
# test/screenshots/support/store_screenshot_insets.dart.
#
# SICHERHEITSHALBER NICHT einfach 72 px abgeschnitten. Gemessen beginnt
# der Inhalt bei 01_willkommen exakt auf y=72, bei 04_anpassen und
# 05_eisbrecher aber auf y=62 - die Bildschirme mit AppBar verbrauchen
# das Inset anders. Ein fester Schnitt von 72 px hat dort 10 px aus der
# AppBar geschnitten, der Titel "Erscheinungsbild" stand abgeschnitten
# im Bild. Deshalb wird die Kante gemessen, soweit sie messbar ist.
STORE_INSET_DP = 24.0
EXPORT_DPR = 3.0
# Sicherheitsabstand zur gemessenen Kante. Ohne ihn faellt die Karte mit
# der Flanke an den Inhalt.
CONTENT_MARGIN_PX = 8

# Mindestzahl abweichender Stichproben, damit eine Zeile als Inhalt
# gilt. ABSOLUT, nicht als Anteil: bei 120 Stichproben waere ein Anteil
# von 2 % "mindestens 3". Genau daran ist "Ueberspringen" auf
# 01_willkommen verloren gegangen - die Schrift ist duenn, ihre oberste
# Zeile trifft nur EINE Stichprobe, die zweite nur zwei. Mit "3" kam der
# Schnitt bei y=80 und der Text begann bei y=66: die Haelfte der
# Buchstaben stand abgeschnitten im Bild. Mit 2 kommt der Schnitt auf
# y=64 und der Text bleibt heil.
CONTENT_MIN_SAMPLES = 2


def _content_edge(shot: Image.Image, top=True) -> int:
    """Erste Inhaltszeile von oben bzw. letzte von unten.

    Gesucht wird nicht nach einer Farbe, sondern nach einer
    ABWEICHUNG von der Hintergrundfarbe der Zeile. Scaffold-
    Hintergrund und Statusleisten-Inset sind dieselbe Farbe - es gibt
    keine Kante, die man abgreifen koennte. Sichtbar wird nur, was
    wirklich gezeichnet ist.

    Nach dem ersten Fund wird bewusst ein Stueck WEITER geschnitten als
    gemessen: lieber ein schmaler leerer Rand am Kartenanfang als ein
    abgeschnittener Titel.
    """
    rgb = shot.convert('RGB')
    w, h = rgb.size
    px = rgb.load()
    step = max(1, w // 120)
    cols = range(0, w, step)

    # Hintergrund aus dem oberen Rand: das erste stabile Band ist der
    # Scaffold. Gesucht wird nach einer ABWEICHUNG von diesem Wert.
    bg = None
    for y in range(0, min(h, 200)):
        r = sum(px[x, y][0] for x in cols) / len(list(cols))
        g = sum(px[x, y][1] for x in cols) / len(list(cols))
        b = sum(px[x, y][2] for x in cols) / len(list(cols))
        if bg is None:
            bg = (r, g, b)
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 24:
            break
        bg = (r, g, b)

    hits = []
    n_cols = len(list(cols))
    for y in range(h):
        n = 0
        for x in cols:
            rr, gg, bb = px[x, y]
            if abs(rr - bg[0]) + abs(gg - bg[1]) + abs(bb - bg[2]) > 36:
                n += 1
        if n >= CONTENT_MIN_SAMPLES:
            hits.append(y)
    if not hits:
        px_inset = int(round(STORE_INSET_DP * EXPORT_DPR))
        return px_inset if top else h - px_inset
    if top:
        return max(0, min(hits[0] - CONTENT_MARGIN_PX, h // 2))
    return max(h // 2, min(hits[-1] + CONTENT_MARGIN_PX, h))


def _crop_store_insets(shot: Image.Image) -> Image.Image:
    """Schneidet die leeren System-Insets aus dem App-Export heraus.

    Der Export enthaelt oben und unten die reservierten Insets
    (SafeArea), in denen nichts gezeichnet wird. Fuer die Kachel-
    Komposition ohne Statusleiste sind sie genau das, was weg soll:
    ein leerer Streifen oben und einer unten.

    Die Kanten werden gemessen, nicht fest angesetzt - siehe
    _content_edge. Feste 72 px schnitten Screens mit AppBar in den
    Titel.
    """
    rgb = shot.convert('RGB')
    return rgb.crop((0, _content_edge(rgb, top=True),
                     rgb.size[0], _content_edge(rgb, top=False)))


def _place_card(bg, card, y, avail_h, max_w, center_w=0, x=None):
    """Eine Inhaltskachel in das Restfeld setzen.

    `x` setzt die linke Kante fest (16:9 nutzt das fuer die Kartenspalte
    neben dem Text). `center_w` mittelt die Kachel in dieser Breite -
    im 9:16-Bild ist die Mitte die einzige sinnvolle Wahl.

    Ohne beide Angaben wird die Kachel zentriert im Gesamtbild gesetzt.

    Rueckgabe: die tatsaechliche Kantenbreite, damit der Aufrufer den
    Textblock daneben setzen kann.
    """
    k = min(max_w / card.width, avail_h / card.height)
    cw = max(1, int(round(card.width * k)))
    ch = max(1, int(round(card.height * k)))
    card = card.resize((cw, ch), Image.LANCZOS)
    # Radius wie in der App: die Kachel ist der App-Screen, dessen
    # Ecken im Geratebild mit 42 dp gerundet werden.
    radius = max(2, int(round(cw * 0.042 / 0.9)))
    layer, dp, dpy = _card_shadow(round_corners(card, radius), radius)
    if x is None:
        cx = center_w if center_w else bg.size[0]
        x = (cx - cw) // 2
    ty = y + max(0, (avail_h - ch) // 2)
    bg.alpha_composite(layer, (x - dp, ty - dpy))
    return cw


def compose_card(shot: Image.Image, headline: str, subline: str, badge: str):
    """9:16: EIN Inhaltsblock als Kachel auf dem Markenverlauf.

    Das Gegenstueck zu compose_9x16 fuer die Variante OHNE Geraet und
    OHNE Statusleiste: glecher Verlauf, gleiche Kopfzeile, gleiche
    Badge-Pille - aber der Inhalt liegt als einzelne Kachel auf dem
    Verlauf, genau wie die fuenf Moduskacheln in compose_modes.

    Der Block ist der echte App-Screen, an den Insets beschnitten und
    heruntergerechnet. Er wird NICHT nachgebaut: ein nachgebautes Layout
    driftet von der App, das war beim SegmentedButton-Fall die Ursache
    fuer ein falsches Bild.
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
    card = _crop_store_insets(shot.convert('RGB'))
    _place_card(bg, card, y + 34, badge_top - y - 70, W - 2 * margin,
                center_w=W)

    badge_pill(bg, badge, W // 2, badge_top)
    return round_corners(bg, 56)


def compose_card_wqhd(shot: Image.Image, headline: str, subline: str,
                      badge: str):
    """16:9: Kachel links, Text rechts - wie compose_modes_wqhd, aber mit
    einem Inhaltsblock statt der fuenf Moduskacheln."""
    W, H = 2560, 1440
    bg = gradient((W, H), 25).convert('RGBA')
    draw = ImageDraw.Draw(bg)

    margin = 90
    col_w = _place_card(bg, _crop_store_insets(shot.convert('RGB')), margin,
                        H - 2 * margin, 980, x=margin)

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
    badge_pill(bg, badge, tx, y, size=36, align='left')
    return round_corners(bg, 56)


CARDS = ROOT / 'test' / 'screenshots' / 'store_v091' / 'cards'
# Der Screenshot-Export laeuft mit dpr 3. Die Rechtecke in den
# rects_*.json sind LOGISCH, die PNGs sind physisch - ohne diesen
# Faktor wuerde jedes Rechteck um den Faktor 3 daneben liegen.
CARDS_DPR = 3.0

# Innenabstand um die Kacheln herum, in LOGISCHEN Pixeln. Siehe
# load_cards: das vermessene Rechteck klebt am Widget und verliert
# dadurch den Innenabstand, den der Screen selbst rundherum setzt.
CARD_MARGIN_LOGICAL = 30.0


def _load_card_rects(screen):
    """Liest die Kachelrechtecke eines Screens.

    Zwei Formen werden akzeptiert, weil beide im Export vorkommen:

      * {"name": [l, t, w, h]}          - ein Rechteck pro Kachel
      * {"name": {"file": ..., "rect": [l, t, w, h]}}  - mit Screenshot

    Die zweite Form ist noetig fuer 05: die Eisbrecher-Kategorien
    stehen in einer Liste, die gescrollt werden muss. Eine Kachel kann
    nur aus dem Bild geschnitten werden, in dem sie vollstaendig stand.
    """
    path = CARDS / f'rects_{screen}.json'
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return []
    out = []
    for name, value in data.items():
        if isinstance(value, dict):
            rect, src = value.get('rect'), value.get('file')
        else:
            rect, src = value, None
        if not rect or len(rect) != 4:
            continue
        out.append((name, src, [float(v) for v in rect]))
    return out


def load_cards(screen, default_src=None, margin=0.0):
    """Schneidet die Kacheln eines Screens aus den exportierten Bildern.

    `default_src` gilt fuer Rechtecke OHNE eigenen Dateiverweis: bei 01
    und 02 gibt es nur einen Screenshot, aus dem alle Kacheln kommen.
    Ohne Vorgabe wurden diese Kacheln stillschweigend verworfen und der
    Screen als eine grosse Kachel eingesetzt - also genau die Loesung,
    die abgeschafft werden sollte.

    `margin` vergroessert das Rechteck in LOGISCHEN Pixeln. Notwendig,
    weil das Rechteck am Widget klebt: im Screen steckt um das Widget
    herum noch dessen eigener Innenabstand (32 dp beim Willkommens-Logo,
    20 dp im Karten-Host), und der faellt beim Zuschneiden weg. Die
    Kachel bekam dadurch weisse Tinte bis an den Rand - "der weisse Rand
    um den Inhalt ist zu klein".
    """
    out = []
    cache = {}
    for name, src, rect in _load_card_rects(screen):
        src = src or default_src
        if not src:
            continue
        img_path = CARDS / src
        if img_path not in cache:
            if not img_path.is_file():
                continue
            cache[img_path] = Image.open(img_path).convert('RGB')
        img = cache[img_path]
        l, t, w, h = rect
        l, t = l - margin, t - margin
        w, h = w + 2 * margin, h + 2 * margin
        box = (int(round(l * CARDS_DPR)), int(round(t * CARDS_DPR)),
               int(round((l + w) * CARDS_DPR)),
               int(round((t + h) * CARDS_DPR)))
        box = (max(0, box[0]), max(0, box[1]),
               min(img.size[0], box[2]), min(img.size[1], box[3]))
        if box[2] <= box[0] or box[3] <= box[1]:
            continue
        out.append((name, img.crop(box)))
    return out


def _heading_card(text, width, sub=None):
    """Ueberschriftskachel im Stil der uebrigen Kacheln.

    Fuer 05: die Kategorien sollen unter einer Kachel mit dem
    Seitentitel stehen, sonst ist die Liste ohne Ueberschrift. Der Text
    kommt aus den Strings der App (`spice.title`), nicht aus dem
    Marketing-Headline - der Screen hiess in der App "Eisbrecher-Fragen".
    """
    f = ImageFont.truetype(FONT_BOLD, max(14, int(width * 0.062)))
    layer = Image.new('RGBA', (width, 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    pad = int(width * 0.06)
    h = th + 2 * pad
    out = Image.new('RGBA', (width, h), (255, 255, 255, 255))
    od = ImageDraw.Draw(out)
    od.rounded_rectangle([0, 0, width - 1, h - 1], radius=h // 3,
                         fill=(255, 255, 255, 255))
    od.text(((width - tw) / 2 - bb[0], pad - bb[1]), text, font=f,
            fill=(45, 38, 50, 255))
    del layer
    return out


def _paste_card(bg, card, x, y):
    """Kachel mit Rundung und Schatten an eine feste Stelle setzen."""
    cw, ch = card.size
    radius = max(6, int(round(cw * 0.07)))
    layer, dp, dpy = _card_shadow(round_corners(card.convert('RGBA'), radius),
                                 radius)
    bg.alpha_composite(layer, (int(x) - dp, int(y) - dpy))
    return cw, ch


def _grid_metrics(cards, avail_h, max_w, cols=2, gap=24, min_gap=18):
    """Rechnet Spaltenbreite, Skalierung und Abstaende aus, ohne zu zeichnen.

    Getrennt von [_place_grid], weil der Aufrufer die Blockhoehe kennen
    muss, BEVOR er die Ueberschrift darueber setzt - und die Hoehe
    haengt von der Skalierung ab. Ein Aufruf zum Zeichnen als "Probe"
    wuerde die Kacheln zweimal in den Hintergrund schreiben.
    """
    if not cards:
        return {'k': 1.0, 'col_w': max_w, 'row_h': 0, 'v_gap': gap,
                'block_h': 0, 'rows': 0}
    n = len(cards)
    rows = (n + cols - 1) // cols
    col_w = (max_w - (cols - 1) * gap) / float(cols)
    widest = max(c.width for c in cards)
    tallest = max(c.height for c in cards)
    # Nur die Breite begrenzt; die Hoehe greift nur, wenn sie wirklich
    # nicht passt. Sonst wuerde ein einziger zu hoher Rest die Kacheln
    # kleiner machen, obwohl sie waagerecht Platz haetten.
    k = min(col_w / widest,
            avail_h / float(rows * tallest + (rows - 1) * min_gap))
    row_h = tallest * k

    # Der uebrige Raum wird auf die Zeilenabstaende verteilt, aber nur
    # begrenzt. Unbegrenzt verteilt lagen zwischen den fuenf Zeilen
    # riesige Leerraeume - die Gruppen zerfielen optisch in fuenf
    # einzelne Reihen statt als eine Liste zu lesen ("nicht so viel
    # Platz zwischen den Gruppen"). 1,5x der Grundabstand ist der
    # Kompromiss: etwas Luft, aber eine erkennbare Liste.
    v_gap = gap
    if rows > 1:
        spread = (avail_h - rows * row_h) / (rows - 1)
        v_gap = max(gap, min(spread, gap * 1.5))
    return {'k': k, 'col_w': col_w, 'row_h': row_h, 'v_gap': v_gap,
            'block_h': rows * row_h + (rows - 1) * v_gap, 'rows': rows}


def _place_grid(bg, cards, y, avail_h, max_w, cols=2, gap=24, min_gap=18,
                center_w=0):
    """Kacheln in `cols` Spalten setzen. Rueckgabe: Blockhoehe.

    Anders als [_place_tiles] wird die Kachelgroesse zuerst von der
    BREITE bestimmt und der uebrige Raum anschliessend (begrenzt) als
    Zeilenabstand verteilt. [_place_tiles] verteilt einen gemeinsamen
    Faktor ueber alle Kacheln und laesst danach den Rest ungenutzt - bei
    zehn flachen Kacheln (Eisbrecher-Kategorien, 72 dp hoch) schrumpfte
    dadurch jede auf ein paar Pixel Hoehe und die Beschriftung war nicht
    mehr lesbar.

    Zwei Spalten statt einer: eine Spalte mit zehn Kacheln braucht
    fuenfzehn Zeilen, zwei Spalten nur sechs.
    """
    if not cards:
        return 0
    m = _grid_metrics(cards, avail_h, max_w, cols, gap, min_gap)
    k, col_w, row_h, v_gap = m['k'], m['col_w'], m['row_h'], m['v_gap']

    # Mittig ueber die GESAMTE Rasterbreite, nicht ueber eine Spalte:
    # zwei Spalten a 466 px plus 28 px Abstand sind 960 px breit und
    # muessen bei 1080 px Bildbreite bei x=60 beginnen. Ueber die
    # Spaltenbreite mitteln liess die zweite Spalte bei x=801 beginnen
    # und damit 187 px aus dem Bild ragen.
    grid_w = cols * col_w + (cols - 1) * gap
    cx = (center_w - grid_w) / 2.0 if center_w else 0.0

    for i, card in enumerate(cards):
        r, c = divmod(i, cols)
        if c >= cols:
            break
        x = cx + c * (col_w + gap)
        cw = max(1, int(round(card.width * k)))
        ch = max(1, int(round(card.height * k)))
        img = card.resize((cw, ch), Image.LANCZOS)
        ty = y + r * (row_h + v_gap)
        _paste_card(bg, img, x + (col_w - cw) / 2.0, ty)
    return m['block_h']


def compose_cards(cards, headline: str, subline: str, badge: str,
                  heading=None, cols=1):
    """9:16: beliebig viele echte Kacheln untereinander auf dem Verlauf.

    Der Aufbau ist der von compose_modes, nur mit den Kacheln, die der
    Dart-Export aus den echten Widgets des Screens geschnitten hat -
    nicht mit dem Screen selbst. "Ueberspringen", die AppBar und der
    grosse Herz-Kopf des Anmeldescreens gehoeren nicht dazu, und
    deshalb sind sie auch nicht dabei.
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
    top = y + 34
    avail_h = badge_top - y - 70

    imgs = [c for _n, c in cards]
    head_h = 0
    head = None
    if heading:
        width = max((c.width for c in imgs), default=W - 2 * margin)
        head = _heading_card(heading, W - 2 * margin)
        head_h = int(head.height * (W - 2 * margin) / width)
        head = head.resize((W - 2 * margin, head_h), Image.LANCZOS)

    if cols > 1:
        # Ueberschrift und Raster als EINEN Block mittig setzen. Nur das
        # Raster zu mitteln liess die Ueberschrift oben kleben und ein
        # Loch darunter.
        #
        # Die Rasterhoehe haengt von der Skalierung ab und die Skalierung
        # vom verfuegbaren Raum - vorher mitteln waere zirkulaer. Deshalb
        # wird die Hoehe einmal vorab berechnet (reines Rechnen, ohne zu
        # zeichnen) und der Block danach einmal verschoben.
        probe = _grid_metrics(imgs, avail_h, W - 2 * margin, cols, gap, 18)
        block = head_h + (gap if heading else 0) + probe['block_h']
        start = top + max(0, (avail_h - block) / 2.0)
        if head is not None:
            _paste_card(bg, head, margin, start)
        _place_grid(bg, imgs, start + head_h + (gap if heading else 0),
                    avail_h, W - 2 * margin, cols=cols, gap=gap, min_gap=18,
                    center_w=W)
    else:
        if head is not None:
            _paste_card(bg, head, margin, top)
            top += head_h + gap
        _place_tiles(bg, imgs, top, avail_h, W - 2 * margin, gap, center_w=W)

    badge_pill(bg, badge, W // 2, badge_top)
    return round_corners(bg, 56)


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

    for d in (OUT_9x16, OUT_WQHD, OUT_FASTLANE,
              OUT_9x16_OHNE, OUT_WQHD_OHNE,
              OUT_9x16_KACHELN, OUT_WQHD_KACHELN):
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
                crops = [_crop_tile(Image.open(t)) for t in tiles]
                a = compose_modes(crops, headline, subline, badge)
                b = compose_modes_wqhd(crops, headline, subline, badge)
                for d, im in ((OUT_9x16, a), (OUT_WQHD, b),
                              (OUT_FASTLANE, a),
                              (OUT_9x16_OHNE, a), (OUT_WQHD_OHNE, b),
                              (OUT_9x16_KACHELN, a), (OUT_WQHD_KACHELN, b)):
                    save_png(im, d / f'{name}.png')
                print(f'  {name}: 9x16 {a.size} + wqhd {b.size} '
                      f'({len(tiles)} Kacheln, drei Varianten)')
                continue
            print('  03_entdecken: keine Kacheln gefunden, Fallback auf '
                  'den Screen')
        shot = Image.open(src)
        a = compose_9x16(shot, headline, subline, badge)
        b = compose_wqhd(shot, headline, subline, badge)

        # Variante MIT nachgeahmter Systemleiste.
        for d, im in ((OUT_9x16, a), (OUT_WQHD, b), (OUT_FASTLANE, a)):
            save_png(im, d / f'{name}.png')

        # Variante OHNE. Der Aufruf geht ueber das Modul-Flag, damit
        # beide Varianten garantiert denselben Weg nehmen - die App-
        # Screens werden nicht zweimal geladen.
        globals()['OMIT_SYSTEM_UI'] = True
        try:
            a2 = compose_9x16(shot, headline, subline, badge)
            b2 = compose_wqhd(shot, headline, subline, badge)
            save_png(a2, OUT_9x16_OHNE / f'{name}.png')
            save_png(b2, OUT_WQHD_OHNE / f'{name}.png')
        finally:
            globals()['OMIT_SYSTEM_UI'] = False

        # Variante KACHELN: die echten Widgets des Screens als einzelne
        # Kacheln auf dem Verlauf. 03 hat seine fuenf Moduskacheln, die
        # uebrigen Screens ihre eigenen - je nachdem, was der Dart-Export
        # als Rechtecke notiert hat. Ohne Export bleibt der Screen in
        # einem Kachelbild: dann ist es kein Fehler, nur weniger schoen.
        prefix = name[:2]
        cards = load_cards(prefix, default_src=f'{name}.png',
                       margin=CARD_MARGIN_LOGICAL if name in
                       ('01_willkommen', '04_anpassen') else 0.0)
        if cards:
            k = compose_cards(cards, headline, subline, badge,
                              heading='Eisbrecher-Fragen'
                              if name == '05_eisbrecher' else None,
                              cols=2 if name == '05_eisbrecher' else 1)
            save_png(k, OUT_9x16_KACHELN / f'{name}.png')
            kw = compose_card_wqhd(shot, headline, subline, badge)
            save_png(kw, OUT_WQHD_KACHELN / f'{name}.png')
            print(f'  {name}: 9x16 {a.size} + wqhd {b.size} '
                  f'(drei Varianten, {len(cards)} Kacheln aus echten '
                  'Widgets)')
            continue

        k = compose_card(shot, headline, subline, badge)
        kw = compose_card_wqhd(shot, headline, subline, badge)
        save_png(k, OUT_9x16_KACHELN / f'{name}.png')
        save_png(kw, OUT_WQHD_KACHELN / f'{name}.png')

        print(f'  {name}: 9x16 {a.size} + wqhd {b.size} '
              f'(drei Varianten, Kachel {k.size})')

    print('Fertig.')


if __name__ == '__main__':
    main()
