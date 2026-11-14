"""Meldet die Testabdeckung des Dart-Codes und prueft einen Mindestwert.

WARUM (13.11.2026, Betreiber): "gibt es jetzt fuer jeden Teil der App von
funktionen ueber sicherheit und datenschutz tests?" - Die ehrliche
Antwort war: es gibt 1000+ Tests, aber KEINE Messung. Ohne Zahl ist die
Frage nicht beantwortbar, und "wir testen viel" ist keine Antwort.

DIE MESSUNG: `flutter test --coverage` schreibt coverage/lcov.info. Die
Datei nennt je Datei die gefundenen Zeilen (LF) und die getroffenen (LH).
Daraus wird:
  * die Gesamtzahl,
  * die Zahl je Bereich (screens, services, widgets, providers, models,
    utils, generated),
  * ein Vergleich mit einem Mindestwert.

DER MINDESTWERT ist ein Gate: faellt die Abdeckung unter die Grenze,
schlaegt der Befehl fehl. Ohne diese Grenze waere die Zahl nur eine
Zahl - man koennte sie wegkuerzen, ohne dass jemand etwas merkt.

Der Mindestwert ist absichtlich NICHT auf dem aktuellen Stand festge-
nagelt: der Stand wuerde jeden Tag wachsen und das Gate waere dann
nutzlos. Er ist ein Boden, darunter ist es ein Fehler.

AUFruf::

    python tool/check_coverage.py                 # Messen und pruefen
    python tool/check_coverage.py --min 65        # eigene Grenze
    python tool/check_coverage.py --datei pfad    # andere lcov-Datei

Ohne lcov-Datei sagt das Skript, dass es nichts messen konnte - es
behauptet nicht, es sei gruen.
"""

import argparse
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Der Boden. Er liegt bewusst NICHT auf dem aktuellen Stand: der Stand
# waechst mit jedem Test, und ein Boden, der morgen auf dem heutigen
# Stand klebt, waere nach zwei Wochen entweder rot (weil ein Modul
# dazukam) oder nutzlos. Der Boden ist die Linie, unterhalb deren ein
# fehlendes Modul als Fehler auffaellt. Er wird mit jedem Testlauf
# nachgezogen (siehe docs/BETRIEBSAUFGABEN.md).
#
# Stand 13.11.2026: 24,3 % (vor den neuen Tests: 20,8 %) - der Boden
# lag bei 24,0 %.
# Stand 14.11.2026: 29,8 % (vor den neuen Tests: 24,3 %) - der Boden
# liegt jetzt bei 29,0 %.
MINDEST = 29.0

# Die Bereiche, in die die lib-Dateien einsortiert werden.
BEREICHE = [
    ("generated", "lib/generated"),
    ("screens", "lib/screens"),
    ("services", "lib/services"),
    ("widgets", "lib/widgets"),
    ("providers", "lib/providers"),
    ("models", "lib/models"),
    ("utils", "lib/utils"),
    ("routing", "lib/routing"),
    ("theme", "lib/theme"),
    ("screens-roots", "lib/screens"),
]


def lcov_lesen(pfad: pathlib.Path):
    """Liest lcov.info: {datei: (gefunden, getroffen)}."""
    ergebnis = {}
    datei = None
    gefunden = getroffen = 0
    for zeile in pfad.read_text(encoding="utf-8", errors="replace").splitlines():
        if zeile.startswith("SF:"):
            datei = zeile[3:].strip()
            gefunden = getroffen = 0
        elif zeile.startswith("LF:"):
            gefunden = int(zeile[3:].strip())
        elif zeile.startswith("LH:"):
            getroffen = int(zeile[3:].strip())
        elif zeile.strip() == "end_of_record" and datei:
            ergebnis[datei] = (gefunden, getroffen)
            datei = None
    return ergebnis


