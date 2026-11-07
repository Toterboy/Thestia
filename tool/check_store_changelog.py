"""Prueft, ob fuer den aktuellen Build ein Store-Changelog existiert.

WARUM (07.11.2026, Betreiber: "Checken, ob alles fuer die v0.10.0
umgesetzt wurde"): Der Store zeigt den Aenderungstext anhand der
VERSION-CODE. Ohne `changelogs/<versionCode>.txt` (in beiden
Sprachen) erscheint beim Upload kein "Was ist neu" - oder der Upload
scheitert. Das ist bei jedem Versionssprung moeglich und wurde bisher
nicht geprueft.

Die Regel: Die Changelog-Datei fuer die aktuelle Build-Nummer aus
pubspec.yaml muss in de-DE und en-US existieren und nicht leer sein.
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
FASTLANE = ROOT / "fastlane" / "metadata" / "android"

# ---------------------------------------------------------------------
# Die aktuelle Build-Nummer aus pubspec.yaml
# ---------------------------------------------------------------------
pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
m = re.search(r"^version:\s*([0-9.]+)\+(\d+)", pubspec, re.M)
if not m:
    print("FEHLER: In pubspec.yaml steht keine Version der Form "
          "name+versionCode.")
    sys.exit(1)
version_name, version_code = m.group(1), m.group(2)
print("  Aktuelle Version: %s (Build %s)" % (version_name, version_code))

# ---------------------------------------------------------------------
# Die Changelogs beider Sprachen
# ---------------------------------------------------------------------
fehler = []
for sprache in ("de-DE", "en-US"):
    basis = FASTLANE / sprache / "changelogs"
    datei = basis / ("%s.txt" % version_code)
    if not datei.is_file():
        fehler.append("%s: changelogs/%s.txt fehlt" % (sprache, version_code))
        print("  X %-8s changelogs/%s.txt fehlt" % (sprache, version_code))
        continue
    inhalt = datei.read_text(encoding="utf-8").strip()
    if not inhalt:
        fehler.append("%s: changelogs/%s.txt ist leer" % (sprache, version_code))
        print("  X %-8s changelogs/%s.txt ist leer" % (sprache, version_code))
        continue
    if len(inhalt) < 40:
        fehler.append(
            "%s: changelogs/%s.txt ist zu kurz (%d Zeichen) - im Store "
            "waere kein brauchbarer Aenderungstext zu sehen"
            % (sprache, version_code, len(inhalt))
        )
        print("  X %-8s changelogs/%s.txt ist zu kurz (%d Zeichen)"
              % (sprache, version_code, len(inhalt)))
        continue
    print("  OK %-8s changelogs/%s.txt (%d Zeichen)"
          % (sprache, version_code, len(inhalt)))

if fehler:
    print()
    print("FEHLER: der Store-Text fuer Build %s fehlt:" % version_code)
    for f in fehler:
        print("  - %s" % f)
    sys.exit(1)

print()
print("OK: fuer Build %s liegt der Store-Text in beiden Sprachen vor."
      % version_code)
