"""Packt den Publish-Ordner in ein Zip fuer den Upload (Drag & Drop).

WARUM ES DAS GIBT (08.11.2026, Hosterwechsel-Vorbereitung): Der
Publish-Ordner wird von Hand hochgeladen - bei Netlify ueber "Drop",
bei Cloudflare Pages ueber "Upload assets". Beide nehmen einen Ordner
ODER eine Zip-Datei entgegen.

Der Zip ist bequemer (eine Datei statt eines Ordners), aber er hat
eine Falle: Liegt im Zip ein ORDNER "passkey-assets/", dann ist das
fuer den Hoster ein Unterordner - die Startseite landet unter
/publish-assets/index.html statt unter "/", und die Website ist
kaputt. Genau das ist beim ersten Hochladen schon einmal passiert
(die .well-known-Pfade fehlten, weil Netlify Drop die Ordner mit
fuehrendem Punkt nicht mitnahm).

DESHALB macht dieses Skript das Zip so, wie der Hoster es braucht:
ALLE Dateien liegen im Zip-WURZELVERZEICHNIS. Der Inhalt ist
zeichengleich mit dem, was das Gate `check_publish_folder.py`
geprueft hat - es wird nichts hinzugefuegt, nichts entfernt, nichts
umgeschrieben.

Aufruf:
    python tool/pack_publish.py              # -> releases/publish-<zeit>.zip
    python tool/pack_publish.py --out X.zip  # -> ein bestimmter Name
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBLISH = ROOT / "passkey-assets"
OUT_DIR = ROOT / "releases"

# Diese Dateien sind Konfiguration fuer einen bestimmten Hoster. Sie
# werden mitgepackt (sie gehoeren zum Ordner, den das Gate prueft),
# aber sie sind ausdruecklich KEINE Seiten.
KONFIG = {"_headers", "_redirects", "netlify.toml"}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Packt den Publish-Ordner fuer den Upload.")
    parser.add_argument("--out", default="", help="Zieldatei (optional)")
    args = parser.parse_args()

    if not PUBLISH.is_dir():
        print("FEHLER: passkey-assets/ existiert nicht.")
        return 1

    dateien = sorted(p for p in PUBLISH.rglob("*") if p.is_file())
    if not dateien:
        print("FEHLER: der Publish-Ordner ist leer.")
        return 1

    if args.out:
        ziel = pathlib.Path(args.out)
        if not ziel.is_absolute():
            ziel = ROOT / ziel
    else:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        ziel = OUT_DIR / ("publish-%s.zip" % __import__("datetime")
                          .datetime.now().strftime("%Y%m%d-%H%M%S"))

    ziel.parent.mkdir(parents=True, exist_ok=True)

    # WICHTIG: arcname ist der Pfad RELATIV zum Publish-Ordner. Ohne
    # das enthaelt die Zip einen Ordner "passkey-assets/" - und der
    # Hoster wuerde die Seite unterhalb davon ablegen.
    with zipfile.ZipFile(ziel, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in dateien:
            rel = p.relative_to(PUBLISH).as_posix()
            zf.write(p, arcname=rel)

    groesse = ziel.stat().st_size
    with ziel.open("rb") as f:
        kette = hashlib.sha256(f.read()).hexdigest()

    print("  Das Zip ist fertig:")
    print("    Datei     : %s" % ziel)
    print("    Inhalt    : %d Dateien, %.2f MB (entpackt)"
          % (len(dateien), sum(p.stat().st_size for p in dateien)
             / 1024 / 1024))
    print("    Groesse   : %.2f MB (komprimiert)" % (groesse / 1024 / 1024))
    print("    SHA-256   : %s" % kette)
    print()
    print("    Alle Dateien liegen im Wurzelverzeichnis des Zips -")
    print("    der Hoster legt die Seite also unter \"/\" ab, nicht unter")
    print("    \"/passkey-assets/\".")
    print()
    print("    Hochladen:")
    print("      Cloudflare Pages -> Workers & Pages -> Create ->")
    print("      \"Upload assets\" -> diese Datei hier auswaehlen.")
    print("      Netlify Drop     -> https://app.netlify.com/drop")
    print()
    print("    Nach dem Hochladen pruefen:")
    print("      python tool/check_websites_live.py --host <die neue Adresse>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
