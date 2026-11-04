#!/usr/bin/env python3
"""Erzeugt die Bilder der oeffentlichen Seite (Landing-Seite).

WARUM (04.11.2026): Die Landing-Seite (index.html) zeigte acht
leere Kaesten - die Pfade /screenshots/*.jpg existierten auf dem
Server nicht. Im Quelltext des Verzeichnisses lagen sie auch nicht:
die Bilder waren nie erzeugt worden.

QUELLE: die Store-Screenshots (9x16, 1080x1920) aus
fastlane/metadata/android/<sprache>/images/phoneScreenshots/. Sie
zeigen dieselben Screens und dieselben Texte wie im Store - das
Bild und sein Alt-Text sagen dasselbe.

ZIEL: passkey-assets/screenshots/*.jpg (deutsch) und
passkey-assets/en/screenshots/*.jpg (englisch). Die Bildpfade in den
Landing-Seiten sind RELATIV, damit die englische Seite ihre eigenen
Bilder zeigt.

Aufruf:
    python tool/make_landing_screenshots.py
"""

import pathlib
import sys

from PIL import Image

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parent.parent
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'
PUBLISH = ROOT / 'passkey-assets'

# Die Breite im Web. Die Landing-Seite haelt den Inhalt bei maximal
# 46 rem (~736 px) - mit 720 px liegt das Bild genau in der Breite.
BREITE = 720
QUALITAET = 82

SPRACHEN = [
    ('de-DE', PUBLISH / 'screenshots'),
    ('en-US', PUBLISH / 'en' / 'screenshots'),
]


def main() -> int:
    anzahl = 0
    fehlend = []

    for sprache, ziel in SPRACHEN:
        quelle = FASTLANE / sprache / 'images' / 'phoneScreenshots'
        if not quelle.is_dir():
            print('  %s: keine Store-Screenshots (%s) - erst '
                  'python tool/make_store_screenshots.py'
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
