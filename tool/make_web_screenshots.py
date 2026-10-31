#!/usr/bin/env python3
"""Erzeugt die Screenshot-Kacheln fuer die Webseite (thestia.de).

NUTZERWUNSCH (31.10.2026): "Auf thestia.de sollen auch die Screenshots
von /release/testapk/screenshots/marketing/9x16-kacheln angezeigt werden."

Das Original liegt in releases/ - und releases/ ist bewusst NICHT im
Repository (dort liegen die Release-Artefakte). Die Webseite braucht die
Bilder aber im Publish-Verzeichnis. Deshalb kopiert dieses Skript die
Kacheln nach passkey-assets/screenshots/ - und zwar VERKLEINERT.

Warum verkleinert: tool/check_web_payload.py legt eine Obergrenze von
200 KB je Datei im Publish-Verzeichnis fest. Die Originale wiegen
300-370 KB. Ausserdem werden sie auf der Seite in einem Raster
angezeigt - in Originalgroesse waeren sie auf dem Handy unbrauchbar
und auf dem Desktop unnoetig gross.

Die Verkleinerung passiert in zwei Schritten:
  1. Kachel auf 540 x 960 verkleinern (die Seite zeigt sie hoechstens
     so breit - auf einem 360-Pixel-Handy sogar noch kleiner).
  2. Als JPEG mit Qualitaet 82 speichern. PNG verliert bei Verlaufs-
     flaechen sehr viel (die Kacheln sind 330 KB als PNG, 60 KB als
     JPEG), ohne sichtbaren Verlust.

Qualitaet und Groesse werden nachgeprueft: jede Datei muss unter der
Obergrenze liegen, sonst bricht das Skript ab - so kann keine zu
grosse Datei in das Publish-Verzeichnis geraten.

Aufruf:  python tool/make_web_screenshots.py
"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Die Quelle ist die KACHELN-Variante, nicht der App-Screenshot
# (NUTZERWUNSCH 31.10.2026: "Es sollen nur die Screenshots benutzt
# werden, die mit Kacheln sind, also keine, die eine Statusleiste oder
# so haben.").
#
# Der Unterschied ist sichtbar: der App-Screenshot (9x16) zeigt einen
# kompletten Geraete-Screen MIT nachgeahmter Statusleiste und
# Navigationsleiste. Die Kacheln-Variante (9x16-kacheln) legt die
# echten Inhalte als einzelne Kacheln auf den Markenverlauf - ohne
# Statusleiste, ohne Navigationsleiste.
#
# Das ist auf der Website das richtige: es sind die Bausteine der App,
# nicht das Bild eines Geraets. Und die Kacheln sind einzeln geladen
# (und einzeln ueber ein Raster verteilt) - ein Geraete-Screen in
# der Mitte des Rasters waere ein Fremdkoerper.
QUELLE = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing' / \
    '9x16-kacheln'
ZIEL = ROOT / 'passkey-assets' / 'screenshots'

# Die Startseite (index.html). Dort steht die Galerie.
INDEX = ROOT / 'passkey-assets' / 'index.html'

# Marken um den erzeugten Abschnitt. Ohne sie gaenge die Galerie
# verloren, sobald die Seite von Hand angefasst wird - mit ihnen
# weiss das Skript genau, was es ersetzen darf.
GALERIE_START = '<!-- GALERIE (tool/make_web_screenshots.py) -->'
GALERIE_ENDE = '<!-- /GALERIE -->'

# Obergrenze je Datei - dieselbe Zahl wie in tool/check_web_payload.py.
MAX_KB = 200

# Kantenlaenge der Web-Fassung. Die Seite zeigt die Kacheln in einem
# Raster; auf einem 360-Pixel-Handy ist das die groesste sinnvolle
# Breite. In Originalgroesse (1080 x 1920) waere die Datei dreimal so
# gross und auf dem Handy unscharf heruntergerechnet.
BREITE = 540

# Qualitaet des JPEG. 82 ist der Punkt, an dem Verlaufskanten noch
# sauber aussehen und die Datei aber unter ein Drittel der PNG-Groesse
# faellt. Bewusst nicht hoeher: der Unterschied ist auf der Seite
# (max. 540 Pixel breit) nicht zu sehen.
QUALITAET = 82

# Reihenfolge der Kacheln auf der Seite. Der Dateiname ist die
# Nummer, danach der Name - die Sortierung ist also einfach die
# Dateisortierung.
KACHELN = [
    ('01_willkommen', 'Blind Date mit Substanz',
     'Persönlichkeit vor Aussehen'),
    ('02_aktuelles', 'Dein Überblick, jeden Tag',
     'Neue Nachrichten, neue Likes, neue Funken'),
    ('03_chat', 'Euer Chat bleibt bei euch',
     'Ende-zu-Ende-verschlüsselt'),
    ('04_entdecken', 'Fünf Wege, einen Funken zu zünden',
     'Von Find your Match bis Transit Spark'),
    ('05_anpassen', 'Dein Stil, deine Farben',
     'Sechs Farbschemata, Hell/System/Dunkel'),
    ('06_hell_dunkel', 'Hell oder dunkel, ganz wie du willst',
     'Drei Erscheinungsmodi: Hell, System oder Dunkel'),
    ('07_eisbrecher', 'Eisbrecher statt Smalltalk',
     'Fragen, die man gern beantwortet'),
    ('08_datenschutz', 'Deine Daten bleiben bei dir',
     'Was erhoben wird - und was nicht'),
]


def galerie_html() -> str:
    """Baut den Galerie-Abschnitt der Startseite.

    Bewusst als EIN Markup-Block mit Bildern und Bildunterschriften:
    die Unterschrift nennt, was auf dem Bild zu sehen ist - das ist
    mehr Information als ein Bild ohne Text, und der Text steht da,
    wo das Bild steht (nicht in einer Liste daneben).

    Der Pfad beginnt mit einem Schraegstrich: die Seite liegt auf
    thestia.de, die Bilder im Unterordner "screenshots/". Mit
    absolutem Pfad findet der Browser sie auch, wenn die Seite
    ueber einen Rewrite (z. B. /impressum) ausgeliefert wird.
    """
    teile = []
    for name, titel, unter in KACHELN:
        teile.append(
            '      <figure class="galerie-bild">\n'
            '        <img src="/screenshots/%s.jpg" alt="%s" loading="lazy" '
            'decoding="async" width="540" height="960">\n'
            '        <figcaption><strong>%s</strong>%s</figcaption>\n'
            '      </figure>' % (name, titel, titel, unter))
    return (
        '    <section class="galerie" aria-labelledby="galerie-titel">\n'
        '      <h2 class="galerie-titel" id="galerie-titel">Ein Blick in die '
        'App</h2>\n'
        '      <p class="galerie-text">Die Bilder zeigen die App in '
        'der Reihenfolge, in der man sie kennenlernt - vom ersten '
        'Screen bis zum Datenschutz.</p>\n'
        '      <div class="galerie-raster">\n'
        + '\n'.join(teile) + '\n'
        '      </div>\n'
        '    </section>')


def setze_galerie() -> bool:
    """Schreibt den Galerie-Abschnitt in die Startseite.

    Ersetzt den Bereich zwischen den Marken. Fehlen die Marken, wird
    nichts angefasst und der Grund gemeldet - dann wird die Seite
    nicht ungefragt umgebaut.
    """
    if not INDEX.exists():
        print('FEHLER: %s fehlt' % INDEX)
        return False
    html = INDEX.read_text(encoding='utf-8')
    if GALERIE_START not in html or GALERIE_ENDE not in html:
        print('FEHLER: Die Marken der Galerie fehlen in index.html.')
        print('  Erwartet: %s ... %s' % (GALERIE_START, GALERIE_ENDE))
        return False
    a = html.index(GALERIE_START)
    b = html.index(GALERIE_ENDE, a)
    neu = html[:a] + GALERIE_START + '\n' + galerie_html() + '\n    ' + \
        html[b:]
    INDEX.write_text(neu, encoding='utf-8', newline='\n')
    print('  Galerie in index.html aktualisiert')
    return True


def main() -> int:
    if not QUELLE.is_dir():
        print('FEHLER: Quelldateien fehlen: %s' % QUELLE)
        print('Zuerst die Store-Screenshots erzeugen:')
        print('  python tool/make_store_screenshots.py')
        return 1

    ZIEL.mkdir(parents=True, exist_ok=True)

    # Alte Dateien entfernen, die nicht mehr im Quellverzeichnis
    # liegen. Sonst bleiben die Kacheln eines alten Screenshots
    # stehen, wenn ein Screen umbenannt wurde.
    quellen = {n + '.jpg' for n, _, _ in KACHELN}
    for alt in ZIEL.glob('*.jpg'):
        if alt.name not in quellen:
            alt.unlink()
            print('  verwaiste Datei entfernt: %s' % alt.name)

    gross = 0
    for name, titel, unter in KACHELN:
        quelle = QUELLE / ('%s.png' % name)
        if not quelle.exists():
            print('  fehlt: %s' % quelle.name)
            return 1

        bild = Image.open(quelle).convert('RGB')
        # Nur verkleinern - vergrössern bringt nichts.
        if bild.width > BREITE:
            hoehe = round(bild.height * BREITE / bild.width)
            bild = bild.resize((BREITE, hoehe), Image.LANCZOS)

        ziel = ZIEL / ('%s.jpg' % name)
        bild.save(ziel, 'JPEG', quality=QUALITAET, optimize=True,
                  progressive=True)

        kb = ziel.stat().st_size / 1024
        gross += kb
        if kb > MAX_KB:
            print('FEHLER: %s wiegt %.0f KB - ueber der Grenze von %d KB.'
                  % (ziel.name, kb, MAX_KB))
            return 1
        print('  %-22s %4.0f KB  %dx%d' % (ziel.name, kb,
                                         bild.width, bild.height))

    print()
    print('%d Kacheln, zusammen %.0f KB.' % (len(KACHELN), gross))

    if not setze_galerie():
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
