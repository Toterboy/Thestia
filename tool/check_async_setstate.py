"""Findet 'setState nach dispose' - setState nach einem await ohne mounted.

WARUM (06.11.2026): Bei der Bildauswahl, beim Standort-Speichern und
in weiteren Faellen wird nach einem await (Serveraufruf, Datei lesen)
setState gerufen, ohne den mounted zu pruefen. Navigiert der Nutzer
in dieser Zeit weg, ruft Flutter setState auf einem abgeraeumten
State auf - im Debug-Build ein Absturz ("setState() called after
dispose()").

DIE REGEL: Zwischen dem await und dem setState muss ein mounted-Check
stehen (oder der Zweig kehrt zurueck).

DIE PRAEZISION (das ist der schwierige Teil - ein zu lueftiger Filter
meldet Fehlalarme und wird dann ignoriert):
  * Die Suche endet an der Funktionsgrenze. Ein await aus einer
    ANDEREN Funktion zaehlt nicht.
  * Ein mounted-Check in derselben Zeile zaehlt
    ("if (mounted) setState(...)").
  * Ein setState in einem Callback (onPressed/onTap) zaehlt nicht -
    dort gibt es kein "nach dem await".
  * Kommentarzeilen zaehlen nicht (dort steht "setState" nur im Text).

Nutzung:  python tool/check_async_setstate.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

CALLBACK = re.compile(
    r"on(Pressed|Tap|Changed|Selected|Submitted|ValueChanged|LongPress"
    r"|Toggled|Saved|Submitted|EditingComplete|Submitted)\s*:"
)


def ist_kommentar(zeile: str) -> bool:
    s = zeile.strip()
    return s.startswith("//") or s.startswith("///") or s.startswith("*")


def funktionsgrenzen(zeilen):
    """Die Klammer-Tiefe vor jeder Zeile."""
    tiefe = 0
    out = []
    for z in zeilen:
        out.append(tiefe)
        tiefe += z.count("{") - z.count("}")
    return out


def pruefe_datei(pfad: pathlib.Path) -> list:
    zeilen = pfad.read_text(encoding="utf-8").split("\n")
    tiefe_vor = funktionsgrenzen(zeilen)
    funde = []

    for i, z in enumerate(zeilen):
        if "setState(" not in z or ist_kommentar(z):
            continue
        # Der mounted-Check darf in derselben Zeile stehen.
        if "mounted" in z:
            continue
        # Ein setState in einem Callback zaehlt nicht.
        if CALLBACK.search(z) or "=>" in z[: z.index("setState(")]:
            continue

        # Die Funktion, in der der setState steht: die Zeile, in der
        # die Klammer-Tiefe am kleinsten ist (der Funktionskopf).
        tiefe = tiefe_vor[i]
        func_von = i
        while func_von > 0 and tiefe_vor[func_von - 1] >= tiefe:
            func_von -= 1

        # Das letzte await DAVOR, aber nur innerhalb der Funktion.
        last_await = None
        for k in range(i - 1, func_von - 1, -1):
            if re.search(r"\bawait\b", zeilen[k]):
                # Nur ein await auf derselben Ebene zaehlt (nicht in
                # einem tieferen Zweig, der danach zurueckkehrt).
                if len(zeilen[k]) - len(zeilen[k].lstrip()) >= (
                    len(z) - len(z.lstrip())
                ):
                    last_await = k
                break
        if last_await is None:
            continue

        dazwischen = zeilen[last_await + 1:i]
        if any("mounted" in d for d in dazwischen):
            continue
        if any(re.match(r"\s*return\b", d) for d in dazwischen):
            continue
        funde.append((i + 1, last_await + 1, z.strip()))
    return funde


def main() -> int:
    fehler = []
    geprueft = 0
    for ordner in ("lib", "test"):
        basis = ROOT / ordner
        if not basis.exists():
            continue
        for pfad in sorted(basis.rglob("*.dart")):
            geprueft += 1
            for zeile, await_zeile, text in pruefe_datei(pfad):
                fehler.append((pfad.relative_to(ROOT).as_posix(), zeile,
                               await_zeile, text))

    print("SETSTATE NACH AWAIT (ohne mounted-Check)")
    print("=" * 72)
    print("  %d Dateien geprueft" % geprueft)
    if fehler:
        print("  FEHLER: %d Stelle(n):" % len(fehler))
        for datei, zeile, await_zeile, text in fehler:
            print("    X %s:%d (await in Zeile %d)" % (datei, zeile,
                                                      await_zeile))
            print("        %s" % text[:88])
        print()
        print("  Nach einem await muss der mounted geprueft werden:")
        print("    if (!mounted) return;")
        return 1
    print("  OK: nach jedem await wird der mounted geprueft.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
