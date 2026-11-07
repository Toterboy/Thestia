#!/usr/bin/env python3
"""Prueft, ob die ausgelieferten Artefakte zum aktuellen Quellstand
passen.

WARUM (07.11.2026, Betreiber): "wie es die ganze Zeit neue Probleme
geben kann, wenn du es immer pruefst. Bitte deck das mit tests besser
ab oder irgendwie anders sinnvoll."

DIE ANTWORT: Die Tests pruefen den CODE. Sie pruefen nicht, ob die
AUSGELIEFERTE DATEI den geprueften Code enthaelt. Genau da sind
beide Fehler passiert:

  1) Die Admin-APK im Release-Ordner war Build 33, der Quellstand
     Build 38. Der Betreiber hat sie getestet und einen Fehler
     gemeldet, den es im aktuellen Stand nicht mehr gab. Der
     versionCode-Vergleich haette es beim Release-Abnehmen gemeldet.

  2) In den alten Release-Ordnern lagen 16 Admin-APKs mit der alten,
     als kompromittiert geltenden UUID. Sie sahen aus wie die
     aktuellen.

Beides sind keine Codefehler, sondern Auslieferungsfehler. Und
Auslieferungsfehler kann kein Test der App finden - sie entstehen
durch das Zusammenspiel aus Bau, Kopieren und Verteilen.

DIESE PRUEFUNG macht drei Dinge:

  A) Die Build-Nummer im Artefakt muss zur Version in pubspec.yaml
     passen. Fuer die oeffentlichen Artefakte ist das die Basis-
     Nummer (plus der ABI-Aufschlag bei den geteilten APKs), fuer die
     Admin-Builds die Basis plus ADMIN_BUILD_OFFSET.

  B) Das Artefakt muss nach der letzten Aenderung am App-Quellstand
     gebaut sein. Ein Build, der aelter ist als die letzte
     Quellzeile, traegt den alten Code - auch wenn die Versionsnummer
     zufaellig passt.

  C) Der Quellstand muss den Code wirklich enthalten, den das
     Artefakt behauptet: Das Werkzeug sucht einen Marker im
     kompilierten Code (z. B. eine neu hinzugefuegte Fehlermeldung).

Aufruf::

    python tool/check_release_version.py

Ohne Artefakte sagt das Skript, dass es nichts pruefen konnte - es
behauptet nicht, es sei gruen.
"""

import hashlib
import pathlib
import re
import subprocess
import sys
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
RELEASES = ROOT / "releases"

# Der Aufschlag des Admin-Builds (siehe tool/build_release.ps1).
ADMIN_BUILD_OFFSET = 9000

# Der ABI-Aufschlag der geteilten APKs: Flutter addiert je
# CPU-Architektur eine eigene Zahl, damit die geteilten APKs
# unterschiedliche Codes bekommen (armv7 = 1000, arm64 = 2000,
# x86_64 = 4000). Die Werte sind an den Artefakten abgelesen.
ABI_OFFSETS = {
    "arm64": 2000,
    "armv7": 1000,
    "x86_64": 4000,
}

# Dateien, die bei JEDEM Build angefasst werden, aber kein Quellstand
# sind. local.properties enthaelt den SDK-Pfad des Rechners - der
# aendert sich bei jedem Build und wuerde jedes Artefakt als "zu alt"
# melden.
KEIN_QUELLSTAND = ("local.properties", "key.properties")


def aktuelle_version():
    text = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9.]+)\+([0-9]+)", text, re.M)
    if not m:
        return None, None
    return m.group(1), int(m.group(2))


def aapt2():
    basis = pathlib.Path(
        __import__("os").environ.get("LOCALAPPDATA", ""), "Android", "Sdk",
        "build-tools")
    if not basis.is_dir():
        return None
    kandidaten = sorted(basis.glob("*/aapt2.exe"), reverse=True)
    return kandidaten[0] if kandidaten else None


