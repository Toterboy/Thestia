"""Prueft die LIVE-Websites vollstaendig - beide Domains, alle Seiten.

WARUM (08.11.2026, Betreiber): "Ist auch alles fehlerfrei bei den
Websites?"

Das Projekt-Gate `check_privacy_deployment.py` vergleicht den
Publish-Ordner mit dem Live-Stand - aber nur auf EINEM Host
(auth.thestia.de). Die oeffentliche Seite thestia.de (die im Play
Console als Privacy-Policy-URL eingetragen wird) wird dabei nicht
geprueft. Dieses Skript prueft beide Domains und ALLE Adressen, die
ueber _redirects erreichbar sind - inklusive der .well-known-Pfade,
der Favicons und der robots-Dateien.

ZWEI FEHLALARME, DIE DIESES SKRIPT NICHT MEHR MACHT (08.11.2026):
  * Umleitungen werden NICHT verfolgt. Die interne Betriebsnotiz wird
    per 301 auf /threat-model.md umgeleitet - das ist gewuellt. Ohne
    dieses Verhalten meldet urllib am Ende "200" und der Test wuerde
    eine korrekte Umleitung als Fehler ausgeben.
  * Die robots.txt wird ueber ihre GUELTIGEN Zeilen bewertet. Die
    Kommentare erwaehnen "Disallow: /" als Erklaerung; mit dem Wort im
    Text sah die Seite gesperrt aus, obwohl sie frei indexierbar ist.

Aufruf:
    python tool/check_websites_live.py
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBLISH = ROOT / "passkey-assets"

DOMAINS = ["https://thestia.de", "https://auth.thestia.de"]


class KeinFollow(urllib.request.HTTPRedirectHandler):
    """Umleitungen nicht folgen - eine 301 kann gewuellt sein."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(KeinFollow)


def hole(url, methode="GET"):
    anfrage = urllib.request.Request(
        url, method=methode, headers={"User-Agent": "thestia-pruefung"})
    try:
        with OPENER.open(anfrage, timeout=30) as antwort:
            return antwort.status, antwort.read(), dict(antwort.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)
    except Exception as e:
        return 0, str(e).encode(), {}


def lade_urls():
    """Die Adressen, die der Publish-Ordner anbietet."""
    pfade = set()
    for datei in PUBLISH.glob("*.html"):
        pfade.add("/" + datei.name)
        pfade.add("/" + datei.stem)
        pfade.add("/" + datei.stem + "/")
    for datei in (PUBLISH / "en").glob("*.html"):
        pfade.add("/en/" + datei.name)
        pfade.add("/en/" + datei.stem)
        pfade.add("/en/" + datei.stem + "/")
    pfade.update({"/", "/index.html", "/favicon.ico", "/favicon.png",
                  "/favicon.svg", "/robots.txt", "/sitemap.xml",
                  "/.well-known/assetlinks.json"})
    return sorted(pfade)


