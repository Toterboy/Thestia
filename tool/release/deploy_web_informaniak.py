"""Laedt die Website auf das klassische Webhosting (Infomaniak, CH).

WARUM DIESES SKRIPT (23.11.2026, Betreiber): "Wir koennen jetzt auf
Infomaniak umziehen von Netlify. Netlify soll aber als Fallback da
bleiben." Der Publish-Ordner ist fuer beide Wege vorbereitet - die
`_headers`/`_redirects` bleiben fuer Netlify im Ordner (Drag & Drop),
und die aus ihnen erzeugte `.htaccess` kommt nach Infomaniak.

DER WEG:
    1. Der Publish-Ordner wird geprueft (das Gate
       `check_publish_folder.py` - es schlaegt auch rot, wenn die
       `.htaccess` veraltet ist).
    2. Der Inhalt wird hochgeladen - OHNE die drei Netlify-Dateien
       (`netlify.toml`, `_headers`, `_redirects`): auf Apache sind sie
       toter Ballast, und die Regeln stecken bereits in der
       `.htaccess`.
    3. Die `.htaccess` wird danach einzeln hochgeladen (sie beginnt mit
       einem Punkt - manche SFTP-Clients ueberspringen Punkt-Dateien).
    4. Optional wird der Live-Stand geprueft
       (`check_websites_live.py --host ...`).

ZWEI HOSTS, ZWEI VERZEICHNISSE (--getrennt):
    Bei Netlify sind `thestia.de` und `auth.thestia.de` EIN Projekt -
    beide Adressen liefern dieselben Dateien, und die Seite entscheidet
    per Hostname, ob sie den Sicherheitscheck oder die Landing-Seite
    zeigt (`passkey-assets/index.html`).
    Bei Infomaniak kann der Betreiber die beiden Adressen trennen: zwei
    Websites, zwei Verzeichnisse, je ein Zertifikat. Der Inhalt ist
    derselbe (die App verlinkt die Rechtsseiten ueber
    `auth.thestia.de/...` - die muessen dort weiterhin existieren),
    aber die Verzeichnisse sind getrennt, und im Verzeichnis des
    Auth-Hosts liegt die gesperrte `robots.txt`.
    Ohne `--getrennt` wird nur ein Verzeichnis befuellt (die Variante
    "eine Website + Alias-Domain", bei der beide Hosts dasselbe
    Wurzelverzeichnis teilen).

DIE ZUGANGSDATEN: Nur aus der Umgebung, nie aus einer Datei und nie
als Parameter (die landen sonst in der Shell-History):

    $env:INFORMANIAK_HOST  = "web12.infomaniak.com"   # aus dem Panel
    $env:INFORMANIAK_USER  = "thXXXX"                 # der FTP-Benutzer
    $env:INFORMANIAK_PATH  = "/home/www/thXXXX/thestia.de/htdocs/"
    # optional, nur mit --getrennt (zwei Verzeichnisse):
    $env:INFORMANIAK_AUTH_PATH = "/home/www/thXXXX/auth.thestia.de/htdocs/"
    # optional (empfohlen - sonst fragt der Server nach dem Passwort):
    $env:INFORMANIAK_SSH_KEY = "$HOME\\.ssh\\id_ed25519"
    $env:INFORMANIAK_PORT  = "22"

    python tool/release/deploy_web_informaniak.py --dry-run
    python tool/release/deploy_web_informaniak.py
    python tool/release/deploy_web_informaniak.py --getrennt
    python tool/release/deploy_web_informaniak.py --pruefen

DER FALLBACK (Netlify): Das Projekt auf Netlify bleibt unangetastet -
der Publish-Ordner traegt die Netlify-Dateien weiterhin, und der
Upload dorthin ist ein Drag & Drop. Zurueckwechseln heisst: im DNS
(Spaceship) die A-Records wieder auf Netlify setzen. Siehe
`docs/betrieb/WEBSITE-HOSTING.md`.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

#: Die oeffentliche Adresse und der Auth-Host (beide stehen im DNS).
#:
#: DER GRUND FUER DIE KONSTANTEN: Sie sind keine Geheimnisse, und sie
#: stehen in `passkey-assets/_headers` und `_redirects` ohnehin. Der
#: Upload muss sie kennen, um den Live-Stand zu pruefen - und die
#: Zugangsdaten kommen trotzdem nur aus der Umgebung.
OEFFENTLICHER_HOST = "thestia.de"
AUTH_HOST = "auth.thestia.de"

#: Die gesperrte robots.txt (im Publish-Ordner) - sie landet im
#: Verzeichnis des Auth-Hosts als `robots.txt`.
GESPERRTE_ROBOTS = "robots-auth.txt"


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

#: Der Ordner, der hochgeladen wird (er enthaelt index.html und Co.).
PUBLISH = ROOT / "passkey-assets"

#: Die Apache-Konfiguration (wird getrennt hochgeladen - Punkt-Dateien
#: nehmen manche SFTP-Clients nicht mit).
HTACCESS = ROOT / "webhosting" / ".htaccess"

#: Diese drei Dateien liest nur Netlify. Auf dem klassischen Webhosting
#: sind sie ueberfluessig - ihre Regeln stecken in der `.htaccess`.
NUR_NETLIFY = ("netlify.toml", "_headers", "_redirects")


def _umgebung(name: str) -> str:
    wert = os.environ.get(name, "").strip()
    if not wert:
        raise SystemExit(
            f"FEHLT: ${name}\n"
            "Die Zugangsdaten kommen nur aus der Umgebung - niemals aus "
            "einer Datei und niemals als Parameter (die landen sonst in "
            "der Shell-History)."
        )
    return wert


def _hole(getrennt: bool) -> dict:
    """Liest die Zugangsdaten aus der Umgebung."""
    daten = {
        "host": _umgebung("INFORMANIAK_HOST"),
        "user": _umgebung("INFORMANIAK_USER"),
        "pfad": os.environ.get("INFORMANIAK_PATH", "").strip(),
        "auth_pfad": os.environ.get("INFORMANIAK_AUTH_PATH", "").strip(),
        "key": os.environ.get("INFORMANIAK_SSH_KEY", "").strip(),
        "port": os.environ.get("INFORMANIAK_PORT", "").strip() or "22",
        "getrennt": getrennt,
    }
    if not daten["pfad"]:
        # Der Standardpfad von Infomaniak: /home/www/<benutzer>/<website>/htdocs/
        daten["pfad"] = f"/home/www/{daten['user']}/{OEFFENTLICHER_HOST}/htdocs/"
    if not daten["pfad"].endswith("/"):
        daten["pfad"] += "/"
    # Ein eigenes Verzeichnis fuer den Auth-Host schaltet die Trennung
    # selbst ein - dann muss kein Schalter gesetzt werden.
    if daten["auth_pfad"]:
        daten["getrennt"] = True
    if daten["getrennt"] and not daten["auth_pfad"]:
        daten["auth_pfad"] = f"/home/www/{daten['user']}/{AUTH_HOST}/htdocs/"
    if daten["auth_pfad"] and not daten["auth_pfad"].endswith("/"):
        daten["auth_pfad"] += "/"
    return daten


def _ziele(daten: dict) -> list[dict]:
    """Die Verzeichnisse, die befuellt werden."""
    ziele = [
        {
            "name": OEFFENTLICHER_HOST,
            "pfad": daten["pfad"],
            # Die gesperrte robots.txt gehoert NUR in das Verzeichnis des
            # Auth-Hosts.
            "gesperrte_robots": False,
        }
    ]
    if daten["getrennt"]:
        ziele.append(
            {
                "name": AUTH_HOST,
                "pfad": daten["auth_pfad"],
                "gesperrte_robots": True,
            }
        )
    return ziele


def _publish_dateien() -> list[pathlib.Path]:
    """Alle Dateien, die hochgeladen werden (ohne die Netlify-Dateien)."""
    if not PUBLISH.is_dir():
        raise SystemExit(
            f"FEHLT: der Publish-Ordner {PUBLISH}\n"
            "Er entsteht aus dem Repository - siehe docs/betrieb/"
            "WEBSITE-HOSTING.md."
        )
    dateien = []
    for pfad in sorted(PUBLISH.rglob("*")):
        if not pfad.is_file():
            continue
        if pfad.name in NUR_NETLIFY:
            continue
        dateien.append(pfad)
    return dateien


def _gate() -> None:
    """Prueft den Publish-Ordner (bricht bei Rot ab)."""
    print("==> Pruefe den Publish-Ordner ...", flush=True)
    ergebnis = subprocess.run(
        [sys.executable, str(ROOT / "tool" / "checks" / "check_publish_folder.py")],
        cwd=str(ROOT),
    )
    if ergebnis.returncode != 0:
        raise SystemExit(
            "ABBRUCH: der Publish-Ordner ist nicht bereit (siehe oben). "
            "Der Upload wuerde eine kaputte Website ausliefern."
        )


def _rsync_befehl(daten: dict, ziel: dict, probe: bool) -> list[str]:
    """Baut den rsync-Aufruf (SSH-Key, falls angegeben)."""
    befehl = ["rsync", "-avz"]
    if probe:
        befehl.append("--dry-run")
    befehl.append("--delete")
    for name in NUR_NETLIFY:
        befehl.append(f"--exclude={name}")
    if daten["key"]:
        befehl += ["-e", f"ssh -i {daten['key']} -p {daten['port']}"]
    befehl.append(f"{PUBLISH.relative_to(ROOT).as_posix()}/")
    befehl.append(f"{daten['user']}@{daten['host']}:{ziel['pfad']}")
    return befehl


def _sftp_befehl(daten: dict, ziel: dict, dateien: list[pathlib.Path]) -> tuple[list[str], str]:
    """Baut den sftp-Aufruf (Stapeldatei) und liefert sie zurueck."""
    zeilen = [
        f"# Von dem Skript erzeugt - der Inhalt fuer {ziel['name']}.",
        f"lcd {PUBLISH.relative_to(ROOT).as_posix()}",
        f"cd {ziel['pfad']}",
    ]
    for pfad in dateien:
        ziel_datei = pfad.relative_to(PUBLISH).as_posix()
        zeilen.append(f"put {ziel_datei}")
    if ziel["gesperrte_robots"]:
        # Die gesperrte robots.txt landet im Auth-Host als robots.txt.
        zeilen.append(f"put {GESPERRTE_ROBOTS} robots.txt")
    # Die .htaccess kommt zuletzt: sie ist eine Punkt-Datei, und manche
    # SFTP-Clients ueberspringen Punkt-Dateien - einzeln geht es immer.
    #
    # WICHTIG: Im Verzeichnis des oeffentlichen Hosts bleibt die
    # normale robots.txt liegen. Der Auth-Host bekommt seine gesperrte
    # Fassung ueber die Regel in der `.htaccess` (RewriteCond auf den
    # Host) und ueber die Datei `robots.txt` oben.
    zeilen.append("lcd webhosting")
    zeilen.append("put .htaccess .htaccess")
    stapel = ROOT / "build" / f"informaniak-upload-{ziel['name']}.txt"
    stapel.parent.mkdir(parents=True, exist_ok=True)
    stapel.write_text("\n".join(zeilen) + "\n", encoding="utf-8")
    befehl = ["sftp", "-b", str(stapel)]
    if daten["key"]:
        befehl += ["-i", daten["key"]]
    befehl += ["-P", daten["port"], f"{daten['user']}@{daten['host']}"]
    return befehl, str(stapel)


def _fuehre(befehl: list[str]) -> None:
    """Fuehrt einen Befehl aus (die Ausgabe geht durch)."""
    print("  " + " ".join(befehl), flush=True)
    ergebnis = subprocess.run(befehl, cwd=str(ROOT))
    if ergebnis.returncode != 0:
        raise SystemExit(
            f"ABBRUCH: der Upload ist fehlgeschlagen (Code {ergebnis.returncode})."
        )


def _lade_hoch(daten: dict, ziel: dict, dateien: list[pathlib.Path], probe: bool) -> None:
    """Laedt ein Verzeichnis hoch (rsync, sonst sftp)."""
    if shutil.which("rsync"):
        befehl = _rsync_befehl(daten, ziel, probe)
        if probe:
            print("==> rsync (Probelauf):")
        else:
            print("==> rsync (Upload):")
        _fuehre(befehl)
        if ziel["gesperrte_robots"]:
            # Die gesperrte robots.txt als robots.txt im Auth-Host.
            quelle = PUBLISH / GESPERRTE_ROBOTS
            if not quelle.exists():
                raise SystemExit(
                    f"FEHLT: {quelle}\n"
                    "Die gesperrte robots.txt muss im Publish-Ordner liegen."
                )
            befehl_robots = [
                "rsync",
                "-avz",
                str(quelle),
                f"{daten['user']}@{daten['host']}:{ziel['pfad']}robots.txt",
            ]
            if daten["key"]:
                befehl_robots[1:1] = [
                    "-e",
                    f"ssh -i {daten['key']} -p {daten['port']}",
                ]
            if probe:
                print("==> rsync (Probelauf, die gesperrte robots.txt):")
            else:
                print("==> rsync (Upload, die gesperrte robots.txt):")
            _fuehre(befehl_robots)
        # Die .htaccess ist eine Punkt-Datei - rsync nimmt sie mit, aber
        # sie wird zuletzt geschrieben, damit sie nie halb da ist.
        print("==> die .htaccess (Apache-Konfiguration):")
        _fuehre(
            [
                "rsync",
                "-avz",
                str(HTACCESS),
                f"{daten['user']}@{daten['host']}:{ziel['pfad']}.htaccess",
            ]
        )
        return

    befehl, stapel = _sftp_befehl(daten, ziel, dateien)
    if probe:
        print("==> sftp (Probelauf) - der Befehl waere:")
        print("  " + " ".join(befehl))
        print("  die Stapeldatei enthaelt:")
        print(pathlib.Path(stapel).read_text(encoding="utf-8"))
        return
    print("==> sftp (Upload) - Hinweis: sftp kennt kein --delete;")
    print("    Dateien, die auf dem Server nicht mehr existieren, bleiben")
    print("    dort liegen. Das ist bei dieser Website unkritisch (die")
    print("    Dateinamen aendern sich selten) - bei Bedarf im Panel")
    print("    aufraeumen.")
    _fuehre(befehl)


def main() -> int:
    """Der Einstiegspunkt."""
    parser = argparse.ArgumentParser(
        description="Laedt die Website auf das Infomaniak-Webhosting.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Nur zeigen, was passieren wuerde (nichts hochladen).",
    )
    parser.add_argument(
        "--getrennt",
        action="store_true",
        help=(
            "Zwei Verzeichnisse befuellen: eines fuer thestia.de und "
            "eines fuer auth.thestia.de (zwei Websites bei Infomaniak)."
        ),
    )
    parser.add_argument(
        "--pruefen",
        action="store_true",
        help="Nach dem Upload den Live-Stand pruefen.",
    )
    args = parser.parse_args()

    daten = _hole(args.getrennt)
    dateien = _publish_dateien()
    ziele = _ziele(daten)
    _gate()

    print("==> Ziele:")
    print(f"    Host:      {daten['host']}:{daten['port']}")
    print(f"    Benutzer:  {daten['user']}")
    for ziel in ziele:
        print(f"    {ziel['name']}: {ziel['pfad']}")
    print(f"    Dateien:   {len(dateien)} (ohne die Netlify-Dateien)")
    print()

    for ziel in ziele:
        print(f"==> {ziel['name']}")
        _lade_hoch(daten, ziel, dateien, args.dry_run)
        print()

    if args.pruefen:
        print("==> Pruefe den Live-Stand ...", flush=True)
        befehl = [
            sys.executable,
            str(ROOT / "tool" / "checks" / "check_websites_live.py"),
        ]
        for ziel in ziele:
            befehl += ["--host", f"https://{ziel['name']}"]
        ergebnis = subprocess.run(befehl, cwd=str(ROOT))
        if ergebnis.returncode != 0:
            print(
                "HINWEIS: der Live-Stand ist noch nicht in Ordnung - siehe "
                "oben. Das kann am Cache des Servers liegen; der zweite "
                "Blick (nach ein paar Minuten) entscheidet."
            )

    print()
    print("FERTIG. Netlify bleibt als Fallback unangetastet - der")
    print("Publish-Ordner traegt die Netlify-Dateien weiterhin.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