def version_code(aapt2_exe, pfad):
    """Die Build-Nummer aus einem APK (aapt2) oder AAB (Manifest)."""
    if pfad.suffix == ".aab":
        return version_code_aus_aab(pfad)
    try:
        ergebnis = subprocess.run(
            [str(aapt2_exe), "dump", "badging", str(pfad)],
            capture_output=True, text=True, timeout=120)
    except Exception:                                       # noqa: BLE001
        return None
    m = re.search(r"versionCode='(\d+)'", ergebnis.stdout)
    return int(m.group(1)) if m else None


def version_code_aus_aab(pfad):
    """Die Build-Nummer aus dem Manifest eines App-Bundles.

    Das Manifest eines AAB ist Protobuff (kein Binaer-XML), deshalb
    kann aapt2 es nicht lesen. Der Leser steckt in
    tool/check_release_consistency.py - dort wird er fuer genau
    diesen Zweck gepflegt.
    """
    try:
        sys.path.insert(0, str(ROOT / "tool"))
        import check_release_consistency as crs
        daten, _fehler = crs.dump_aab_manifest(pfad)
        return daten.get("versionCode") if daten else None
    except Exception:                                       # noqa: BLE001
        return None


def juengste_quell_aenderung():
    """Die juengste Aenderung am App-Quellstand: (mtime, pfad)."""
    kandidaten = []
    for ordner in ("lib", "android"):
        basis = ROOT / ordner
        if not basis.is_dir():
            continue
        for pfad in basis.rglob("*"):
            if not pfad.is_file():
                continue
            if any(teil in pfad.parts for teil in
                   (".gradle", "build", ".cxx", ".idea", ".kotlin")):
                continue
            if pfad.name in KEIN_QUELLSTAND:
                continue
            try:
                kandidaten.append((pfad.stat().st_mtime, pfad))
            except OSError:
                continue
    if not kandidaten:
        return None
    return max(kandidaten)


def marker_aus_dem_quellstand():
    """Marker, die im kompilierten Code sein MUESSTEN.

    Gesucht wird eine Fehlermeldung, die der App den aktuellen
    Quellstand beweist: eine Zeile, die es im Quelltext gibt und die
    erst mit dem letzten Stand dazugekommen ist.

    HERANGEKOMMEN wird der Text nicht geraten, sondern aus dem
    Git-Verlauf gelesen: die zuletzt hinzugefuegten Schluessel in
    lib/l10n/app_strings.dart. Ohne Git (frischer Checkout) faellt der
    Check auf die Versionsnummer zurueck.
    """
    try:
        ergebnis = subprocess.run(
            ["git", "log", "-1", "--format=%H", "--", "lib/l10n/app_strings.dart"],
            capture_output=True, text=True, cwd=str(ROOT), timeout=60)
        commit = ergebnis.stdout.strip()
        if not commit:
            return []
        ergebnis = subprocess.run(
            ["git", "show", "--format=", "--unified=0", commit,
             "--", "lib/l10n/app_strings.dart"],
            capture_output=True, text=True, cwd=str(ROOT), timeout=60)
    except Exception:                                       # noqa: BLE001
        return []

    marker = []
    for zeile in ergebnis.stdout.split("\n"):
        if not zeile.startswith("+") or zeile.startswith("+++"):
            continue
        m = re.search(r"'([a-z][a-zA-Z0-9_.]{6,})':", zeile)
        if m:
            marker.append(m.group(1))
    return marker[:6]