def main() -> int:
    print("=" * 74)
    print("LIVE-PRUEFUNG DER WEBSITES")
    print("=" * 74)
    print()
    fehler = 0

    for domain in DOMAINS:
        print("  ===== %s =====" % domain)
        status, _, _ = hole(domain + "/")
        print("    Startseite: HTTP %s%s" % (status, "" if status == 200
                                            else "   <-- FEHLER"))
        if status != 200:
            fehler += 1
        for pfad in lade_urls():
            code, _, kopf = hole(domain + pfad)
            if code == 200:
                continue
            if code in (301, 302, 308):
                # Eine Umleitung ist in Ordnung, wenn das ZIEL existiert.
                # Netlify macht aus "/datenschutz/" eine 301 auf
                # "/datenschutz" (die kanonische Form, ohne doppelten
                # Inhalt fuer die Suchmaschine). Das war am 08.11.2026
                # ein Fehlalarm: 26 "Fehler", die keine waren.
                ziel = kopf.get("Location", "")
                if ziel:
                    # Der Location-Header ist manchmal RELATIV ("/bestaetigt").
                    if ziel.startswith("/"):
                        ziel = domain + ziel
                    ziel_code, _, _ = hole(ziel)
                    if ziel_code == 200:
                        continue
                print("    X  %-42s HTTP %s -> %s (Ziel: %s)"
                      % (pfad, code, ziel, ziel_code))
                fehler += 1
                continue
            if domain.startswith("https://auth.") and not pfad.startswith("/robots"):
                # Der Auth-Host liefert die oeffentlichen Seiten nicht -
                # er ist die CAPTCHA-Seite. Das ist so gewollt.
                continue
            print("    X  %-42s HTTP %s" % (pfad, code))
            fehler += 1
        print()

    print("  ===== Die Pflichtinhalte (live) =====")
    pruefungen = [
        ("/impressum", "Impressum (Par. 5 DDG)"),
        ("/kinderschutz", "Kinderschutz und Meldestelle"),
        ("/konto-loeschen", "Konto-Loesch-URL (Play-Pflichtfeld)"),
        ("/datenschutz", "Datenschutzerklaerung (Play)"),
        ("/nutzungsbedingungen", "Nutzungsbedingungen (DSA Art. 16)"),
    ]
    for pfad, was in pruefungen:
        code, koerper, _ = hole("https://thestia.de" + pfad)
        text = koerper.decode("utf-8", "replace")
        if code != 200:
            print("    X  %-34s fehlt (HTTP %s)" % (was, code))
            fehler += 1
        elif "Platzhalter" in text:
            print("    X  %-34s enthaelt noch einen Platzhalter" % was)
            fehler += 1
        else:
            print("    OK %-34s ist live und gefuellt" % was)

    # Die interne Betriebsnotiz: umleiten ist gewuellt, oeffentlich nicht.
    code, _, kopf = hole("https://thestia.de/ASSETLINKS_ROOTDOMAIN.md")
    ziel = kopf.get("Location", "")
    if code in (301, 302, 308) and "threat-model" in ziel:
        print("    OK %-34s wird umgeleitet (HTTP %s -> %s)"
              % ("interne Betriebsnotiz", code, ziel))
    elif code == 200:
        print("    X  %-34s ist OEFFENTLICH (HTTP 200) - darf nicht sein!"
              % "interne Betriebsnotiz")
        fehler += 1
    else:
        print("    OK %-34s ist nicht oeffentlich (HTTP %s)"
              % ("interne Betriebsnotiz", code))

    print()
    print("  ===== Die Favicons (das Symbol in der Google-Suche) =====")
    for pfad in ("/favicon.ico", "/favicon.png", "/favicon.svg"):
        code, _, _ = hole("https://thestia.de" + pfad)
        if code == 200:
            print("    OK %-16s HTTP 200" % pfad)
        else:
            print("    X  %-16s HTTP %s - die Website zeigt ein fremdes Symbol"
                  % (pfad, code))
            fehler += 1

    print()
    print("  ===== Die Passkey-Datei (Android-App-Links) =====")
    code, koerper, _ = hole("https://thestia.de/.well-known/assetlinks.json")
    if code != 200:
        print("    X  /.well-known/assetlinks.json -> HTTP %s" % code)
        fehler += 1
    else:
        try:
            daten = json.loads(koerper)
            ziel = daten[0].get("target", {}).get("namespace", "")
            paket = daten[0].get("target", {}).get("package_name", "")
            finger = daten[0].get("target", {}).get(
                "sha256_cert_fingerprints", [])
            print("    OK  /.well-known/assetlinks.json (%d Eintraege)"
                  % len(daten))
            print("        namespace: %s | Paket: %s | Fingerabdruecke: %d"
                  % (ziel, paket, len(finger)))
            if not finger:
                print("    X  keine Fingerabdruecke - Android kann die App "
                      "nicht verknuepfen")
                fehler += 1
        except (json.JSONDecodeError, IndexError, KeyError, TypeError) as e:
            print("    X  Die Datei ist kein gueltiges JSON: %s" % e)
            fehler += 1

    print()
    print("  ===== robots.txt (der Auth-Host muss gesperrt sein) =====")
    for domain in DOMAINS:
        code, koerper, _ = hole(domain + "/robots.txt")
        # NUR die gueltigen Zeilen: die Kommentare erwaehnen "Disallow: /"
        # als Erklaerung - mit ihnen im Text sah die Sperre aus, obwohl
        # die Seite frei indexierbar ist.
        text = koerper.decode("utf-8", "replace")
        gueltig = [z.strip() for z in text.splitlines()
                   if z.strip() and not z.strip().startswith("#")]
        gesperrt = any(z.startswith("Disallow:") for z in gueltig)
        if domain.startswith("https://auth."):
            if code == 200 and gesperrt:
                print("    OK %-28s gesperrt" % domain)
            else:
                print("    X  %-28s ist NICHT gesperrt (HTTP %s)"
                      % (domain, code))
                fehler += 1
        else:
            if code == 200 and not gesperrt:
                print("    OK %-28s indexierbar" % domain)
            else:
                print("    X  %-28s ist gesperrt oder fehlt (HTTP %s) - die "
                      "oeffentliche Seite ist nicht auffindbar" % (domain, code))
                fehler += 1

    print()
    if fehler:
        print("FEHLER: %d Punkt(e) - die Websites sind NICHT fehlerfrei."
              % fehler)
        return 1
    print("OK: die Websites sind fehlerfrei.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
