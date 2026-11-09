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
    python tool/check_websites_live.py --host https://beispiel.pages.dev

WAS DER AUFZUG-PRUEFER KANN (08.11.2026): Mit "--host" laesst sich
  jeder weitere Host pruefen - etwa das Cloudflare-Pages-Projekt, auf
  das der Publish-Ordner vor dem DNS-Umstellen hochgeladen wird. So
laesst sich der Wechsel pruefen, BEVOR thestia.de auf den neuen
Hoster zeigt (der alte Stand bleibt dann unangetastet).
"""
import argparse
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
    parser = argparse.ArgumentParser(
        description="Prueft die LIVE-Websites (beide Domains).")
    parser.add_argument(
        "--host", action="append", default=[], metavar="URL",
        help="Ein weiterer Host, der geprueft werden soll (z. B. das "
             "Cloudflare-Pages-Projekt vor dem DNS-Umstellen).")
    args = parser.parse_args()

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
    fehler = pruefe_header("https://thestia.de", fehler)

    print()
    print("  ===== Die Passkey-Datei (Android-App-Links) =====")
    fehler = pruefe_assetlinks_identisch("https://thestia.de", fehler)
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
    fehler += pruefe_zusatzhosts(args.host)
    print()
    print("  ===== Der Auth-Host: nicht indexierbar =====")
    #
    # BEFUND (08.11.2026): Bei Netlify sperrt eine domain-bezogene
    # Regel in _redirects die robots.txt des Auth-Hosts. Cloudflare
    # Pages kann solche Regeln nicht - dort muss der Header
    # "X-Robots-Tag: noindex" die Sperre uebernehmen (die Datei
    # _headers setzt ihn fuer https://auth.thestia.de/*).
    #
    # BEFUND (09.11.2026): Netlify wertet in `_headers` NUR PFADE aus
    # - eine regel mit einer absoluten URL (`https://auth.thestia.de/*`)
    # wird ignoriert. (Die Cloudflare-Doku sagt das Gegenteil, und
    # dort stimmt es auch.) Der Header kam deshalb bei Netlify nie an -
    # was als "Deploy zu alt" aussah, war ein Mechanics-Unterschied.
    #
    # DER PRUEFUNG: Der Auth-Host muss NICHT INDEXIERBAR sein. Das
    # kann auf zwei Wegen erreicht werden, und welcher gilt, haengt
    # vom Hoster ab. Deshalb wird beides geprueft:
    #   * der Header X-Robots-Tag: noindex (der Cloudflare-Weg), ODER
    #   * eine gesperrte robots.txt (der Netlify-Weg).
    # Nur wenn WEDER das eine NOCH das andere zutrifft, ist es ein
    # Fehler.
    code, _, kopf = hole("https://auth.thestia.de/")
    tag = {k.lower(): v for k, v in kopf.items()}.get("x-robots-tag", "")
    header_ok = "noindex" in tag.lower()

    robots_code, robots_body, _ = hole("https://auth.thestia.de/robots.txt")
    robots_text = robots_body.decode("utf-8", "replace")
    gueltig = [z.strip() for z in robots_text.splitlines()
               if z.strip() and not z.strip().startswith("#")]
    gesperrt = any(z.startswith("Disallow:") for z in gueltig)

    if header_ok:
        print("    OK  https://auth.thestia.de liefert X-Robots-Tag: %s"
              % tag)
    elif gesperrt and robots_code == 200:
        print("    OK  https://auth.thestia.de/robots.txt sperrt "
              "(Disallow) - der Sicherheitscheck ist nicht indexierbar")
    else:
        print("    X  https://auth.thestia.de ist indexierbar: weder "
              "X-Robots-Tag: noindex noch eine gesperrte robots.txt")
        fehler += 1

    print()
    if fehler:
        print("FEHLER: %d Punkt(e) - die Websites sind NICHT fehlerfrei."
              % fehler)
        return 1
    print("OK: die Websites sind fehlerfrei.")
    return 0


SICHERHEITS_HEADER = {
    "x-content-type-options": "nosniff",
    "referrer-policy": "strict-origin-when-cross-origin",
    "x-frame-options": "DENY",
    "permissions-policy": "geolocation=()",
    "strict-transport-security": "max-age=",
    "content-security-policy": "frame-ancestors",
}


def pruefe_header(domain: str, fehler: int) -> int:
    """Die Sicherheits-Header, die der Host tatsaechlich liefert.

    BEFUND (08.11.2026): Die Datei _headers wird beim Hochladen
    ausgewertet - aber OB sie ausgewertet wird, sieht man erst am
    Live-Host. Wird ein Hoster gewechselt, ist das die erste Frage
    (Cloudflare Pages akzeptiert _headers, aber mit eigenen Regeln
    zur Einrueckung).

    Deshalb wird hier nicht die Datei geprueft, sondern die ANTWORT
    des Servers.
    """
    print("  ===== Die Sicherheits-Header (live) =====")
    code, _, kopf = hole(domain + "/")
    if code != 200:
        print("    X  %-28s nicht erreichbar (HTTP %s)" % (domain, code))
        return fehler + 1
    klein = {k.lower(): v for k, v in kopf.items()}
    for name, muss_in in SICHERHEITS_HEADER.items():
        wert = klein.get(name)
        if wert is None:
            print("    X  %-28s %s fehlt" % (domain, name))
            fehler += 1
        elif muss_in.lower() not in wert.lower():
            print("    X  %-28s %s = %s (erwartet: %s)"
                  % (domain, name, wert[:60], muss_in))
            fehler += 1
        else:
            print("    OK  %-28s %s" % (domain, name))
    return fehler


def pruefe_assetlinks_identisch(domain: str, fehler: int) -> int:
    """Die live ausgelieferte Datei muss der im Ordner entsprechen.

    BEFUND (08.11.2026): Die Datei assetlinks.json im Publish-Ordner
    nennt die Fingerabdruecke, gegen die Android die Zertifikatskette
    des Webservers prueft. Ein veralteter Deploy liefert die alte
    Fassung - die Passkey-Anmeldung auf Android scheitert dann, ohne
    dass irgendwo ein Fehler zu sehen ist.

    Deshalb wird hier der Inhalt verglichen, nicht nur die Syntax.
    """
    lokal = (PUBLISH / "assetlinks.json").read_bytes()
    code, koerper, _ = hole(domain + "/.well-known/assetlinks.json")
    if code != 200:
        print("    X  %-28s /.well-known/assetlinks.json -> HTTP %s"
              % (domain, code))
        return fehler + 1
    if koerper.strip() != lokal.strip():
        print("    X  %-28s die live Datei weicht vom Publish-Ordner ab - "
              "der Deploy ist aelter als das Repository" % domain)
        return fehler + 1
    print("    OK  %-28s /.well-known/assetlinks.json ist identisch mit "
          "dem Publish-Ordner" % domain)
    return fehler


def pruefe_zusatzhosts(hosts: list) -> int:
    """Prueft weitere Hosts (z. B. ein Cloudflare-Pages-Projekt).

    Der Aufruf dient dem Hosterwechsel: Der Publish-Ordner wird auf
    das neue Projekt hochgeladen und DIESES wird geprueft - solange
    thestia.de noch auf den alten Hoster zeigt. Erst wenn hier
    alles gruen ist, wird der DNS-Record umgestellt.
    """
    if not hosts:
        return 0
    fehler = 0
    for raw in hosts:
        domain = raw.strip().rstrip("/")
        if not domain.startswith("http"):
            domain = "https://" + domain
        print()
        print("  ===== %s (Zusatzhost) =====" % domain)
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
                # "/datenschutz" (die kanonische Form).
                ziel = kopf.get("Location", "")
                if ziel:
                    if ziel.startswith("/"):
                        ziel = domain + ziel
                    ziel_code, _, _ = hole(ziel)
                    if ziel_code == 200:
                        continue
                print("    X  %-42s HTTP %s -> %s (Ziel: %s)"
                      % (pfad, code, ziel, ziel_code))
                fehler += 1
                continue
            print("    X  %-42s HTTP %s" % (pfad, code))
            fehler += 1
        fehler = pruefe_header(domain, fehler)
        fehler = pruefe_assetlinks_identisch(domain, fehler)
    return fehler


if __name__ == "__main__":
    sys.exit(main())
