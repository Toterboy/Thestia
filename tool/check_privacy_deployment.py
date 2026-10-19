# tool/check_privacy_deployment.py
"""
Prueft, ob die LIVE ausgelieferte Datenschutzerklaerung mit der im Repo
uebereinstimmt.

WARUM ES DAS GIBT
-----------------
`passkey-assets/datenschutz.html` wird auf Netlify per Drag-and-Drop
hochgeladen, nicht aus dem Repo deployed. Zwei Kopien, keine Kopplung -
und das ist bereits schiefgegangen: live stand Version 5 (v0.9.2) mit
"AusOrt wird nicht erhoben" und "Entfernung in 5-km-Schritten", waehrend
die App seit v0.10.0 das Bundesland speichert, Koordinaten auf ein
5-km-Raster rundet und die Entfernung in 10-km-Stufen zeigt. Die
veroeffentlichte Erklaerung beschrieb also eine App, die es nicht mehr
gibt.

Ein Versions- oder Hash-Vergleich allein haette das nicht gezeigt: das
Repo war korrekt, nur die VEROEFFENTLICHTE Fassung war es nicht.

    python tool/check_privacy_deployment.py

Exit-Code 1 bei Abweichung. Ohne Netz (offline) wird die Pruefung
uebersprungen, nicht als Fehler gewertet - ein Offline-Lauf soll den
Build nicht blockieren.

Die Live-Adresse ist ueber THESTIA_PRIVACY_URL ueberschreibbar.
"""

import hashlib
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL = os.path.join(ROOT, 'passkey-assets', 'datenschutz.html')
DEFAULT_URL = 'https://auth.thestia.de/datenschutz.html'

# Woerter, die nur in einer Version vorkommen. Sie machen den Unterschied
# lesbar, statt nur "Hash weicht ab" zu sagen.
MARKERS = [
    ('Version 6 (v0.10.0)', 'neuer Stand: Ort/Stadt wird nicht erhoben'),
    ('Version 5 (v0.9.2)', 'alter Stand: beschreibt die v0.9.2-Standortlogik'),
    ('5-km-Raster', 'neuer Stand: Koordinaten werden auf ein 5-km-Raster gerundet'),
    ('5-km-Schritten', 'alter Stand: Entfernung in 5-km-Schritten'),
]


def norm(text: str) -> str:
    """Vereinheitlicht fuer den Vergleich."""
    text = re.sub(r'<script.*?</script>', ' ', text, flags=re.S | re.I)
    text = re.sub(r'<style.*?</style>', ' ', text, flags=re.S | re.I)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'&[a-z]+;', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()


def main() -> int:
    url = os.environ.get('THESTIA_PRIVACY_URL', DEFAULT_URL)

    if not os.path.exists(LOCAL):
        print(f'FEHLER: {LOCAL} existiert nicht.')
        return 1

    with open(LOCAL, 'rb') as f:
        lokal = f.read().decode('utf-8', errors='replace')

    print('=' * 70)
    print('DATENSCHUTZERKLAERUNG: Repo vs. live ausgeliefert')
    print('=' * 70)
    print(f'  lokal : {LOCAL}')
    print(f'  live  : {url}')

    try:
        req = urllib.request.Request(
            url, headers={'User-Agent': 'thesia-privacy-check/1.0'})
        with urllib.request.urlopen(req, timeout=25) as res:
            live = res.read().decode('utf-8', errors='replace')
    except (urllib.error.URLError, OSError) as e:
        print()
        print(f'  Live nicht erreichbar ({e}).')
        print('  Pruefung uebersprungen - offline ist das kein Fehler.')
        return 0

    nl, nv = norm(lokal), norm(live)
    if nl == nv:
        print()
        print('OK  live und Repo sind identisch.')
        return 0

    print()
    print('FEHLER  live und Repo weichen ab.')
    print(f'        lokal {len(nl)} Zeichen, live {len(nv)} Zeichen')
    print()
    for marker, bedeutung in MARKERS:
        in_lokal = marker in nl
        in_live = marker in nv
        if in_lokal != in_live:
            ort = 'live' if in_live else 'Repo'
            print(f'  - {marker!r}: nur im {ort} ({bedeutung})')
    print()
    print('  Die live ausgelieferte Fassung ist vermutlich aelter.')
    print('  Netlify: passkey-assets/ neu hochladen (Drag & Drop),')
    print('  danach diese Pruefung erneut laufen lassen.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
