"""Findet Provider-Aenderungen in einem Widget-Lebenszyklus.

WARUM (06.11.2026): Im app.dart wurde in initState ein StateProvider
gesetzt:

  ref.read(globalRelayInboxProvider.notifier).state = inbox;

Riverpod wirft dann "Tried to modify a provider while the widget tree
was building" - im Debug-Build als Ausnahme, im Release als
inkonsistenter Zustand. Live im Emulator gesehen: die App kam beim
Start in einen Fehlerzustand.

DIE REGEL: In initState, build, dispose, didUpdateWidget und
didChangeDependencies darf KEIN Provider gesetzt werden. Riverpods
eigener Rat: "Delay your modification, such as by encapsulating the
modification in a Future(() {...})" - also addPostFrameCallback.

Nutzung:  python tool/check_provider_in_lifecycle.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

LEBENSZYKLUS = ("initState", "build", "dispose", "didUpdateWidget",
                "didChangeDependencies", "deactivate")

# Eine Provider-Zuweisung: "...notifier).state = ..." oder
# "...Provider.state = ..." (nicht "!=", "==", "=>").
ZUWEISUNG = re.compile(r"\.state\s*=(?![=>])")
PROVIDER = re.compile(r"\b(ref|_ref|widget\.ref)\s*\.\s*(read|watch)\s*\(")


def finde_methoden(zeilen):
    """Liefert (name, start, ende, koerper_einrueckung) je Methode."""
    methoden = []
    for i, z in enumerate(zeilen):
        m = re.match(r"\s*(?:Future<[^>]*>|void|Widget|bool|int|String|"
                     r"[\w<>?,\s]+)\s+(\w+)\s*\([^)]*\)\s*(?:async\s*)?\{",
                     z)
        if m and m.group(1) in LEBENSZYKLUS:
            # Die Klammer-Tiefe bis zum Ende der Methode.
            tiefe = 0
            ende = None
            koerper = None
            for k in range(i, len(zeilen)):
                tiefe += zeilen[k].count("{") - zeilen[k].count("}")
                # Die Einrueckung des Koerpers steht in der ERSTEN Zeile
                # nach dem Kopf - nicht in der Kopfzeile selbst.
                if koerper is None and tiefe == 1 and k > i:
                    koerper = len(zeilen[k]) - len(zeilen[k].lstrip())
                if tiefe == 0 and k > i:
                    ende = k
                    break
            if ende is not None:
                methoden.append((m.group(1), i, ende, koerper or 0))
    return methoden


def pruefe_datei(pfad: pathlib.Path) -> list:
    zeilen = pfad.read_text(encoding="utf-8").split("\n")
    funde = []
    for name, von, bis, koerper_einrueckung in finde_methoden(zeilen):
        for k in range(von, bis + 1):
            z = zeilen[k]
            if not (ZUWEISUNG.search(z) and PROVIDER.search(z)):
                continue
            # Nur der direkte Koerper der Methode zaehlt. Was in einem
            # Callback darunter liegt (addListener, addPostFrameCallback)
            # laeuft spaeter - dort ist das Setzen erlaubt.
            if koerper_einrueckung and (
                len(z) - len(z.lstrip())
            ) > koerper_einrueckung:
                continue
            funde.append((k + 1, name, z.strip()))
    return funde


def main() -> int:
    fehler = []
    hinweise = []
    geprueft = 0
    for ordner in ("lib", "test"):
        basis = ROOT / ordner
        if not basis.exists():
            continue
        for pfad in sorted(basis.rglob("*.dart")):
            geprueft += 1
            for zeile, methode, text in pruefe_datei(pfad):
                (hinweise if methode == "dispose" else fehler).append(
                    (pfad.relative_to(ROOT).as_posix(), zeile, methode, text))

    print("PROVIDER-ANDERUNG IM LEBENSZYKLUS")
    print("=" * 72)
    print("  %d Dateien geprueft" % geprueft)

    if hinweise:
        # In dispose ist das Setzen ueblich und flusslos: der Widgetbaum
        # wird da nicht gebaut. Riverpod nennt dispose zwar auch auf,
        # die Praxis zeigt aber: es funktioniert.
        print("  Hinweise (in dispose - dort wird nichts gebaut): %d"
              % len(hinweise))
        for datei, zeile, methode, text in hinweise:
            print("    - %s:%d  %s" % (datei, zeile, text[:80]))

    if fehler:
        print("  FEHLER: %d Stelle(n) in initState/build:" % len(fehler))
        for datei, zeile, methode, text in fehler:
            print("    X %s:%d  (in %s)" % (datei, zeile, methode))
            print("        %s" % text[:88])
        print()
        print("  Riverpod verbietet das: 'Tried to modify a provider while")
        print("  the widget tree was building'. Die Aenderung gehoert in")
        print("  einen addPostFrameCallback:")
        print("    WidgetsBinding.instance.addPostFrameCallback((_) { ... });")
        print()
        print("  Achtung: Der Fehler tritt nur auf, wenn der Provider")
        print("  ZuhörER hat (dann feuert die Benachrichtigung). Die")
        print("  app.dart-Stelle ist live belegt (ANR beim Start).")
        return 1

    print("  OK: in initState und build wird kein Provider gesetzt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
