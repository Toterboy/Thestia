"""Aktualisiert die Pruefsummen in der Testanleitung.

Nach einem neuen Build sind die SHA-256-Summen der APKs alt. Sie
stehen in der Testanleitung, damit der Betreiber pruefen kann, ob
die Datei auf dem Handy die richtige ist (ein gekuerzter Download
laesst sich sonst schwer vom Original unterscheiden).

Das Skript rechnet die Summen der Dateien im Release-Ordner neu und
baut den Abschnitt "Pruefsummen (SHA-256)" neu auf. Zwei Bloecke:
einen fuer die oeffentlichen Artefakte, einen fuer die
Admin-Builds (nur Team-intern).

Aufruf::

    python tool/update_release_checksums.py
"""

import hashlib
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _release_ordner() -> pathlib.Path:
    """Der Release-Ordner gehoert zur Version aus pubspec.yaml.

    BEFUND (09.11.2026): Hier stand fest 'v0.10.0'. Mit dem
    Versionswechsel (0.11.0) waere der Ordner falsch gewesen - und
    die Pruefsummen waeren stillschweigend im alten Ordner gelandet.
    Der Ordner gehoert jetzt zur Version, die gebaut wird.
    """
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9.]+)\+[0-9]+", text, re.M)
    if not m:
        return ROOT / "releases" / "v0.10.0"
    return ROOT / "releases" / ("v" + m.group(1))


RELEASE = _release_ordner()
ANLEITUNG = RELEASE / "TESTANLEITUNG.md"

KOPF = "## 5) Pruefsummen (SHA-256)"
ENDE = "## 6) Wenn etwas nicht geht"


def sha256(datei: pathlib.Path) -> str:
    h = hashlib.sha256()
    with datei.open("rb") as f:
        for stueck in iter(lambda: f.read(1024 * 1024), b""):
            h.update(stueck)
    return h.hexdigest()


def main() -> int:
    if not RELEASE.exists():
        print("  ! Der Release-Ordner fehlt: %s" % RELEASE)
        return 1

    # Die APKs und das AAB im Hauptordner.
    oeffentlich = sorted(
        p for p in RELEASE.iterdir() if p.suffix in (".apk", ".aab")
    )
    # Die Admin-Builds liegen in admin/.
    admin = []
    adminordner = RELEASE / "admin"
    if adminordner.exists():
        admin = sorted(p for p in adminordner.iterdir() if p.suffix == ".apk")

    if not oeffentlich:
        print("  ! Keine Artefakte gefunden.")
        return 1

    print("  %d oeffentliche Artefakte, %d Admin-Builds:"
          % (len(oeffentlich), len(admin)))
    zeilen_oeffentlich = []
    for datei in oeffentlich:
        summe = sha256(datei)
        print("    %-42s %6.1f MB  %s"
              % (datei.name, datei.stat().st_size / (1024 * 1024), summe[:16]))
        zeilen_oeffentlich.append("%s  %s" % (summe, datei.name))
    zeilen_admin = []
    for datei in admin:
        summe = sha256(datei)
        print("    %-42s %6.1f MB  %s (Admin)"
              % (datei.name, datei.stat().st_size / (1024 * 1024), summe[:16]))
        zeilen_admin.append("%s  %s" % (summe, datei.name))

    if not ANLEITUNG.exists():
        print("  ! Die Testanleitung fehlt: %s" % ANLEITUNG)
        return 1

    text = ANLEITUNG.read_text(encoding="utf-8")
    i = text.find(KOPF)
    j = text.find(ENDE)
    if i < 0 or j < 0 or j < i:
        print("  ! Der Abschnitt mit den Pruefsummen wurde nicht gefunden.")
        return 1

    abschnitt = KOPF + """

Damit die Uebertragung auf die Handys geprueft werden kann (ein
gekuerzter Download laesst sich sonst schwer vom Original
unterscheiden):

```
%s
```
""" % "\n".join(zeilen_oeffentlich)

    if zeilen_admin:
        abschnitt += """
Und die Admin-Builds (nur Team-intern, **nicht** verteilen):

```
%s
```
""" % "\n".join(zeilen_admin)

    abschnitt += """
Pruefen in PowerShell:

```powershell
Get-FileHash .\\Thestia-v0.10.0-play.apk -Algorithm SHA256
```

Auf dem Handy (ohne PC): die Datei mit der App "Dateiinfo" oeffnen
oder mit `adb shell sha256sum <datei>`.

"""

    text = text[:i] + abschnitt + text[j:]
    ANLEITUNG.write_text(text, encoding="utf-8", newline="\n")
    print("  Die Pruefsummen in der Testanleitung sind aktualisiert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
