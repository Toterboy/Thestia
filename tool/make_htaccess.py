"""Erzeugt die Apache-Konfiguration (.htaccess) fuer das Webhosting.

WARUM ES DAS GIBT (08.11.2026): Der Betreiber hostet die Website auf
Infomaniak (Schweiz) - im Studentenprogramm ist das Webhosting
kostenlos, und es ist ein klassisches Apache-Hosting. Infomaniak
laesst mod_rewrite und .htaccess zu ("The Apache mod_rewrite module
is enabled by default on all Infomaniak infrastructures", Doku vom
08.11.2026).

Die Website hat aber zwei Konfigurationsdateien, die nur Netlify und
Cloudflare Pages lesen: `_redirects` (die Adressen ohne ".html") und
`_headers` (die Sicherheits-Header und die Cache-Regeln). Beide muss
man fuer Apache in eine `.htaccess` uebersetzen - 40 Rewrite-Regeln
und 41 Header-Bloecke. Von Hand waere das ein Fundus fuer Fehler und
ausserdem muesste es bei jeder Aenderung nachgezogen werden.

DESHALB: Dieses Skript liest die beiden Dateien und schreibt die
`.htaccess`. Die Uebersetzung sitzt an genau einer Stelle, und ein
Gate prueft, dass die erzeugte Datei zur Quelle passt
(`tool/check_publish_folder.py`).

DIE UEBERSETZUNG IM EINZELNEN:

* Regel mit Code 200  -> RewriteRule (Adresse ohne ".html" auf die
  Datei). Das Verzeichnis wird nicht mitgeschickt: Apache loest
  Rewrite-Regeln gegen den Pfad OHNE fuehrenden Schraegstrich.
* Regel mit Code 301  -> RewriteRule mit [R=301,L].
* Regel mit Host im Quellpfad (die robots.txt des Auth-Hosts) ->
  RewriteRule mit einer RewriteCond auf den Host. Genau das, was bei
  Netlify der "Host-Rewrite" macht.
* Header-Block mit Pfad "/*" -> global (jede Antwort).
* Header-Block mit einem Pfad -> SetEnvIf auf den Request-URI plus
  "env=" am Header. Das trifft dieselbe Adresse wie bei Netlify
  (dort ist es der aufgerufene Pfad, bei Apache der Dateiname).
* Header-Block mit einem HOST im Pfad -> SetEnvIf auf den Host.

Das Ergebnis liegt in `webhosting/.htaccess` - bewusst AUSSERHALB des
Publish-Ordners: Netlify und Cloudflare Pages sollen die Datei nicht
sehen (sie wuerden sie als statische Datei ausliefern). Beim Upload
auf den Hoster wird sie in das Wurzelverzeichnis kopiert.

Aufruf:
    python tool/make_htaccess.py            # schreibt webhosting/.htaccess
    python tool/make_htaccess.py --check    # nur vergleichen (Exit 1 bei Abweichung)
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBLISH = ROOT / "passkey-assets"
ZIEL = ROOT / "webhosting" / ".htaccess"

# Der Auth-Host: fuer ihn gilt die gesperrte robots.txt und er darf
# nicht indexiert werden. Bei Netlify macht das eine domain-bezogene
# Regel in _redirects, bei Cloudflare Pages der X-Robots-Tag-Header in
# _headers - bei Apache beides ueber den Host.
AUTH_HOST = "auth.thestia.de"

KOPF = """# ============================================================
# THESTIA - Apache-Konfiguration
#
# ERZEUGT von tool/make_htaccess.py aus passkey-assets/_redirects
# und passkey-assets/_headers. NICHT von Hand aendern - das naechste
# Erzeugen ueberschreibt die Datei.
#
# Vor der Aenderung an _redirects oder _headers:
#     python tool/make_htaccess.py
# und dann:
#     python tool/check_publish_folder.py
#
# Diese Datei gehoert in das WURZELVERZEICHNIS der Website (dort, wo
# index.html liegt). Sie wird nur fuer das klassische Webhosting
# gebraucht - Netlify und Cloudflare Pages lesen stattdessen
# _redirects und _headers.
# ============================================================

