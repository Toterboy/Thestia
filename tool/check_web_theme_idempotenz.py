"""
tool/check_web_theme_idempotenz.py
==================================
Prueft, dass die Web-Werkzeuge WIEDERHOLBAR sind: ein zweiter
Durchlauf darf an den Seiten NICHTS aendern.

ANLASS (01.11.2026): Der Betreiber musste den ganzen Ordner
passkey-assets/ bei JEDER Aenderung neu hochladen. Ursache war nicht
der Netlify-Upload, sondern die Werkzeuge: apply_theme() war nicht
idempotent.

Zwei Stellen sammelten Zeilen an:

  1) Der CSS-Block. THEME_CSS beginnt mit einem Umbruch und einer
     Einrueckung, und der Marker sitzt erst an Position 5 des
     CSS-Blocks. strip_theme() entfernte ab dem Marker - der Rest
     blieb stehen und kam bei jedem Lauf dazu.

  2) Die Kopfzeile. apply_theme() setzte einen Umbruch zwischen
     <body> und der Kopfzeile; strip_theme() entfernte die Kopfzeile,
     aber nicht diesen Umbruch.

Das Ergebnis: die Seite war nach jedem Durchlauf eine Zeile laenger.
Weil die Datei sich damit aenderte, meldete
check_privacy_deployment.py eine Abweichung - und der Betreiber
musste alles neu hochladen, obwohl sich an den Seiten nichts
geaendert hatte.

Dieser Selbsttest macht genau das messbar, was vorher nur
auffaellig war: Er prueft, dass ein zweiter Durchlauf die Dateien
byte-identisch laesst.

Aufruf:
    python tool/check_web_theme_idempotenz.py

Exit 0 = alle Seiten sind wiederholbar.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))

from web_theme import apply_theme, strip_theme  # noqa: E402

# Die SeitENlisten und die Sprachlogik kommen aus apply_web_theme.py -
# sonst prueft dieser Selbsttest etwas anderes als das echte Werkzeug.
# Das war die Ursache fuer einen Fehlalarm: apply_theme() ohne den
# Sprachknopf entfernt ihn, und die Seite war damit "veraendert".
from apply_web_theme import EN_SEITEN, NUR_CSS, SEITEN, sprachziel  # noqa: E402

ASSETS = ROOT / 'passkey-assets'

FEHLER = []


def pruefe_seite(name: str, nur_css: bool) -> None:
    pfad = ASSETS / name
    if not pfad.exists():
        FEHLER.append(f'{name}: fehlt')
        return

    vorher = pfad.read_text(encoding='utf-8')
    ziel, sprache = sprachziel(name)

    # 1) Ohne --force: der Normalfall. apply_theme() entfernt ein
    #    vorhandenes Theme und spielt es neu ein.
    nachher = apply_theme(vorher,
                          insert_chrome=not nur_css,
                          sprach_ziel=ziel,
                          sprache=sprache)
    if nachher != vorher:
        FEHLER.append(
            f'{name}: ein Durchlauf aendert die Datei '
            f'({len(vorher)} -> {len(nachher)} Zeichen)')

    # 2) Mit --force: der Weg, den apply_web_theme.py nimmt. Erst
    #    strip_theme(), dann apply_theme() - das Ergebnis muss
    #    dasselbe sein.
    quelle = strip_theme(vorher, remove_chrome=not nur_css)
    erzwungen = apply_theme(quelle,
                            insert_chrome=not nur_css,
                            sprach_ziel=ziel,
                            sprache=sprache)
    if erzwungen != nachher:
        FEHLER.append(f'{name}: --force ergibt ein anderes Ergebnis '
                      f'als der Normalfall')


def main() -> int:
    print('=' * 70)
    print('SELBSTTEST: Web-Werkzeuge muessen wiederholbar sein')
    print('=' * 70)

    for name in SEITEN + EN_SEITEN:
        pruefe_seite(name, nur_css=False)
    for name in NUR_CSS:
        pruefe_seite(name, nur_css=True)

    # Zugriff auf die Beispieldatei: die Werkzeuge an sich muessen
    # auch auf einer frischen Seite stabil sein.
    beispiel = (
        '<!DOCTYPE html>\n<html>\n<head>\n<style>\nbody { margin: 0; }\n'
        '</style>\n</head>\n<body>\n\n<h1>Test</h1>\n\n</body>\n</html>\n')
    einmal = apply_theme(beispiel)
    zweimal = apply_theme(einmal)
    if einmal != zweimal:
        FEHLER.append('Beispielseite: zweiter Durchlauf aendert sie')
    else:
        print('  OK    Beispielseite ist wiederholbar')

    if FEHLER:
        print()
        print('FEHLER:')
        for f in FEHLER:
            print('  X', f)
        print()
        print('Ein nicht wiederholbares Werkzeug zwingt zum Neuladen des')
        print('GANZEN Publish-Ordners - bei jeder kleinen Aenderung.')
        return 1

    print()
    print('OK  alle Seiten sind wiederholbar - ein zweiter Durchlauf')
    print('    aendert nichts. Es muss also nur hochgeladen werden, was')
    print('    sich wirklich geaendert hat.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