def prozent(gefunden, getroffen):
    if gefunden <= 0:
        return 0.0
    return 100.0 * getroffen / gefunden


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=float, default=MINDEST,
                        help="Mindestabdeckung in Prozent")
    parser.add_argument("--datei", default="coverage/lcov.info",
                        help="pfad zur lcov-Datei")
    args = parser.parse_args()

    pfad = ROOT / args.datei
    if not pfad.is_file():
        print("  (keine %s - es konnte nichts gemessen werden. "
              "Zuerst 'flutter test --coverage'.)" % args.datei)
        return 1

    daten = lcov_lesen(pfad)
    if not daten:
        print("  (%s ist leer - nichts zu messen.)" % args.datei)
        return 1

    # NUR die App-Dateien (lib/). third_party/ gehoert nicht dazu.
    app = {d: v for d, v in daten.items()
           if d.replace("\\", "/").startswith("lib/")}

    gefunden = sum(v[0] for v in app.values())
    getroffen = sum(v[1] for v in app.values())
    gesamt = prozent(gefunden, getroffen)

    print("=" * 70)
    print("TESTABDECKUNG (lib/)")
    print("=" * 70)
    print()
    print("  Dateien:     %d" % len(app))
    print("  Zeilen:      %d von %d getroffen" % (getroffen, gefunden))
    print("  Abdeckung:   %.1f %%" % gesamt)
    print()

    # Je Bereich aufsummieren (die Bereiche ueberlappen nicht).
    def summiere(praefix):
        f = g = 0
        for d, (df, dg) in app.items():
            norm = d.replace("\\", "/")
            if norm.startswith(praefix):
                f += df
                g += dg
        return f, g

    zeilen = []
    for name, praefix in BEREICHE:
        f, g = summiere(praefix)
        if f == 0:
            continue
        zeilen.append((name, g, f, prozent(f, g)))
    # "screens-roots" ist dasselbe wie "screens" - nicht doppelt zeigen.
    gesehen = set()
    ausgabe = []
    for name, g, f, p in zeilen:
        if name in gesehen:
            continue
        gesehen.add(name)
        ausgabe.append((name, g, f, p))
    for name, g, f, p in sorted(ausgabe, key=lambda z: z[3]):
        balken = "#" * int(p / 5)
        print("  %-10s %6.1f %%  %5d/%-6d %s"
              % (name, p, g, f, balken))
    print()

    # Die am schlechtesten abgedeckten Dateien (Top 10).
    einzel = sorted(app.items(), key=lambda kv: prozent(kv[1][0], kv[1][1]))
    print("  Die zehn schlechtesten Dateien:")
    for d, (f, g) in einzel[:10]:
        if f == 0:
            continue
        print("    %5.1f %%  %s" % (prozent(f, g),
                                   d.replace("\\", "/")))
    print()

    # DIE LISTE FUER DEN NAECHSTEN TESTDURCHGANG: die Dateien mit den
    # MEISTEN unbedeckten Zeilen. Prozentzahlen allein sagen nichts
    # darueber, wo die Arbeit winkt - eine Datei mit 3.000 Zeilen und
    # 10 % Abdeckung ist das halbe Budget.
    print("  Die groessten Luecken (unbedeckte Zeilen):")
    luecken = sorted(
        app.items(), key=lambda kv: (kv[1][0] - kv[1][1]), reverse=True)
    for d, (f, g) in luecken[:12]:
        print("    %5d offen  %5.1f %%  %s"
              % (f - g, prozent(f, g), d.replace("\\", "/")))
    print()

    if gesamt < args.min:
        print("FEHLER: die Abdeckung liegt bei %.1f %% - der Mindestwert "
              "ist %.1f %%." % (gesamt, args.min))
        print("  Ein Modul ohne Test ist der Grund - siehe die Liste oben.")
        return 1

    print("OK: die Abdeckung liegt bei %.1f %% (Mindestwert %.1f %%)."
          % (gesamt, args.min))
    return 0


if __name__ == "__main__":
    sys.exit(main())
