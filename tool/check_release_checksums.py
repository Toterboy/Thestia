"""Prueft die SHA-256-Pruefsummen in den Release-Dokumenten.

BEFUND (11.11.2026): Die Release-Notes hatten einen EIGENEN
Pruefsummen-Block, den `tool/update_release_checksums.py` nicht
angefasst hat. Nach dem Build 52 standen dort dadurch die Summen
von Build 51 - und die Release-Notes werden ja auf GitHub
veroeffentlicht. Dort standen also falsche Summen.

Diese Pruefung rechnet die Summen der Dateien neu und vergleicht
sie mit ALLEN Release-Dokumenten. Sie findet:
  * eine falsche Summe (die Datei wurde nach dem Bauen geaendert),
  * eine fehlende Datei (ein Artefakt steht nicht im Dokument),
  * eine erwaehnte Datei, die es nicht gibt.

Der Ordner `releases/` steht nicht im Repository (siehe .gitignore).
Deshalb laeuft diese Pruefung nur, wenn der Ordner mit dem
gebauten Stand liegt - sonst gibt sie sich zufrieden.

Aufruf::

    python tool/check_release_checksums.py
"""

import hashlib
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _release_ordner() -> pathlib.Path:
    """Der Release-Ordner gehoert zur Version aus pubspec.yaml."""
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9.]+)\+[0-9]+", text, re.M)
    if not m:
        return ROOT / "releases" / "v0.10.0"
    return ROOT / "releases" / ("v" + m.group(1))


RELEASE = _release_ordner()

# Die Dokumente, die Pruefsummen tragen duerfen.
DOKUMENTE = ["TESTANLEITUNG.md", "RELEASE_NOTES.md"]

MUSTER = re.compile(r"([0-9a-f]{64})\s+(Thestia-v[0-9.]+-[^\s]+)")


def sha256(datei: pathlib.Path) -> str:
    h = hashlib.sha256()
    with datei.open("rb") as f:
        for stueck in iter(lambda: f.read(1024 * 1024), b""):
            h.update(stueck)
    return h.hexdigest()


def main() -> int:
    if not RELEASE.exists():
        # BEFUND (11.11.2026): Der Release-Ordner steht nicht im
        # Repository. In der CI gibt es deshalb nichts zu pruefen -
        # das ist kein Fehler, sondern eine nicht moegliche Pruefung.
        print("  (kein Release-Ordner: %s - nichts zu pruefen)" % RELEASE)
        return 0

    artefakte = {}
    for p in sorted(RELEASE.iterdir()):
        if p.suffix in (".apk", ".aab"):
            artefakte[p.name] = sha256(p)
    adminordner = RELEASE / "admin"
    if adminordner.exists():
        for p in sorted(adminordner.iterdir()):
            if p.suffix == ".apk":
                artefakte[p.name] = sha256(p)

    if not artefakte:
        print("  (keine Artefakte im Release-Ordner - nichts zu pruefen)")
        return 0

    fehler = 0
    for name in DOKUMENTE:
        dok = RELEASE / name
        if not dok.exists():
            print("  %-22s (nicht vorhanden - uebersprungen)" % name)
            continue

        text = dok.read_text(encoding="utf-8")
        gefunden = MUSTER.findall(text)
        if not gefunden:
            print("  %-22s FEHLER: keine Pruefsummen gefunden" % name)
            fehler += 1
            continue

        fehler_dok = 0
        genannte = set()
        for summe, datei in gefunden:
            genannte.add(datei)
            soll = artefakte.get(datei)
            if soll is None:
                print("  %-22s FEHLER: %s wird genannt, die Datei gibt es nicht"
                      % (name, datei))
                fehler_dok += 1
            elif soll != summe:
                print("  %-22s FEHLER: %s hat eine falsche Summe" % (name, datei))
                print("       im Dokument: %s" % summe)
                print("       wirklich:     %s" % soll)
                fehler_dok += 1

        fehlend = [a for a in artefakte if a not in genannte]
        if fehlend:
            print("  %-22s FEHLER: nicht genannt: %s"
                  % (name, ", ".join(sorted(fehlend))))
            fehler_dok += 1

        if fehler_dok:
            fehler += fehler_dok
        else:
            print("  %-22s OK (%d Pruefsummen stimmen)" % (name, len(gefunden)))

    if fehler:
        print("\n  %d PROBLEM(E) - die Pruefsummen sind veraltet." % fehler)
        print("  Fix: python tool/update_release_checksums.py")
        return 1

    print("\n  OK: alle Pruefsummen in den Release-Dokumenten stimmen.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
