"""Prueft: In lib/ und test/ gibt es keine leeren catch-Bloecke mehr.

WARUM (05.11.2026): Die App hatte 94 leere `catch (_) {}`-Bloecke.
Sie waren nicht falsch - das Muster "ein fehlgeschlagener
Einzelschritt darf den Ablauf nicht stoppen" ist richtig (beim
Abmelden darf ein kaputter Cache-Abbau nicht die restliche
Aufraeumung verhindern). Aber sie verschluckten jeden Fehler
spurlos: niemand konnte sehen, dass beim Aufraeumen etwas
schiefging.

AB LOESUNG: Es gibt jetzt den zentralen Helfer
lib/utils/best_effort.dart. Er macht genau dasselbe wie ein leeres
catch - der Fehler stoppt den Ablauf nicht - protokolliert ihn aber.

DESHALB DIESES GATE: Ein leeres catch waere wieder still. Der
Analyzer-Lint "empty_catches" faellt hier nicht durch, weil der
Unterstrich im catch ("catch (_)") fuer den Analyzer ein
"bewusst ignoriert" ist - gemessen: mit aktiviertem Lint meldet er
keinen der 94 Bloecke, nur die ohne Unterstrich.

Nutzung:  python tool/check_no_empty_catches.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Ein catch-Block, der direkt gefolgt von einer Klammer folgt.
CATCH = re.compile(r"catch\s*\(([^)]*)\)\s*\{")


def leerer_catch(text: str) -> list:
    """Die Zeilen, an denen ein leerer catch steht."""
    funde = []
    # Die Kommentarzeilen ausblenden (sonst zaehlt der Beispielcode
    # im Doc-Kommentar des Helfers mit).
    ohne_kommentare = []
    for zeile in text.split("\n"):
        if zeile.lstrip().startswith("//"):
            ohne_kommentare.append("")
        else:
            ohne_kommentare.append(zeile)
    raus = "\n".join(ohne_kommentare)

    for m in CATCH.finditer(raus):
        offen = raus.index("{", m.end() - 1)
        tiefe = 0
        i = offen
        while i < len(raus):
            if raus[i] == "{":
                tiefe += 1
            elif raus[i] == "}":
                tiefe -= 1
                if tiefe == 0:
                    break
            i += 1
        else:
            continue
        body = raus[offen + 1:i]
        if body.strip() == "":
            funde.append(raus[:m.start()].count("\n") + 1)
    return funde


def main() -> int:
    fehler = []
    geprueft = 0
    for ordner in ("lib", "test"):
        for p in sorted((ROOT / ordner).rglob("*.dart")):
            geprueft += 1
            zeilen = leerer_catch(p.read_text(encoding="utf-8"))
            for zeile in zeilen:
                fehler.append("%s:%d" % (p.relative_to(ROOT).as_posix(),
                                         zeile))

    print("LEERE CATCH-BLOECKE")
    print("=" * 66)
    print("  %d Dateien geprueft" % geprueft)
    if fehler:
        print("  FEHLER: %d leerer(e) catch-Bloecke:" % len(fehler))
        for f in fehler:
            print("    X %s" % f)
        print()
        print("  Nutze lib/utils/best_effort.dart:")
        print("    await bestEffort('Was passiert', () async { ... });")
        print("  Der Fehler wird protokolliert, der Ablauf laeuft weiter.")
        return 1
    print("  OK: kein leerer catch - jeder Fehler hat eine Spur.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
