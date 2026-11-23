"""Bereitet die zwei Upload-Ordner fuer Infomaniak vor.

WARUM (23.11.2026, Betreiber): "Ich kann selbst den Upload machen." Der
Umzug auf Infomaniak ist damit eine Sache des Betreibers - aber das
ZUSAMMENSTELLEN der zwei Ordner (und das richtige robots.txt im
Auth-Verzeichnis) soll nicht an einem falschen Dateinamen liegen.

DAS MACHT DIESES SKRIPT:
    1. Es kopiert den Publish-Ordner (passkey-assets) in zwei fertige
       Upload-Ordner:
           build/informaniak/thestia.de/
           build/informaniak/auth.thestia.de/
    2. In BEIDE kommt die .htaccess aus webhosting/ (die Apache-Regeln:
       HTTPS erzwingen, www auf die Haupt-Domain, die Adressen ohne
       ".html", die Sicherheits-Header).
    3. Im Auth-Ordner wird die robots.txt durch die GESPERRTE Fassung
       ersetzt (robots-auth.txt aus dem Publish-Ordner) - dort sollen die
       Maschinen nicht herumlaufen.
    4. Die Netlify-Dateien (netlify.toml, _headers, _redirects) werden
       NICHT mitgenommen: auf Apache sind sie toter Ballast, ihre Regeln
       stecken in der .htaccess.
    5. Am Ende liegt je ein ZIP daneben - damit der Upload im Panel
       per Drag & Drop geht.

AUFRUFSWEISE:
    python tool/release/bereite_upload_infomaniak.py

DANACH (im Infomaniak-Panel):
    * "Website thestia.de" -> Dateien verwalten -> build/informaniak/
      thestia.de.zip hochladen (in das Wurzelverzeichnis, ALSO DORT,
      wo die index.html liegt).
    * "Website auth.thestia.de" -> dasselbe mit auth.thestia.de.zip.

ACHTUNG PUNKT-FDATEIEN: Die .htaccess beginnt mit einem Punkt. Manche
Upload-Werkzeuge ueberspringen Punkt-Dateien. Im Zweifel ueber
SFTP/FTP hochladen (die Datei liegt im fertigen Ordner bereit).

DIE ZUGANGSDATEN braucht dieses Skript NICHT - es schreibt nur lokal.
"""
from __future__ import annotations

import pathlib
import shutil
import sys
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "pubspec.yaml").exists():
            return kandidat
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "supabase" / "migrations").is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()

#: Der Publish-Ordner (die Website selbst).
PUBLISH = ROOT / "passkey-assets"

#: Die Apache-Konfiguration.
HTACCESS = ROOT / "webhosting" / ".htaccess"

#: Wo die fertigen Ordner und ZIPs liegen.
ZIEL = ROOT / "build" / "informaniak"

#: Diese Dateien liest nur Netlify - auf Apache sind sie Ballast.
NUR_NETLIFY = ("netlify.toml", "_headers", "_redirects")

#: Die gesperrte robots.txt (im Publish-Ordner) fuer den Auth-Host.
GESPERRTE_ROBOTS = "robots-auth.txt"

#: Die beiden Ziele: (Name des Ordners, bekommt die gesperrte robots.txt)
ZIELE = (
    ("thestia.de", False),
    ("auth.thestia.de", True),
)


def _kopiere_inhalt(ordner: pathlib.Path) -> int:
    """Kopiert den Publish-Ordner (ohne die Netlify-Dateien) und zaehlt."""
    if not PUBLISH.is_dir():
        raise SystemExit(
            f"FEHLT: der Publish-Ordner {PUBLISH}\n"
            "Er entsteht aus dem Repository."
        )
    anzahl = 0
    for pfad in sorted(PUBLISH.rglob("*")):
        if not pfad.is_file():
            continue
        if pfad.name in NUR_NETLIFY:
            continue
        ziel = ordner / pfad.relative_to(PUBLISH)
        ziel.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(pfad, ziel)
        anzahl += 1
    return anzahl


def _zippe(ordner: pathlib.Path) -> pathlib.Path:
    """Packt den Ordner (alle Dateien im Wurzelverzeichnis des ZIPs)."""
    zip_pfad = ordner.parent / (ordner.name + ".zip")
    with zipfile.ZipFile(zip_pfad, "w", zipfile.ZIP_DEFLATED) as zf:
        for pfad in sorted(ordner.rglob("*")):
            if pfad.is_file():
                zf.write(pfad, pfad.relative_to(ordner).as_posix())
    return zip_pfad


def main() -> int:
    """Der Einstiegspunkt."""
    if ZIEL.exists():
        shutil.rmtree(ZIEL)
    ZIEL.mkdir(parents=True, exist_ok=True)

    if not HTACCESS.exists():
        raise SystemExit(
            f"FEHLT: {HTACCESS}\n"
            "Sie wird erzeugt mit: python tool/web/make_htaccess.py"
        )

    for name, gesperrt in ZIELE:
        ordner = ZIEL / name
        ordner.mkdir(parents=True, exist_ok=True)

        anzahl = _kopiere_inhalt(ordner)

        # DIE APACHE-REGELN: in beide Ordner (sie unterscheiden die
        # Hosts von selbst ueber RewriteCond %{HTTP_HOST}).
        shutil.copy2(HTACCESS, ordner / ".htaccess")

        if gesperrt:
            quelle = PUBLISH / GESPERRTE_ROBOTS
            if not quelle.exists():
                raise SystemExit(f"FEHLT: {quelle}")
            shutil.copy2(quelle, ordner / "robots.txt")
            print(f"  {name}: die gesperrte robots.txt liegt drin.")

        zip_pfad = _zippe(ordner)
        groesse = sum(
            f.stat().st_size for f in ordner.rglob("*") if f.is_file()
        )
        print(f"  {name}: {anzahl + 2} Dateien, {groesse // 1024} KB")
        print(f"           ZIP: {zip_pfad.relative_to(ROOT)}")

    print()
    print("FERTIG. Im Infomaniak-Panel:")
    print("  1) Website 'thestia.de'     -> ZIP 'thestia.de.zip' in das")
    print("     Wurzelverzeichnis hochladen (dort, wo die index.html liegt).")
    print("  2) Website 'auth.thestia.de' -> ZIP 'auth.thestia.de.zip'")
    print("     genauso hochladen.")
    print()
    print("DANACH (in dieser Reihenfolge):")
    print("  3) Zertifikat pruefen: https://thestia.de und")
    print("     https://auth.thestia.de muessen ohne Warnung oeffnen.")
    print("  4) Passkeys: die assetlinks.json ist bereits auf die neue")
    print("     Zertifikatskette geschrieben (23.11.2026) - mit dem")
    print("     Upload geht sie live. Nachpruefen:")
    print("       python tool/checks/check_passkey_assetlinks.py --live")
    print("  5) Live-Check: python tool/checks/check_websites_live.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
