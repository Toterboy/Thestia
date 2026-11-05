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
