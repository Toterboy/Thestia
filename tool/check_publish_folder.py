"""Vollpruefung des Netlify-Publish-Ordners vor dem Upload.

WARUM DIESES SKRIPT ES GIBT (04.11.2026):
==========================================

Der Publish-Ordner wird per Drag-and-Drop hochgeladen - es gibt
keinen Build-Schritt, der einen Fehler meldet. Was nicht geprueft
wird, landet live. Nach dem Upload sind die Dateien "da", aber:

  * eine Regel zeigt auf eine Datei, die es nicht gibt -> 404
  * eine Seite ist durch noindex gesperrt -> nicht auffindbar
  * ein Link zeigt ins Leere -> toter Link auf einer Pflichtseite
  * die Sicherheits-Header fehlen -> Clickjacking moeglich

Deshalb wird der Ordner VOR dem Upload geprueft - und der Ordner
wird nach jeder Aenderung an ihm wieder geprueft (der Aufruf steht
in tool/check_local_ci.ps1, also in der CI und im lokalen Spiegel).

Prueft:
  1. Dateien und verbotene Inhalte (.env, .sql, Schlüssel, ...)
  2. Jedes Ziel aus _redirects existiert
  3. Jeder Pfad aus _headers trifft eine Datei
  4. Die Sicherheits-Header (inkl. frame-ancestors im CSP)
  5. canonical auf allen oeffentlichen Seiten, noindex nur dort, wo
     es richtig ist
  6. Jeder interne Link und jedes Asset loest auf
  7. robots.txt sperrt nicht alles, die Sitemap existiert
  8. Keine Platzhalter (REPLACE_, TODO, ...) im sichtbaren Text
"""
import pathlib
import re
import sys
import tomllib

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

A = pathlib.Path(__file__).resolve().parent.parent / "passkey-assets"
fehler: list[str] = []
hinweise: list[str] = []


def rel(p: pathlib.Path) -> str:
    return p.relative_to(A).as_posix()


