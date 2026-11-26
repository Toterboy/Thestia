#!/usr/bin/env python3
"""Meldet unsichere Casts auf fremde JSON-Werte.

WARUM (22.11.2026, Betreiber: "Mit fuzzing könntest du in der App nach
Sicherheitslücken suchen."):

Das Fuzzing hat eine Fehlerklasse gefunden, die sich immer wieder
zeigt: ein Cast auf einen Wert, der von außen kommt.

    photos: (json['photos'] as List<dynamic>).map((e) => e as String)

Der Server (oder die Gegenseite) liefert eine Zahl statt eines Textes -
und die App ist weg. Das ist ein Denial of Service über die
Schnittstelle: der Angreifer schickt EIN falsches Feld.

DAS GATE: Es sucht in den Modellen (und in den Diensten, die fremde
Daten lesen) nach Casts auf JSON-Werte und meldet sie. Der richtige
Weg ist der Leser in `lib/utils/common/json_leser.dart`:
`textOf`, `intOf`, `numOf`, `boolOf`, `textListOf`, `dateOf` - die
werfen NIE.

DIE AUSNAHME: `lib/models/settings/app_settings.dart` liest den
lokalen Cache (den die App selbst geschrieben hat). Ein Cast dort ist
eine interne Zusicherung, kein Angriffsfenster - der Wert kommt nicht
von außen. Der Cache wird trotzdem robust gelesen (der Leser
`boolOf` versteht auch "true" als Text).

Aufruf::

    python tool/checks/check_keine_unsicheren_casts.py
"""

import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "pubspec.yaml").exists():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent.parent


ROOT = _projektwurzel()
LIB = ROOT / "lib"

#: Die Dateien, die ausgenommen sind (mit Grund).
AUSNAHMEN = {
    "lib/models/settings/app_settings.dart":
        "Der lokale Cache - die App hat ihn selbst geschrieben.",
}

#: Die Casts auf fremde Werte.
MUSTER = [
    re.compile(r"json\[[^\]]+\]\s+as\s+(String|int|bool|num)\??\b"),
    re.compile(r"DateTime\.parse\(\s*json\["),
    re.compile(r"\)\.map\(\(e\)\s*=>\s*e\s+as\s+String\)"),
]

#: Die Muster für eine ABSICHTLICHE Typprüfung.
#:
#: DER WEG: `json['page'] is int ? json['page'] as int : 0` ist sicher -
#: der Cast wird nur ausgeführt, wenn der Wert wirklich eine Zahl ist.
#: Solche Zeilen sind kein Befund.
GEPRUEFT_MUSTER = re.compile(r"\bis\s+(int|String|bool|num|double|Map|List)\b")


def main() -> int:
    print("=" * 74)
    print("UNSICHERE CASTS: koennte ein fremder Wert die App abstuerzen?")
    print("=" * 74)

    befunde = []
    geprueft = 0
    for datei in sorted(LIB.rglob("*.dart")):
        rel = datei.relative_to(ROOT).as_posix()
        if rel in AUSNAHMEN:
            continue
        geprueft += 1
        zeilen = datei.read_text(encoding="utf-8", errors="replace").splitlines()
        for nummer, zeile in enumerate(zeilen, 1):
            if zeile.strip().startswith("//"):
                continue
            # Eine absichtliche Typprüfung macht den Cast sicher. Sie
            # kann auch in der Zeile DARÜBER stehen (der Wert wird in
            # der nächsten Zeile gecastet).
            if GEPRUEFT_MUSTER.search(zeile):
                continue
            if nummer > 1 and GEPRUEFT_MUSTER.search(zeilen[nummer - 2]):
                continue
            for muster in MUSTER:
                if muster.search(zeile):
                    befunde.append("%s:%d: %s" % (rel, nummer, zeile.strip()))
                    break

    print()
    print("  %d Dateien geprueft." % geprueft)
    if AUSNAHMEN:
        print("  Ausgenommen: %s" % ", ".join(sorted(AUSNAHMEN)))
    if befunde:
        print()
        print("  BE FUNDE - ein fremder Wert kann die App abstuerzen lassen:".replace(" ", ""))
        for befund in befunde:
            print("    X %s" % befund)
        print()
        print("  DER WEG: Der Leser in lib/utils/common/json_leser.dart")
        print("  (textOf, intOf, numOf, boolOf, textListOf, dateOf) wirft NIE.")
        return 1

    print()
    print("  OK: kein unsicherer Cast auf einen fremden JSON-Wert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