# Keine Verzeichnisliste, und KEIN "MultiViews": Apache soll die
# Adressen nur ueber die Regeln unten erreichen, nicht zufaellig
# ueber die Dateinamen.
Options -Indexes -MultiViews
DirectoryIndex index.html

<IfModule mod_rewrite.c>
RewriteEngine On

# --- 1) HTTPS erzwingen -------------------------------------------
# Das Zertifikat liefert der Hoster (Let's Encrypt). Der HSTS-Header
# steht weiter unten in den Headern aus _headers.
RewriteCond %{HTTPS} !=on
RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
"""


def regex_escape(text: str) -> str:
    """Maskiert die Regex-Sonderzeichen (ausser der Pfad-Sonderform).

    WICHTIG: Die Punkte MUESSEN escaped werden. Ohne Escape waere
    "^auth.thestia.de$" auch ein Treffer fuer "authXthestiaYde" - und
    "^.well-known/assetlinks.json$" wuerde auf jede Datei passen.
    """
    return re.sub(r"([.^$*+?{}\[\]|\\()])", r"\\\1", text)


def pfad_zu_regex(pfad: str) -> str:
    """Aus einem _headers-Pfad wird ein Request-URI-Muster.

    "/datenschutz"   -> ^/datenschutz(/)?(\\?|$)
    "/datenschutz/"  -> ^/datenschutz/(\\?|$)
    "/screenshots/*" -> ^/screenshots/
    "/*"             -> (global, wird nicht gebraucht)
    """
    if pfad.endswith("/*"):
        return "^" + regex_escape(pfad[:-2]) + "/"
    if pfad.endswith("/"):
        return "^" + regex_escape(pfad) + r"(\?|$)"
    return "^" + regex_escape(pfad) + r"(/)?(\?|$)"


def lies_umleitungen() -> list[tuple[str, str, str]]:
    """Die Regeln aus _redirects als (Quelle, Ziel, Code)."""
    regeln = []
    for zeile in (PUBLISH / "_redirects").read_text(encoding="utf-8").split("\n"):
        s = zeile.strip()
        if not s or s.startswith("#"):
            continue
        teile = s.split()
        quelle, ziel = teile[0], teile[1]
        code = teile[2] if len(teile) > 2 else "302"
        regeln.append((quelle, ziel, code))
    return regeln


def lies_header() -> list[tuple[str, list[tuple[str, str]]]]:
    """Die Bloecke aus _headers als (Pfad, [(Name, Wert)])."""
    bloecke: list[tuple[str, list[tuple[str, str]]]] = []
    pfad = None
    werte: list[tuple[str, str]] = []
    for zeile in (PUBLISH / "_headers").read_text(encoding="utf-8").split("\n"):
        if zeile.strip() == "" or zeile.lstrip().startswith("#"):
            continue
        if zeile.startswith((" ", "\t")):
            if pfad is not None:
                name, _, wert = zeile.strip().partition(":")
                werte.append((name.strip(), wert.strip()))
            continue
        if pfad is not None:
            bloecke.append((pfad, werte))
        pfad = zeile.strip()
        werte = []
    if pfad is not None:
        bloecke.append((pfad, werte))
    return bloecke


def baue_htaccess(publish: pathlib.Path | None = None) -> str:
    """Baut die .htaccess aus _redirects und _headers.

    Der Ordner ist ein Parameter, damit der Selbsttest mit
    synthetischen Dateien arbeiten kann - ohne die echten zu
    veraendern.
    """
    global PUBLISH
    if publish is not None:
        PUBLISH = publish
    regeln = lies_umleitungen()
    bloecke = lies_header()

    teile = [KOPF]

    # --- 2) Die Umleitungen -----------------------------------------
    teile.append("\n# --- 2) Die Adressen (aus _redirects) --------------------\n")
    host_regeln = []
    normale = []
    for quelle, ziel, code in regeln:
        if quelle.startswith("http"):
            host_regeln.append((quelle, ziel, code))
            continue
        normale.append((quelle, ziel, code))

    # Die domain-bezogene Regel zuerst (die robots.txt des Auth-Hosts),
    # damit sie nicht von einer allgemeinen Regel ueberholt wird.
    for quelle, ziel, code in host_regeln:
        host = quelle.split("/")[2]
        ziel_pfad = ziel.lstrip("/")
        teile.append(
            "# Der Auth-Host bekommt die gesperrte robots.txt (bei Netlify\n"
            "# ist das eine domain-bezogene Regel in _redirects).\n"
            "RewriteCond %%{HTTP_HOST} ^%s$ [NC]\n"
            "RewriteRule ^%s$ %s [L]\n"
            % (regex_escape(host), regex_escape(quelle.split("/", 3)[3]),
               ziel_pfad))
        teile.append("\n")

    for quelle, ziel, code in normale:
        if quelle.startswith("/"):
            muster = quelle.lstrip("/")
        else:
            muster = quelle
        ziel_pfad = ziel.lstrip("/")
        if code.startswith("301"):
            teile.append("RewriteRule ^%s$ %s [R=301,L]\n"
                         % (regex_escape(muster), ziel_pfad))
        else:
            teile.append("RewriteRule ^%s$ %s [L]\n"
                         % (regex_escape(muster), ziel_pfad))
    teile.append("</IfModule>\n")

    # --- 3) Die Bedingungen fuer die Header -------------------------
    #
    # Die globalen Bloecke (Pfad "/*") bekommen keinen env=-Filter.
    # Alles andere wird an den Request-URI oder den Host gebunden.
    globale = []
    bedingt = []
    for pfad, werte in bloecke:
        if not werte:
            continue
        if pfad == "/*":
            globale.append(werte)
        else:
            bedingt.append((pfad, werte))

    teile.append("\n# --- 3) Die Bedingungen (aus _headers) ------------------\n")
    teile.append("<IfModule mod_setenvif.c>\n")
    zaehler = 0
    bedingungs_zeilen = []
    for pfad, werte in bedingt:
        if pfad.startswith("http"):
            host = pfad.split("/")[2]
            name = "thestia_host_%d" % zaehler
            bedingungs_zeilen.append(
                'SetEnvIf Host "^%s$" %s\n' % (regex_escape(host), name))
        else:
            name = "thestia_pfad_%d" % zaehler
            bedingungs_zeilen.append(
                'SetEnvIf Request_URI "%s" %s\n' % (pfad_zu_regex(pfad), name))
        zaehler += 1
    teile.append("".join(bedingungs_zeilen))
    teile.append("</IfModule>\n")

    # --- 4) Die Header selbst ---------------------------------------
    teile.append("\n# --- 4) Die Header (aus _headers) ----------------------\n")
    teile.append("<IfModule mod_headers.c>\n")
    for werte in globale:
        for name, wert in werte:
            teile.append('Header always set %s "%s"\n' % (name, wert))
    zaehler = 0
    for pfad, werte in bedingt:
        if pfad.startswith("http"):
            name = "thestia_host_%d" % zaehler
        else:
            name = "thestia_pfad_%d" % zaehler
        for header_name, wert in werte:
            teile.append('Header always set %s "%s" env=%s\n'
                         % (header_name, wert, name))
        zaehler += 1
    teile.append("</IfModule>\n")

    teile.append("""