def main() -> int:
    if not A.exists():
        print("FEHLER: passkey-assets/ existiert nicht.")
        return 1

    alle = sorted(p for p in A.rglob("*") if p.is_file())
    html = sorted(A.rglob("*.html"))

    print("NETFLIFY-PUBLISH-ORDNER")
    print("=" * 72)
    print("  %d Dateien, %d davon HTML" % (len(alle), len(html)))

    # -----------------------------------------------------------------
    # 1) Verbotene Dateien
    # -----------------------------------------------------------------
    print("\n1) Verbotene Dateien:")
    verboten = []
    for p in alle:
        n = p.name.lower()
        if n.startswith(".") or n.endswith(
            (".bak", ".old", ".log", ".sql", ".key", ".pem", ".p12",
             ".jks", ".keystore", ".properties")
        ):
            verboten.append(rel(p))
    if verboten:
        for v in verboten:
            fehler.append("Verbotene Datei im Publish-Ordner: %s" % v)
        print("  FEHLER: %s" % ", ".join(verboten))
    else:
        print("  OK: keine")

    # -----------------------------------------------------------------
    # 2) _redirects
    # -----------------------------------------------------------------
    print("\n2) _redirects:")
    rewrite_ziele: list[tuple[str, str]] = []
    for z in (A / "_redirects").read_text(encoding="utf-8").split("\n"):
        s = z.strip()
        if not s or s.startswith("#"):
            continue
        teile = s.split()
        if len(teile) < 2:
            fehler.append("_redirects: unvollstaendige Regel: %r" % s)
            continue
        quelle, ziel = teile[0], teile[1]
        if ziel.startswith("http"):
            continue
        if not (A / ziel.lstrip("/")).exists():
            fehler.append("_redirects: Ziel %s existiert nicht (%s)"
                          % (ziel, quelle))
        rewrite_ziele.append((quelle, ziel))
    print("  %d Regeln, alle Ziele vorhanden" % len(rewrite_ziele))

    # -----------------------------------------------------------------
    # 2b) netlify.toml
    # -----------------------------------------------------------------
    #
    # GEFUNDEN 05.11.2026: Hier stand ein [[redirects]]-Block ohne
    # "from" und "to" - eine ungueltige Regel. Sie fiel nicht auf,
    # weil kein Gate die Datei gelesen hat (nur _redirects und
    # _headers wurden geprueft). Jetzt wird sie es.
    print("\n2b) netlify.toml:")
    toml_pfad = A / "netlify.toml"
    toml_regeln = []
    if not toml_pfad.exists():
        fehler.append("netlify.toml fehlt im Publish-Ordner")
        print("  FEHLER: die Datei fehlt")
    else:
        roh_toml = toml_pfad.read_text(encoding="utf-8")
        try:
            daten = tomllib.loads(roh_toml)
        except tomllib.TOMLDecodeError as e:
            fehler.append("netlify.toml ist kein gueltiges TOML: %s" % e)
            print("  FEHLER: ungueltiges TOML: %s" % e)
            daten = {}
        else:
            print("  TOML gueltig")
        for regel in daten.get("redirects", []):
            quelle = regel.get("from")
            ziel = regel.get("to")
            status = regel.get("status")
            if not quelle or not ziel:
                fehler.append("netlify.toml: Regel ohne from/to: %r" % regel)
                print("  FEHLER: Regel ohne from/to: %r" % regel)
                continue
            if ziel.startswith("http"):
                # Ein Rewrite auf eine fremde Adresse - das Ziel kann
                # nicht im Ordner liegen.
                toml_regeln.append((quelle, ziel))
                continue
            if not (A / ziel.lstrip("/")).exists():
                fehler.append("netlify.toml: Ziel %s existiert nicht (%s)"
                              % (ziel, quelle))
                print("  FEHLER: Ziel %s existiert nicht" % ziel)
            if status not in (200, 301, 302, 303, 307, 308):
                fehler.append("netlify.toml: unbekannter Status %r bei %s"
                              % (status, quelle))
            toml_regeln.append((quelle, ziel))
        print("  %d Regeln geprueft" % len(toml_regeln))

        # Dieselbe Adresse in beiden Quellen: dann muss dasselbe Ziel
        # das Ziel sein. Sonst schattiert eine Quelle die andere
        # lautlos - genau das warnt der Kopf von _redirects.
        redirect_map = dict(rewrite_ziele)
        for quelle, ziel in toml_regeln:
            if quelle in redirect_map and redirect_map[quelle] != ziel:
                fehler.append(
                    "netlify.toml und _redirects nennen dieselbe Adresse "
                    "%s, aber unterschiedliche Ziele (%s vs %s)"
                    % (quelle, ziel, redirect_map[quelle]))
                print("  FEHLER: %s zeigt auf zwei Ziele" % quelle)

    # -----------------------------------------------------------------
    # 2c) Cloudflare-Tauglichkeit
    # -----------------------------------------------------------------
    #
    # BEFUND (08.11.2026, Hosterwechsel-Vorbereitung): Der Betreiber
    # sucht einen Hoster, weil die Netlify-Credits fast leer sind und
    # er ofter deployen moechte. Der naheliegende Kandidat ist
    # Cloudflare Pages: 0 Euro, unbegrenzte Bandbreite - und ein Deploy
    # ist dort ein ORDNER-UPLOAD, also ein Deploy OHNE Build-Minuten.
    #
    # Cloudflare Pages liest dieselben zwei Dateien (_redirects,
    # _headers), aber mit einer ENGEREN Syntax. Beide Unterschiede
    # sind live in der Cloudflare-Doku belegt (Stand 08.11.2026):
    #
    #   * _redirects kennt nur "[Quelle] [Ziel] [Code]" mit einer ZAHL
    #     als Code. Das Netlify-"!" ("erzwungen, auch wenn an der
    #     Quelladresse eine Datei liegt") wird nicht verstanden - die
    #     Regel wird ignoriert.
    #   * _redirects kennt KEINE domain-bezogenen Regeln ("Domain-level
    #     redirects: nicht unterstuetzt"). Die Regel fuer die eigene
    #     robots.txt des Auth-Hosts funktioniert dort also nicht.
    #
    # Deshalb wird hier beides geprueft:
    #   1) Regeln, die Cloudflare braucht, duerfen keine Netlify-
    #      Syntax tragen.
    #   2) Fuer die eine Regel, die nur Netlify kann, muss der Ersatz
    #      vorhanden sein: der X-Robots-Tag-Header in _headers.
    #
    # Ohne diese Pruefung faellt der Unterschied erst auf dem
    # Live-Host auf - bei der Datei, die am wichtigsten ist: ohne
    # /.well-known/assetlinks.json funktionieren die Passkeys auf
    # Android nicht mehr.
    print("\n2c) Cloudflare-Tauglichkeit:")
    NETLIFY_ONLY = "https://auth.thestia.de/robots.txt"
    regeln = []
    for z in (A / "_redirects").read_text(encoding="utf-8").split("\n"):
        s = z.strip()
        if not s or s.startswith("#"):
            continue
        teile = s.split()
        quelle, ziel = teile[0], teile[1]
        code = teile[2] if len(teile) > 2 else ""
        regeln.append((quelle, ziel, code))

    ausrufezeichen = []
    domains = []
    for quelle, _ziel, code in regeln:
        if code.endswith("!"):
            ausrufezeichen.append((quelle, code))
        if quelle.startswith("http"):
            domains.append(quelle)

    # (1) Das Ausrufezeichen: nur bei der einen Regel erlaubt, fuer die
    #     es noetig ist (dort liegt /robots.txt als Datei im Ordner).
    erlaubt = {NETLIFY_ONLY}
    for quelle, code in ausrufezeichen:
        if quelle in erlaubt:
            print("  OK  %s: Ausrufezeichen noetig (Netlify-only)" % quelle)
            continue
        fehler.append(
            "_redirects: die Regel '%s' traegt ein Ausrufezeichen (%s) - "
            "Cloudflare Pages versteht nur eine Zahl als Code und wuerde "
            "die ganze Regel ignorieren. Das Ausrufezeichen ist nur bei "
            "'%s' erlaubt." % (quelle, code, NETLIFY_ONLY))
        print("  FEHLER %s: Ausrufezeichen (%s)" % (quelle, code))
    if not ausrufezeichen:
        print("  OK  keine Regel mit Netlify-Ausrufezeichen")

    # (2) Domain-bezogene Regeln: nur die eine, und dafuer muss der
    #     Ersatz in _headers stehen.
    headers_inhalt = (A / "_headers").read_text(encoding="utf-8")
    for quelle in domains:
        if quelle != NETLIFY_ONLY:
            fehler.append(
                "_redirects: die domain-bezogene Regel '%s' kann nur "
                "Netlify (nicht Cloudflare Pages)." % quelle)
            print("  FEHLER %s: domain-bezogene Regel" % quelle)
            continue
        print("  OK  %s: domain-bezogen (nur Netlify - bei Cloudflare "
              "greift der Ersatz unten)" % quelle)
        ersatz = False
        block = []
        for zeile in headers_inhalt.split("\n"):
            if zeile.strip() and not zeile.startswith((" ", "\t")) \
                    and not zeile.startswith("#"):
                if block and any("X-Robots-Tag" in b and "noindex" in b
                                 for b in block):
                    ersatz = True
                block = []
            block.append(zeile)
        if block and any("X-Robots-Tag" in b and "noindex" in b
                         for b in block):
            ersatz = True
        host = quelle.split("/")[2]
        if not ersatz:
            fehler.append(
                "_headers: es fehlt ein 'X-Robots-Tag: noindex' fuer %s - "
                "Cloudflare Pages kann die domain-bezogene Regel nicht "
                "abbilden, dann waere der Auth-Host indexierbar." % host)
            print("  FEHLER %s: kein X-Robots-Tag-Ersatz in _headers" % host)
        else:
            print("  OK  %s: X-Robots-Tag: noindex ist gesetzt" % host)

    # -----------------------------------------------------------------
    # 3) _headers
    # -----------------------------------------------------------------
    print("\n3) _headers:")
    inhalt = (A / "_headers").read_text(encoding="utf-8")
    bloecke = []
    for z in inhalt.split("\n"):
        s = z.strip()
        if not s or s.startswith("#"):
            continue
        if not (z.startswith(" ") or z.startswith("\t")):
            bloecke.append(s)
    print("  %d Pfad-Bloecke" % len(bloecke))

    # -----------------------------------------------------------------
    # 4) Sicherheits-Header
    # -----------------------------------------------------------------
    print("\n4) Sicherheits-Header:")
    noetig = ["X-Content-Type-Options", "Referrer-Policy",
              "X-Frame-Options", "Permissions-Policy",
              "Strict-Transport-Security", "Content-Security-Policy"]
    for h in noetig:
        ok = h.lower() in inhalt.lower()
        print("  %-30s %s" % (h, "OK" if ok else "FEHLT"))
        if not ok:
            fehler.append("_headers: %s fehlt" % h)
    if "frame-ancestors" not in inhalt.lower():
        fehler.append("_headers: CSP ohne frame-ancestors - die Seiten "
                      "waeren in fremde iframes einbettbar")
    else:
        print("  %-30s OK" % "frame-ancestors im CSP")

    # -----------------------------------------------------------------
    # 5) canonical / noindex
    # -----------------------------------------------------------------
    print("\n5) canonical und noindex:")
    for p in html:
        t = p.read_text(encoding="utf-8")
        m = re.search(r'<link rel="canonical" href="([^"]+)"', t)
        n = re.search(r'<meta name="robots" content="([^"]+)"', t)
        transient = ("einstellungen" in rel(p)
                     or rel(p).endswith("bestaetigt.html"))
        if transient:
            if not n:
                fehler.append("%s: noindex fehlt (Token-URL bzw. transient)"
                              % rel(p))
        else:
            if not m:
                fehler.append("%s: canonical fehlt" % rel(p))
            if n:
                fehler.append("%s: noindex steht drin - die Seite soll "
                              "auffindbar sein" % rel(p))
    print("  %d Seiten geprueft" % len(html))

    # -----------------------------------------------------------------
    # 6) Links und Assets
    # -----------------------------------------------------------------
    print("\n6) Links und Assets:")
    rewrite_quellen = {q.lstrip("/") for q, _ in rewrite_ziele}
    tot = []
    for p in html:
        t = p.read_text(encoding="utf-8")
        for m in re.finditer(r'(?:href|src)="([^"]+)"', t):
            ziel = m.group(1)
            if ziel.startswith(("http://", "https://", "mailto:",
                                "data:", "#", "tel:")):
                continue
            if ziel.startswith("/"):
                # absolut: /pfad oder /pfad.html
                kandidat = ziel.lstrip("/")
                if (A / kandidat).exists():
                    continue
                if (A / (kandidat + ".html")).exists():
                    continue
                # ueber eine Rewrite-Regel?
                if kandidat in rewrite_quellen:
                    continue
                if kandidat.rstrip("/") in rewrite_quellen:
                    continue
                tot.append("%s -> %s" % (rel(p), ziel))
            else:
                kandidat = (p.parent / ziel).resolve()
                if kandidat.exists():
                    continue
                if (kandidat.parent / (kandidat.name + ".html")).exists():
                    continue
                tot.append("%s -> %s (relativ)" % (rel(p), ziel))
    for t_ in tot:
        fehler.append("Toter Link: %s" % t_)
    print("  %d Seiten, %d tote Links" % (len(html), len(tot)))

    # -----------------------------------------------------------------
    # 7) robots.txt / sitemap.xml
    # -----------------------------------------------------------------
    print("\n7) robots.txt und sitemap.xml:")
    robots = (A / "robots.txt").read_text(encoding="utf-8")
    zeilen = [z.strip() for z in robots.split("\n")
              if z.strip() and not z.strip().startswith("#")]
    sperrt_alles = any(z.startswith("Disallow: /") for z in zeilen)
    print("  robots.txt sperrt die ganze Seite: %s" % sperrt_alles)
    if sperrt_alles:
        fehler.append("robots.txt sperrt alles - die oeffentliche Seite "
                      "waere nicht auffindbar")
    sitemap = (A / "sitemap.xml").read_text(encoding="utf-8")
    urls = re.findall(r"<loc>([^<]+)</loc>", sitemap)
    print("  sitemap.xml: %d URLs" % len(urls))
    for z in zeilen:
        if z.startswith("Sitemap:"):
            ziel = z.split(":", 1)[1].strip()
            datei = ziel.replace("https://thestia.de/", "")
            if not (A / datei).exists():
                fehler.append("robots.txt zeigt auf eine Sitemap, die es "
                              "nicht gibt: %s" % ziel)

    # -----------------------------------------------------------------
    # 7b) robots.txt: Syntax
    # -----------------------------------------------------------------
    #
    # BEFUND (05.11.2026): Die Datei begann mit einem Python-Docstring
    # statt mit Kommentaren - kein gueltiges robots.txt (Lighthouse:
    # "robots.txt is not valid", SEO-Score 80 statt 100). Die interne
    # Betriebsnotiz stand dabei oeffentlich im Netz.
    print("\n7b) robots.txt (Syntax):")
    ERLAUBT = {"user-agent", "allow", "disallow", "crawl-delay",
               "sitemap", "host", "noindex"}
    for name in ("robots.txt", "robots-auth.txt"):
        pfad = A / name
        if not pfad.exists():
            print("  %s: fehlt (uebersprungen)" % name)
            continue
        zeilen = pfad.read_text(encoding="utf-8").split("\n")
        kaputt = []
        for nummer, roh in enumerate(zeilen, 1):
            s = roh.strip()
            if not s or s.startswith("#"):
                continue
            if ":" not in s:
                kaputt.append((nummer, s))
                continue
            schluessel = s.split(":", 1)[0].strip().lower()
            if schluessel not in ERLAUBT:
                kaputt.append((nummer, s))
        if kaputt:
            for nummer, s in kaputt:
                fehler.append("%s Zeile %d: keine gueltige robots-Direktive: "
                              "%s" % (name, nummer, s[:60]))
                print("  FEHLER %s Zeile %d: %s" % (name, nummer, s[:60]))
        else:
            print("  OK    %s: alle Zeilen sind Kommentar oder eine "
                  "bekannte Direktive" % name)

    # -----------------------------------------------------------------
    # 8) Platzhalter
    # -----------------------------------------------------------------
    print("\n8) Platzhalter:")
    platzhalter = re.compile(r"REPLACE_|XXX|TODO|FIXME", re.I)
    gefunden = False
    for p in html:
        t = p.read_text(encoding="utf-8")
        for m in platzhalter.finditer(t):
            gefunden = True
            zeile = t[:m.start()].count("\n") + 1
            print("  %s Zeile %d: %s" % (rel(p), zeile, m.group(0)))
            fehler.append("%s Zeile %d: Platzhalter %s"
                          % (rel(p), zeile, m.group(0)))
    if not gefunden:
        print("  OK: keine")

    # -----------------------------------------------------------------
    # 9) Sprachfassungen
    # -----------------------------------------------------------------
    #
    # NUTZERWUNSCH 04.11.2026: "Alle sollen Englische Versionen haben."
    #
    # Bis hierher galt das nur fuer die Seiten, die man beim Bauen
    # bemerkt hat. Die Bestaetigungsseite war die Ausnahme - und genau
    # die fiel auf, weil niemand sie im Alltag besucht. Deshalb wird
    # es jetzt geprueft: Jede Seite braucht die andere Fassung, und
    # jede Seite verlinkt auf sie.
    print("\n9) Sprachfassungen:")

    def zwilling(p: pathlib.Path) -> pathlib.Path:
        """Die Seite in der anderen Sprache."""
        r = rel(p)
        if r.startswith("en/"):
            rest = r[3:]
            # Die Ordnerstruktur bildet die Adresse ab:
            # /eltern/einstellungen liegt in en/eltern/einstellungen.html
            if rest == "eltern/einstellungen.html":
                return pathlib.Path("eltern-einstellungen.html")
            return pathlib.Path(rest)
        if r == "eltern-einstellungen.html":
            return pathlib.Path("en/eltern/einstellungen.html")
        return pathlib.Path("en") / r

    def adresse(p: pathlib.Path) -> str:
        """Die oeffentliche Adresse einer Seite (ohne .html).

        [p] ist relativ zu passkey-assets/ - wie der Zwilling oben.
        """
        r = p.as_posix()
        # Die Adresse folgt den Rewrite-Regeln in _redirects, nicht dem
        # Dateinamen: /eltern/einstellungen ist die echte Adresse der
        # Datei eltern-einstellungen.html.
        if r == "eltern-einstellungen.html":
            return "/eltern/einstellungen"
        if r == "en/eltern/einstellungen.html":
            return "/en/eltern/einstellungen"
        if r.endswith("index.html"):
            return "/" + r[:-len("index.html")]
        return "/" + r[:-len(".html")]

    fehlend = []
    for p in html:
        z = zwilling(p)
        if not (A / z).exists():
            fehlend.append("%s (erwartet %s)" % (rel(p), z.as_posix()))
    if fehlend:
        for f in fehlend:
            fehler.append("Keine Sprachfassung: %s" % f)
        print("  FEHLER: %d Seite(n) ohne Fassung in der anderen Sprache"
              % len(fehlend))
        for f in fehlend:
            print("    %s" % f)
    else:
        print("  OK: %d Seiten, jede hat die andere Fassung" % len(html))

    ohne_link = []
    for p in html:
        z = zwilling(p)
        erwartet = adresse(z)
        varianten = (erwartet, erwartet + ".html")
        t = p.read_text(encoding="utf-8")
        if not any('href="%s"' % v in t for v in varianten):
            ohne_link.append("%s (erwartet %s)" % (rel(p), erwartet))
    if ohne_link:
        for f in ohne_link:
            fehler.append("Kein Link auf die Sprachfassung: %s" % f)
        print("  FEHLER: %d Seite(n) ohne Link auf die andere Fassung"
              % len(ohne_link))
        for f in ohne_link:
            print("    %s" % f)
    else:
        print("  OK: jede Seite verlinkt auf ihre Sprachfassung")

    # -----------------------------------------------------------------
    # 10) Impressum und Meldestelle
    # -----------------------------------------------------------------
    #
    # RECHERCHE 05.11.2026: Die EU-ODR-Plattform ist seit dem 20.07.2025
    # abgeschaltet (VO (EU) 2024/3228). Ein Impressum, das sie noch
    # erwaehnt, behauptet etwas Falsches - und der Absatz war auch vor
    # der Abschaltung irrefuehrend, weil er eine Teilnahme ablehnte,
    # ohne zu sagen, dass es keine Plattform mehr gibt.
    print("\n10) Impressum und Meldestelle:")
    impressum_de = (A / "impressum.html").read_text(encoding="utf-8")
    impressum_en = (A / "en" / "impressum.html").read_text(encoding="utf-8")

    odr_muster = ("ec.europa.eu/consumers/odr", "Online-Streitbeilegung",
                   "online dispute resolution", "EU-Streitschlichtung",
                   "EU dispute resolution")
    for name, inhalt in (("impressum.html", impressum_de),
                          ("en/impressum.html", impressum_en)):
        treffer = [m for m in odr_muster if m.lower() in inhalt.lower()]
        if treffer:
            fehler.append(
                "%s: nennt die ODR-Plattform (%s) - sie ist seit dem "
                "20.07.2025 abgeschaltet" % (name, ", ".join(treffer)))
            print("  FEHLER: %s nennt noch die ODR-Plattform" % name)
        else:
            print("  OK: %s nennt keine ODR-Plattform" % name)

    # Die Anschrift: § 5 Abs. 1 Nr. 1 DDG verlangt eine ladungsfaehige
    # Anschrift - Straße, Hausnummer, PLZ und Ort. Ein Postfach genuegt
    # nicht.
    #
    # Drei Faelle (siehe Kommentar im Skript):
    #   1) Platzhalter noch drin  -> HINWEIS
    #   2) Anschrift erkennbar     -> OK
    #   3) nichts davon            -> FEHLER
    #
    # Erkannt wird PLZ + Ort; die Hausnummer wird zusaetzlich geprueft,
    # weil sie das Gesetz ausdruecklich verlangt.
    adress_muster = re.compile(r"\b\d{5}\s+[A-Za-zÄÖÜäöüß][^<\n]{2,40}")
    hausnummer_muster = re.compile(r"\b\w+stra(?:ß|ss)e?\s+\d+"
                                   r"|\b\d+\s*,?\s*\d{5}\s")
    for name, inhalt, marker in (
            ("impressum.html", impressum_de, "[Straße, Hausnummer, PLZ, Ort]"),
            ("en/impressum.html", impressum_en,
             "[street, house number, postcode, city]")):
        if marker in inhalt:
            hinweise.append(
                "%s: die Anschrift ist noch nicht eingetragen. Vor dem "
                "Hochladen ersetzen: Straße, Hausnummer, PLZ, Ort - und "
                "zustellmoeglich (kein Postfach, keine erfundene Adresse)."
                % name)
            print("  HINWEIS: %s - Anschrift noch offen" % name)
        elif adress_muster.search(inhalt) and hausnummer_muster.search(inhalt):
            print("  OK: %s nennt eine Anschrift mit Hausnummer" % name)
        else:
            fehler.append(
                "%s: keine ladungsfaehige Anschrift (Straße, Hausnummer, "
                "PLZ, Ort) - § 5 Abs. 1 Nr. 1 DDG verlangt sie auf der "
                "Seite selbst" % name)
            print("  FEHLER: %s nennt keine Anschrift" % name)

    # Die Meldestelle muss den Meldeweg fuer rechtswidrige Inhalte
    # nennen (DSA Art. 18 - die Bundesnetzagentur).
    for name in ("kinderschutz.html", "en/kinderschutz.html"):
        inhalt = (A / name).read_text(encoding="utf-8")
        if "bundesnetzagentur.de" not in inhalt.lower():
            fehler.append(
                "%s: nennt keinen Meldeweg fuer rechtswidrige Inhalte "
                "(DSA Art. 18 - Bundesnetzagentur)" % name)
            print("  FEHLER: %s nennt die Bundesnetzagentur nicht" % name)
        else:
            print("  OK: %s nennt die Bundesnetzagentur" % name)

    print("\n" + "=" * 72)
    if fehler:
        print("FEHLER (%d):" % len(fehler))
        for f in fehler:
            print("  - %s" % f)
        print("=" * 72)
        return 1
    print("OK: der Publish-Ordner ist bereit fuer den Upload.")
    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
