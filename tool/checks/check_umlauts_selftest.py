"""
tool/checks/check_umlauts_selftest.py
==============================
Prueft, dass `check_umlauts.py` Fehler WIRKLICH meldet - und dass er
nicht uebermotive Fehlalarme produziert.

WARUM (16.11.2026): Ein Checker, der nichts findet, sieht aus wie ein
Checker, der sauber ist. Genau das ist beim Gitignore-Checker passiert
(01.11.2026): Die Ausgabe wurde falsch gelesen, der Checker meldete
nichts mehr - und niemand haette es gemerkt, weil "0 Beanstandungen"
nach wie vor gruen aussieht.

Die Negativfaelle hier sind der Kern:

  * "fuer" in einem Nutzertext      -> MUSS gemeldet werden
  * "fuer" in einem Quellcode-Kommentar -> MUSS NICHT gemeldet werden
    (das Projekt schreibt Kommentare bewusst in ASCII)
  * "fuer" in einer URL              -> MUSS NICHT gemeldet werden
  * "Feuer" (echtes Wort ohne Umlaut)-> MUSS NICHT gemeldet werden
  * "für" (korrekt geschrieben)      -> MUSS NICHT gemeldet werden
  * "ueber" am Wortanfang            -> MUSS gemeldet werden

Aufruf:
    python tool/checks/check_umlauts_selftest.py

Exit 0 = alle Negativfaelle wurden erkannt und keine Fehlalarme.
"""

import importlib.util
import pathlib
import sys

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zaehlen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe aendert.
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

TARGET = ROOT / 'tool' / 'checks/check_umlauts.py'

spec = importlib.util.spec_from_file_location('cum', TARGET)
cum = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cum)


def funde_in(text: str, art: str = 'ganz') -> list:
    """Prueft einen Text (die gleiche Logik wie der Checker)."""
    funde: list = []
    if art == 'ganz':
        cum.pruefe(cum.ohne_code_und_urls(text), funde, 'test.txt')
    else:
        for _, literal in cum.lies_string_literale(text):
            cum.pruefe(literal, funde, 'test.txt')
    return funde


def main() -> int:
    fehler: list[str] = []

    # --- MUSS gemeldet werden -------------------------------------------
    faelle_positiv = [
        ('fuer', 'fuer', 'Kommt fuer dich an.'),
        ('ueber', 'ueber', 'Schau ueber die Schulter.'),
        ('pruefen', 'pruefen', 'Bitte Netz pruefen.'),
        ('Schluessel', 'Schluessel', 'Schluessel immer pruefen.'),
        ('Spaeter', 'Spaeter', 'Button: Spaeter'),
        ('oeffnen', 'oeffnen', 'Die Seite oeffnen.'),
        ('weiss', 'weiss', 'Du weisst es nicht.'),
        ('gross', 'gross', 'Die grosse Karte.'),
        ('unabhaengig', 'unabhaengig', ' unabhaengig davon.'),
        ('Minderjaehrigen', 'Minderjaehrigen', 'zu Minderjaehrigen.'),
    ]
    for erwartet, _, text in faelle_positiv:
        funde = funde_in(text)
        if not funde:
            fehler.append(
                f'NICHT GEFUNDEN (sollte gemeldet werden): {text!r} '
                f'(erwartet: {erwartet})'
            )

    # --- MUSS NICHT gemeldet werden -------------------------------------
    faelle_negativ = [
        ('Korrekt geschrieben', 'Diese Nachricht ist für dich da.'),
        ('Echtes Wort ohne Umlaut', 'Das Feuer brennt.'),
        ('URL', 'Siehe https://example.de/fuer-den-test'),
        ('Inline-Code', 'Der Wert `fuer` ist gesetzt.'),
        ('Englischer Text', 'This is for you.'),
    ]
    for begruendung, text in faelle_negativ:
        funde = funde_in(text)
        if funde:
            fehler.append(
                f'FEHLALARM ({begruendung}): {text!r} -> {funde[0][2]}'
            )

    # --- Kommentare im Quellcode bleiben ASCII --------------------------
    quelltext = """
// Kommentar im Projektstil: fuer den Sicherheitscheck, ueber die
// Schulter, Schluessel immer pruefen.
final text = 'Diese Nachricht ist fuer dich da.';
"""
    funde = funde_in(quelltext, art='strings')
    if len(funde) != 1:
        fehler.append(
            'Der Quellcode-Test stimmt nicht: erwartet genau 1 Fund '
            f'(im String-Literal), gefunden {len(funde)}.'
        )
    else:
        gefunden = funde[0]
        if gefunden[2].lower() != 'fuer':
            fehler.append(
                f'Unerwarteter Fund im String-Literal: {gefunden[2]}'
            )

    if fehler:
        print('SELBSTTEST FEHLGESCHLAGEN:')
        for f in fehler:
            print('  - ' + f)
        return 1

    print('OK: der Umlaut-Pruefer findet die Fehler und meldet keine '
          'Fehlalarme.')
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main())
