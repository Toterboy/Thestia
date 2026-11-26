#!/usr/bin/env python3
"""Erzeugt die Bilder der öffentlichen Seite (Landing-Seite).

WARUM (04.11.2026): Die Landing-Seite (index.html) zeigte acht
leere Kästen - die Pfade /screenshots/*.jpg existierten auf dem
Server nicht. Im Quelltext des Verzeichnisses lagen sie auch nicht:
die Bilder waren nie erzeugt worden.

QUELLE: die Store-Screenshots in der KACHELN-Variante (9x16,
1080x1920) aus releases/testapk/screenshots/marketing/9x16-kacheln/
(bzw. .../en/9x16-kacheln/ für Englisch). Das ist die Variante OHNE
nachgeahmte Statusleiste - der Test in test/web_pages_test.dart
verlangt genau das ("Die Galerie zeigt die Kacheln, nicht den
Geräte-Screen").

Die Geräte-Screens (fastlane/.../phoneScreenshots) haben oben die
gemalte Statusleiste (Uhrzeit, WLAN, Akku) auf weissem Grund - das
sieht in der Galerie nach einem Screenshot aus und ist für die
Webseite die falsche Wahl.

ZIEL: passkey-assets/screenshots/*.jpg (deutsch) und
passkey-assets/en/screenshots/*.jpg (englisch). Die Bildpfade in den
Landing-Seiten sind RELATIV, damit die englische Seite ihre eigenen
Bilder zeigt.

Aufruf:
    python tool/web/make_landing_screenshots.py
"""

import pathlib
import sys

from PIL import Image

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zählen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe ändert.
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


ROOT = _projektwurzel()

FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'
PUBLISH = ROOT / 'passkey-assets'

# Die Breite im Web. Die Landing-Seite hält den Inhalt bei maximal
# 46 rem (~736 px) - mit 720 px liegt das Bild genau in der Breite.
BREITE = 720
QUALITAET = 82

SPRACHEN = [
    ('de-DE', PUBLISH / 'screenshots'),
    ('en-US', PUBLISH / 'en' / 'screenshots'),
]

# Die Quelle: die Kacheln-Variante der Store-Screenshots.
QUELLE = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing'


def main() -> int:
    anzahl = 0
    fehlend = []

    for sprache, ziel in SPRACHEN:
        basis = QUELLE if sprache == 'de-DE' else QUELLE / 'en'
        quelle = basis / '9x16-kacheln'
        if not quelle.is_dir():
            print('  %s: keine Kacheln-Screenshots (%s) - erst '
                  'python tool/images/make_store_screenshots.py'
                  % (sprache, quelle.relative_to(ROOT)))
            return 1

        ziel.mkdir(parents=True, exist_ok=True)
        for png in sorted(quelle.glob('*.png')):
            with Image.open(png) as im:
                im = im.convert('RGB')
                hoehe = round(im.height * BREITE / im.width)
                klein = im.resize((BREITE, hoehe), Image.LANCZOS)
                ziel_pfad = ziel / (png.stem + '.jpg')
                klein.save(ziel_pfad, format='JPEG', quality=QUALITAET,
                           optimize=True, progressive=True)
            anzahl += 1
            print('  %s %-22s %d B' % (sprache, ziel_pfad.name,
                                       ziel_pfad.stat().st_size))

    # Gegenprobe: Die Landing-Seiten verweisen auf genau diese Dateien.
    for seite, basis in (('passkey-assets/index.html', 'screenshots'),
                          ('passkey-assets/en/index.html', 'screenshots')):
        p = ROOT / seite
        if not p.is_file():
            fehlend.append('%s fehlt' % seite)
            continue
        text = p.read_text(encoding='utf-8')
        import re
        pfade = re.findall(r'src="(screenshots/[^"]+)"', text)
        if not pfade:
            fehlend.append('%s: keine Bildpfade gefunden' % seite)
            continue
        for pfad in pfade:
            if not (p.parent / pfad).is_file():
                fehlend.append('%s: %s fehlt' % (seite, pfad))
        print('  %s: %d Bildpfade geprueft' % (seite, len(pfade)))

    print()
    if fehlend:
        for f in fehlend:
            print(' X', f)
        print('%d Befund(e).' % len(fehlend))
        return 1

    print('OK: %d Landing-Bilder erzeugt.' % anzahl)
    return 0


if __name__ == '__main__':
    sys.exit(main())