# --- 5) Der Auth-Host und die spaetere Web-Version --------------

# Der Auth-Host (auth.thestia.de) bekommt die gesperrte robots.txt
# (siehe Abschnitt 2) und den Header "X-Robots-Tag: noindex". Beides
# steht schon oben - der Header aus dem Block
# "https://auth.thestia.de/*" in _headers, die robots.txt aus dem
# Host-Rewrite in _redirects. Hier steht nichts mehr, damit es nicht
# auseinanderlaufen kann.

# Fuer die Web-Version der App (v0.12.0) kommt hier der
# SPA-Fallback hin: unbekannte Adressen liefern dann index.html.
# RewriteCond %%{REQUEST_FILENAME} !-f
# RewriteCond %%{REQUEST_FILENAME} !-d
# RewriteRule . /index.html [L]
""")

    return "".join(teile)


def selbsttest() -> int:
    """Prueft die Uebersetzung an synthetischen Dateien.

    WARUM (08.11.2026): Eine falsch maskierte Regel in der .htaccess
    faellt auf dem Server auf, nicht hier - und eine .htaccess, die
    zur Haelfte nicht greift, sieht im Browser wie eine kaputte
    Website aus (die Adressen ohne ".html" liefern dann 404).

    Der Test baut eine .htaccess aus zwei erfundenen Dateien und
    prueft an den Stellen nach, an denen es in der echten Datei schon
    einmal falsch war: die Punkte in den Mustern.
    """
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        ordner = pathlib.Path(tmp)
        (ordner / "_redirects").write_text(
            "# Test\n"
            "/datenschutz    /datenschutz.html  200\n"
            "/eltern/        /eltern.html  200\n"
            "https://auth.thestia.de/robots.txt  /robots-auth.txt  200!\n"
            "/intern         /threat-model.md  301\n",
            encoding="utf-8", newline="\n")
        (ordner / "_headers").write_text(
            "# Test\n"
            "/*\n"
            "  X-Frame-Options: DENY\n"
            "/datenschutz\n"
            "  Cache-Control: public, max-age=300\n"
            "https://auth.thestia.de/*\n"
            "  X-Robots-Tag: noindex\n",
            encoding="utf-8", newline="\n")
        ergebnis = baue_htaccess(ordner)

    fehler = []

    def muss(text: str) -> None:
        if text not in ergebnis:
            fehler.append(text)

    def darf_nicht(text: str) -> None:
        if text in ergebnis:
            fehler.append("darf nicht vorkommen: " + text)

    # Die Rewrite-Regeln (ohne fuehrenden Schraegstrich, Punkt escaped)
    muss("RewriteRule ^datenschutz$ datenschutz.html [L]")
    muss("RewriteRule ^eltern/$ eltern.html [L]")
    muss("RewriteRule ^intern$ threat-model.md [R=301,L]")
    # Die domain-bezogene Regel wird zu einer Host-Bedingung
    muss("RewriteCond %{HTTP_HOST} ^auth\\.thestia\\.de$ [NC]")
    muss("RewriteRule ^robots\\.txt$ robots-auth.txt [L]")
    # Die Header: global ohne Bedingung, die anderen mit
    muss('Header always set X-Frame-Options "DENY"')
    muss('SetEnvIf Request_URI "^/datenschutz(/)?(\\?|$)"')
    muss('Header always set Cache-Control "public, max-age=300" env=')
    muss('SetEnvIf Host "^auth\\.thestia\\.de$"')
    muss('Header always set X-Robots-Tag "noindex" env=')
    # Die Klammern muessen zu Ende sein
    if ergebnis.count("<IfModule") != ergebnis.count("</IfModule>"):
        fehler.append("unbalancierte IfModule-Bloecke")
    if ergebnis.count("<") != ergebnis.count(">"):
        fehler.append(" spitze Klammern unbalanciert")
    # KEINE unescaped Punkte in den Mustern
    darf_nicht("^auth.thestia.de$")
    darf_nicht("^robots.txt$")
    darf_nicht("^.well-known")

    if fehler:
        print("  Der Selbsttest ist ROT:")
        for f in fehler:
            print("    - %s" % f)
        return 1
    print("  Der Selbsttest ist gruen (die Uebersetzung stimmt).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Erzeugt die .htaccess fuer das Webhosting.")
    parser.add_argument("--check", action="store_true",
                        help="Nur vergleichen, nicht schreiben.")
    parser.add_argument("--selbsttest", action="store_true",
                        help="Prueft die Uebersetzung an Testdateien.")
    args = parser.parse_args()

    if args.selbsttest:
        return selbsttest()

    inhalt = baue_htaccess()
    alt = ZIEL.read_text(encoding="utf-8") if ZIEL.exists() else None

    if args.check:
        if alt == inhalt:
            print("OK: die .htaccess passt zu _redirects und _headers.")
            return 0
        print("FEHLER: die .htaccess weicht von _redirects/_headers ab.")
        print("  Reparieren: python tool/make_htaccess.py")
        return 1

    ZIEL.parent.mkdir(parents=True, exist_ok=True)
    ZIEL.write_text(inhalt, encoding="utf-8", newline="\n")
    zeilen = inhalt.count("\n")
    regeln = inhalt.count("RewriteRule")
    print("  Die .htaccess ist geschrieben: %s" % ZIEL)
    print("    %d Zeilen, %d Rewrite-Regeln" % (zeilen, regeln))
    return 0


if __name__ == "__main__":
    sys.exit(main())
