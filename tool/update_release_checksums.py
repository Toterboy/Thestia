"""Aktualisiert die Pruefsummen in der Testanleitung UND den
Release-Notes.

Nach einem neuen Build sind die SHA-256-Summen der APKs alt. Sie
stehen in der Testanleitung, damit der Betreiber pruefen kann, ob
die Datei auf dem Handy die richtige ist (ein gekuerzter Download
laesst sich sonst schwer vom Original unterscheiden).

BEFUND (11.11.2026): Die Release-Notes hatten einen EIGENEN
Pruefsummen-Block, den dieses Skript nicht angefasst hat - er
stand nach dem Build 52 noch auf den Summen von Build 51. Die
Release-Notes werden ja auf GitHub veroeffentlicht - dort standen
also falsche Summen. Deshalb werden jetzt BEIDE Dokumente
gepflegt.

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
# BEFUND (11.11.2026): Auch die Release-Notes tragen Pruefsummen
# (sie werden auf GitHub veroeffentlicht).
NOTES = RELEASE / "RELEASE_NOTES.md"

# BEFUND (10.11.2026): Das Skript suchte exakt "## 5) Pruefsummen
# (SHA-256)" - die Testanleitung schreibt aber "## 5) Prüfsummen (SHA-256)"
# (mit Umlaut). Dadurch wurde der Abschnitt nicht gefunden und die
# Pruefsummen blieben auf dem alten Stand. Die Suche ist jetzt tolerant:
# beide Schreibweisen werden erkannt.
KOPF = "## 5) Pruefsummen (SHA-256)"
KOPF_UMLAUT = "## 5) Prüfsummen (SHA-256)"
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
    if i == -1:
        i = text.find(KOPF_UMLAUT)
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

    _notes_aktualisieren(zeilen_oeffentlich, zeilen_admin)
    return 0


# Der Abschnitt in den Release-Notes. Er wird an beiden Schreibweisen
# erkannt (mit und ohne Umlaut).
NOTES_KOPF = "## Prüfsummen (SHA-256)"
NOTES_KOPF_ASCII = "## Pruefsummen (SHA-256)"


def _notes_aktualisieren(zeilen_oeffentlich, zeilen_admin) -> None:
    """Ersetzt die Pruefsummen-Bloecke in den Release-Notes.

    BEFUND (11.11.2026): Die Release-Notes hatten einen eigenen
    Pruefsummen-Block, der beim Build nicht mitgepflegt wurde - auf
    GitHub standen dadurch falsche Summen.
    """
    if not NOTES.exists():
        print("  (keine Release-Notes - uebersprungen)")
        return

    text = NOTES.read_text(encoding="utf-8")
    i = text.find(NOTES_KOPF)
    if i == -1:
        i = text.find(NOTES_KOPF_ASCII)
    if i == -1:
        print("  ! In den Release-Notes wurde kein Pruefsummen-Abschnitt "
              "gefunden.")
        return

    # Das Ende des Abschnitts: die naechste Ueberschrift der Ebene 2.
    j = text.find("\n## ", i + 1)
    if j == -1:
        j = len(text)

    abschnitt = text[i:j]

    # Die Code-Bloecke finden. Es sind (normalerweise) zwei: der erste
    # traegt die oeffentlichen Artefakte, der zweite die Admin-Builds.
    #
    # BEFUND (11.11.2026): Die erste Fassung dieser Funktion hat den
    # Admin-Block in den ERSTEN Code-Block geschrieben - und dadurch
    # die oeffentlichen Summen aus den Release-Notes verdraengt. Jetzt
    # werden die Bloecke anhand ihrer Position bestimmt, nicht durch
    # wiederholtes Suchen.
    zaeunf = []
    pos = 0
    while True:
        k = abschnitt.find("```", pos)
        if k == -1:
            break
        zaeunf.append(k)
        pos = k + 3

    if len(zaeunf) < 2:
        print("  ! In den Release-Notes wurde kein Code-Block gefunden.")
        return

    def _inhalt(start: int, ende: int) -> str:
        """Der Text zwischen zwei Zaeunen (ohne die Zaeune selbst)."""
        a = abschnitt.find("\n", start) + 1
        b = abschnitt.find("```", a)
        return abschnitt[a:b]

    bloecke = []
    for k in range(0, len(zaeunf) - 1, 2):
        bloecke.append((zaeunf[k], zaeunf[k + 1]))

    if len(bloecke) < 1:
        print("  ! Der Code-Block in den Release-Notes ist nicht zu.")
        return

    # Von hinten nach vorn ersetzen, damit die Positionen gueltig
    # bleiben. Der erste Block: die oeffentlichen Artefakte. Der
    # zweite (falls vorhanden): die Admin-Builds.
    ersetzungen = [(bloecke[0][0], bloecke[0][1], zeilen_oeffentlich)]
    if len(bloecke) >= 2 and zeilen_admin:
        ersetzungen.append((bloecke[1][0], bloecke[1][1], zeilen_admin))

    for start, ende, inhalt in reversed(ersetzungen):
        abschnitt = (abschnitt[:start]
                     + "```\n" + "\n".join(inhalt) + "\n"
                     + abschnitt[ende:])

    text = text[:i] + abschnitt + text[j:]
    NOTES.write_text(text, encoding="utf-8", newline="\n")
    print("  Die Pruefsummen in den Release-Notes sind aktualisiert.")


if __name__ == "__main__":
    sys.exit(main())