def main() -> int:
    print("=" * 70)
    print("AUSLIEFERUNG: passen die Artefakte zum Quellstand?")
    print("=" * 70)

    version, basis = aktuelle_version()
    if basis is None:
        print("  FEHLER: In pubspec.yaml steht keine Version der Form "
              "name+versionCode.")
        return 1
    print()
    print("  Der Quellstand: v%s (Build %d)" % (version, basis))

    ordner = RELEASES / ("v" + version)
    if not ordner.is_dir():
        print("  ! Es gibt keinen Release-Ordner %s - es konnte nichts "
              "geprueft werden." % ordner.name)
        return 1

    aapt2_exe = aapt2()
    if aapt2_exe is None:
        print("  ! aapt2 nicht gefunden - die Build-Nummern konnten nicht "
              "gelesen werden.")
        return 1

    quell = juengste_quell_aenderung()
    if quell:
        print("  Juengste Quellzeile: %s (%s)"
              % (quell[1].relative_to(ROOT).as_posix(),
                 quell[0]))

    marker = marker_aus_dem_quellstand()
    if marker:
        print("  Marker aus dem letzten Aendern der Texte: %s"
              % ", ".join(marker[:3]))

    fehler = []
    geprueft = 0

    for pfad in sorted(ordner.rglob("*.apk")) + sorted(ordner.rglob("*.aab")):
        name = pfad.name
        ist_admin = "ADMIN" in name
        erwartet = basis + (ADMIN_BUILD_OFFSET if ist_admin else 0)
        if not ist_admin:
            for stichwort, aufschlag in ABI_OFFSETS.items():
                if "-%s" % stichwort in name:
                    erwartet += aufschlag
                    break

        ist = version_code(aapt2_exe, pfad)
        geprueft += 1
        if ist is None:
            fehler.append("%s: Build-Nummer nicht lesbar" % name)
            continue

        # Der MARKER zuerst: er sagt das Wichtigste - der Build traegt
        # einen aelteren CODE. Die Build-Nummer kann zufaellig passen
        # (etwa weil sie von Hand gesetzt wurde), der Code nicht.
        if marker:
            fehlt_marker = None
            with zipfile.ZipFile(pfad) as z:
                namen = [n for n in z.namelist() if n.endswith("libapp.so")]
                if namen:
                    klein = min(namen, key=lambda n: z.getinfo(n).file_size)
                    daten = z.read(klein)
                    for m in marker:
                        if m.encode("utf-8") not in daten:
                            fehlt_marker = m
                            break
            if fehlt_marker:
                fehler.append(
                    "%s: der Text '%s' fehlt im kompilierten Code - der "
                    "Build traegt einen aelteren Stand als die Quellen"
                    % (name, fehlt_marker))
                continue

        if ist != erwartet:
            fehler.append(
                "%s: Build-Nummer %d, erwartet %d (Quellstand %d%s) - "
                "das Artefakt ist VERALDET"
                % (name, ist, erwartet, basis,
                   " + %d fuer den Admin-Build" % ADMIN_BUILD_OFFSET
                   if ist_admin else ""))
            continue

        # Frische: nach der letzten Quellzeile gebaut?
        if quell and pfad.stat().st_mtime < quell[0]:
            fehler.append(
                "%s: gebaut vor der letzten Quellzeile (%s) - der Build "
                "traegt einen aelteren Code"
                % (name, quell[1].relative_to(ROOT).as_posix()))
            continue

        print("  OK %-40s Build %d" % (name, ist))

    # Die alten Ordner: liegen dort Admin-Builds, die jemand nehmen
    # koennte?
    alte = []
    for ordner2 in sorted(RELEASES.iterdir()):
        if not ordner2.is_dir() or ordner2 == ordner:
            continue
        admin_ordner = ordner2 / "admin"
        if admin_ordner.is_dir():
            alte.extend(sorted(admin_ordner.glob("*.apk")))

    print()
    if alte:
        print("  ! %d Admin-Build(s) in anderen Release-Ordnern: %s"
              % (len(alte), ", ".join(p.name for p in alte[:3])
                 + (" ..." if len(alte) > 3 else "")))
        print("    Sie tragen eine alte Admin-UUID und sind von den "
              "aktuellen nicht zu")
        print("    unterscheiden. Vor einem Admin-Einsatz loeschen "
              "(siehe docs/BETRIEBSAUFGABEN.md).")

    print()
    if fehler:
        print("FEHLER: %d Artefakt(e) passen nicht zum Quellstand:"
              % len(fehler))
        for f in fehler:
            print("  - %s" % f)
        return 1

    if not geprueft:
        print("  ! Es gab nichts zu pruefen.")
        return 1

    print("OK: %d Artefakte passen zum Quellstand (Build %d)."
          % (geprueft, basis))
    return 0


if __name__ == "__main__":
    sys.exit(main())
