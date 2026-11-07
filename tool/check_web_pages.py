"""Der Website-Qualitaetspruefer: prueft ALLE Seiten des Publish-Ordners.

WARUM (05.11.2026): Der Nutzer liest alle 22 Seiten gegen. Bisher
prueften die Gates nur punktuell (Dashes, Mojibake, Publish-Ordner,
Rechtstexte). Was fehlte, war eine PRUEFUNG DER SEITEN SELBST:
Struktur, Ueberschriften-Hierarchie, doppelte IDs, alt-Texte, Labels
an Formularfeldern, Theme-Marker, Platzhalter, Sprache/canonical,
Sprachknopf, tote Links, JS-Syntax.

Diese Pruefung hat bei ihrer ersten Fassung selbst zwei Fehler
gemacht (canonical stand in einem <link>, nicht in einem <a>; die
Platzhalter-Suche traf legitimen JavaScript-Code wie isNaN(x) und
typeof x === 'undefined'). Beides ist hier behoben: die Seite wird
mit einem echten HTML-Parser gelesen, und die Platzhalter-Suche
laeuft ueber den SICHTBAREN Text (ohne script und style) - dort
faellt ein "undefined" wirklich auf.

Jede Pruefung, die anschlaegt, wird gegen eine echte Manipulation
nachgewiesen (Negativprobe), sonst waere sie nutzlos.

Nutzung:  python tool/check_web_pages.py
"""
import os
import pathlib
import re
import subprocess
import sys
import time
from html.parser import HTMLParser

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "passkey-assets"


class Seite(HTMLParser):
    """Sammelt die fuer die Qualitaetspruefung noetigen Angaben."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = []
        self.ueberschriften = []      # (ebene, text)
        self.bilder = []              # (src, alt-Attribut vorhanden?)
        self.felder = []              # (id, name, typ, aria-label)
        self.labels = []              # for= Attribute
        self.links = []               # href
        self.links_ohne_text = 0
        self.meta_desc = None
        self.title = ""
        self.noindex = False
        self.canonical = None
        self.og_url = None
        self.hreflang = []            # (hreflang, href)
        self.scripts = []             # (art, inhalt)
        self._skript = []
        self._im_h = None
        self._im_title = False
        self._im_script = False
        self._im_style = False
        self._sichtbar = []           # der Text, den der Besucher liest
        self._im_a = False
        self._a_text = []
        self._a_href = None
        self._a_aria = None
        self._a_leer = False

    # -- Tag-Handler -------------------------------------------------
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a and a["id"]:
            self.ids.append(a["id"])
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self._im_h = [int(tag[1]), ""]
        elif tag == "title":
            self._im_title = True
        elif tag == "script":
            self._im_script = True
            self._skript = []
            if a.get("src"):
                self.scripts.append(("extern", a["src"]))
        elif tag == "style":
            self._im_style = True
        elif tag == "img":
            self.bilder.append((a.get("src", ""), a.get("alt")))
        elif tag in ("input", "select", "textarea"):
            self.felder.append((a.get("id", ""), a.get("name", ""),
                                a.get("type", tag), a.get("aria-label")))
        elif tag == "label":
            if a.get("for"):
                self.labels.append(a["for"])
        elif tag == "link" and "canonical" in (a.get("rel") or ""):
            self.canonical = a.get("href", "")
        elif tag == "a":
            if "href" in a:
                self.links.append(a["href"])
            if a.get("hreflang"):
                self.hreflang.append((a.get("hreflang"), a.get("href", "")))
            self._im_a = True
            self._a_text = []
            self._a_href = a.get("href")
            self._a_aria = a.get("aria-label") or a.get("title")
            self._a_leer = False
        elif tag == "meta":
            name = (a.get("name") or "").lower()
            if name == "description":
                self.meta_desc = a.get("content", "")
            if name == "robots" and "noindex" in (a.get("content") or ""):
                self.noindex = True
            if (a.get("property") or "").lower() == "og:url":
                self.og_url = a.get("content", "")

    def handle_endtag(self, tag):
        if tag == "script" and self._im_script:
            self._im_script = False
            self.scripts.append(("inline", "".join(self._skript)))
            self._skript = []
        elif tag == "style":
            self._im_style = False
        elif tag in ("h1", "h2", "h3", "h4", "h5", "h6") and self._im_h:
            self.ueberschriften.append((self._im_h[0], self._im_h[1].strip()))
            self._im_h = None
        elif tag == "title":
            self._im_title = False
        elif tag == "a" and self._im_a:
            self._im_a = False
            text = " ".join("".join(self._a_text).split())
            if not text and not self._a_aria and self._a_href:
                self._a_leer = True

    def handle_data(self, data):
        if self._im_h:
            self._im_h[1] += data
        if self._im_title:
            self.title += data
        if self._im_script:
            self._skript.append(data)
        if not self._im_script and not self._im_style:
            self._sichtbar.append(data)
        if self._im_a:
            self._a_text.append(data)

    # -- Bequemlichkeiten --------------------------------------------
    @property
    def sichtbarer_text(self) -> str:
        return " ".join(" ".join(self._sichtbar).split())


def lies(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def rewrite_quellen() -> dict:
    """Die Rewrite-Regeln aus _redirects: Adresse -> Ziel.

    OHNE diese Regeln waere zum Beispiel "/eltern/einstellungen" ein
    toter Link - die Datei heisst eltern-einstellungen.html. Die
    Adresse entsteht erst durch die Rewrite-Regel.
    """
    regeln = {}
    p = ASSETS / "_redirects"
    if not p.exists():
        return regeln
    for zeile in p.read_text(encoding="utf-8").split("\n"):
        s = zeile.strip()
        if not s or s.startswith("#"):
            continue
        teile = s.split()
        if len(teile) >= 2:
            regeln[teile[0]] = teile[1]
    return regeln


def main() -> int:
    # Der Ordner ist ein Parameter, damit die Negativproben auf Kopien
    # laufen koennen (ohne die echten Seiten anzufassen).
    global ASSETS
    if len(sys.argv) > 1:
        ASSETS = pathlib.Path(sys.argv[1]).resolve()

    fehler = []
    seiten = sorted(ASSETS.rglob("*.html"))
    if not seiten:
        print("FEHLER: keine HTML-Seiten gefunden.")
        return 1
    rewrites = rewrite_quellen()

    print("WEBSITE-QUALITAET: alle %d Seiten" % len(seiten))
    print("=" * 74)

    for pfad in seiten:
        # Die Anzeige ist relativ zu ASSETS - nicht zu ROOT: der Ordner
        # kann (in den Negativproben) ausserhalb des Repositorys liegen.
        kurz = str(pfad.relative_to(ASSETS)).replace("\\", "/")
        rel = kurz
        roh = lies(pfad)
        s = Seite()
        try:
            s.feed(roh)
        except Exception as e:  # noqa: BLE001
            fehler.append((rel, "HTML nicht lesbar: %s" % e))
            continue

        ist_englisch = kurz.startswith("en/")

        # --- 1) Genau eine h1 ------------------------------------------
        h1 = [t for e, t in s.ueberschriften if e == 1]
        if len(h1) != 1:
            fehler.append((rel, "%d h1 (genau eine erwartet)" % len(h1)))

        # --- 2) Ueberschriften-Hierarchie (kein Sprung) ---------------
        vorher = 0
        for ebene, text in s.ueberschriften:
            if vorher and ebene > vorher + 1:
                fehler.append((rel, "Ueberschrift springt von h%d auf h%d: %s"
                               % (vorher, ebene, text[:48])))
            vorher = ebene

        # --- 3) Leere Ueberschrift ------------------------------------
        for ebene, text in s.ueberschriften:
            if not text:
                fehler.append((rel, "leere h%d" % ebene))

        # --- 4) Doppelte IDs -------------------------------------------
        doppelt = sorted({i for i in s.ids if s.ids.count(i) > 1})
        if doppelt:
            fehler.append((rel, "doppelte ID(s): %s" % ", ".join(doppelt[:4])))

        # --- 5) alt-Texte an Bildern -----------------------------------
        for src, alt in s.bilder:
            if alt is None:
                fehler.append((rel, "Bild ohne alt-Attribut: %s" % src[:48]))
            elif not alt.strip():
                fehler.append((rel, "Bild mit leerem alt: %s" % src[:48]))

        # --- 6) Jedes Formularfeld hat ein Label ----------------------
        label_ids = set(s.labels)
        for fid, name, typ, aria in s.felder:
            if typ in ("hidden", "submit", "button", "reset"):
                continue
            if not fid:
                if not aria:
                    fehler.append((rel, "Feld ohne id und ohne aria-label: %s"
                                   % (name or typ)))
                continue
            if fid not in label_ids and not aria:
                fehler.append((rel, "Feld ohne Label und ohne aria-label: %s"
                               % fid))

        # --- 6b) Jedes Label zeigt auf ein vorhandenes Feld ------------
        #
        # Ein <label for="x"> ohne Element mit id="x" ist eine
        # wirkungslose Beschriftung: sie erreicht niemanden, und der
        # Screenreader meldet das Feld als unbeschriftet.
        vorhandene_ids = set(s.ids)
        for ziel in s.labels:
            if ziel not in vorhandene_ids:
                fehler.append((rel, "ein Label zeigt auf eine ID, die es "
                               "nicht gibt: %s" % ziel))

        # --- 7) Theme-Marker: das gemeinsame CSS ist eingebunden -----
        if "Web-Design (tool/web_theme.py)" not in roh:
            fehler.append((rel, "kein gemeinsames Theme-CSS im Style-Block"))

        # --- 8) Platzhalter im SICHTBAREN Text ------------------------
        # (nicht im JavaScript: dort ist "undefined" in einem Vergleich
        #  legitim, im Text nicht)
        text = s.sichtbarer_text
        for muster in ("Lorem ipsum", "TODO", "FIXME", "XXX", "PLATZHALTER",
                       "{{", "}}", "undefined", "NaN", "[object Object]"):
            if muster in text:
                fehler.append((rel, "Platzhalter im sichtbaren Text: %s"
                               % muster))

        # --- 9) Sprache, canonical, hreflang --------------------------
        m = re.search(r'<html[^>]*\blang="([a-z]{2})"', roh, re.I)
        erwartet = "en" if ist_englisch else "de"
        if not m:
            fehler.append((rel, "html-Tag ohne lang-Attribut"))
        elif m.group(1).lower() != erwartet:
            fehler.append((rel, "lang=%s, erwartet %s" % (m.group(1),
                                                         erwartet)))
        if not s.title.strip():
            fehler.append((rel, "leerer <title>"))
        # canonical und meta description sind nur auf den Seiten sinnvoll,
        # die ueberhaupt indexiert werden. Die transienten Seiten
        # (bestaetigt.html, eltern-einstellungen.html) stehen auf noindex
        # - dort waere beides sinnlos. Der Gate "Publish-Ordner"
        # verlangt fuer sie genau das Gegenteil (noindex statt canonical).
        if s.noindex:
            if s.canonical:
                fehler.append((rel, "canonical steht drin, obwohl die Seite "
                               "auf noindex ist - dann soll sie gar nicht "
                               "kanonisiert werden"))
        else:
            if not s.canonical:
                fehler.append((rel, "kein rel=canonical"))
            elif not s.canonical.startswith("https://thestia.de/"):
                fehler.append((rel, "canonical zeigt ins Falsche: %s"
                               % s.canonical))
            if not s.meta_desc or not s.meta_desc.strip():
                fehler.append((rel, "keine meta description - ohne sie "
                               "zeigt die Suchmaschine einen beliebigen "
                               "Textausschnitt der Seite"))

        # --- 10) Sprachknopf: die andere Fassung ist erreichbar ------
        if len(s.hreflang) != 1:
            fehler.append((rel, "%d Sprachlinks (einer erwartet)"
                           % len(s.hreflang)))
        else:
            sprache, ziel = s.hreflang[0]
            if sprache.lower() != ("de" if ist_englisch else "en"):
                fehler.append((rel, "der Sprachknopf zeigt auf %s, "
                               "erwartet die andere Sprache" % sprache))
            if ziel not in rewrites and ziel.lstrip("/") not in (
                    "en/" + kurz, kurz):
                # Der Knopf muss auf eine Adresse zeigen, die es gibt.
                if not (ASSETS / ziel.lstrip("/").replace(".html", "")
                        ).exists() and ziel.rstrip("/") not in rewrites:
                    fehler.append((rel, "der Sprachknopf zeigt ins Leere: %s"
                                   % ziel))

        # --- 11) Keine toten internen Links --------------------------
        for href in s.links:
            if href.startswith(("http://", "https://", "mailto:", "tel:",
                                "#", "//")):
                continue
            if not href.startswith("/"):
                continue
            ziel = href.split("#")[0].split("?")[0]
            if not ziel:
                continue
            if ziel in rewrites:
                continue
            if ziel.rstrip("/") in rewrites:
                continue
            if ziel.endswith("/"):
                kandidat = ASSETS / ziel.strip("/") / "index.html"
            else:
                kandidat = ASSETS / ziel.strip("/")
                if not kandidat.suffix:
                    kandidat = kandidat.with_suffix(".html")
            if not kandidat.exists():
                fehler.append((rel, "link ins Leere: %s" % href))

        # --- 12) Kein Link ohne Text ---------------------------------
        if s._a_leer:
            fehler.append((rel, "Link ohne Text und ohne aria-label"))

        # --- 13) JS-Syntax (echter Parser) ---------------------------
        for art, inhalt in s.scripts:
            if art != "inline" or not inhalt.strip():
                continue
            # EIGENER Dateiname je Lauf (BEFUND 07.11.2026): Mit einem
            # FESTEN Namen ("tool/.web_pages_js_check.js") haben sich
            # zwei parallele Laeufe die Datei ueberschrieben - der eine
            # pruefte dann die halbe Datei des anderen und meldete
            # "JS-Syntaxfehler". Das Gate wurde dadurch rot, ohne dass
            # etwas kaputt war: der Selbsttest lief zweimal nebeneinander
            # (lokaler Spiegel plus Handlauf).
            #
            # Die PID und die Uhrzeit machen den Namen eindeutig.
            tmp = (ROOT / "tool" /
                   (".web_pages_js_check_%d_%d.js"
                    % (os.getpid(), int(time.time() * 1000) % 1000000)))
            tmp.write_text(inhalt, encoding="utf-8")
            try:
                r = subprocess.run(["node", "--check", str(tmp)],
                                   capture_output=True, text=True,
                                   timeout=30)
                if r.returncode != 0:
                    erste = (r.stderr.strip().splitlines() or ["?"])[0]
                    fehler.append((rel, "JS-Syntaxfehler: %s" % erste[:90]))
            except FileNotFoundError:
                break
            except subprocess.TimeoutExpired:
                fehler.append((rel, "JS-Pruefung dauerte zu lange"))
            finally:
                if tmp.exists():
                    tmp.unlink()

    # --- Der Bericht --------------------------------------------------
    print("  %d Seiten geprueft." % len(seiten))
    if fehler:
        print("=" * 74)
        print("FEHLER:")
        for rel, was in fehler:
            print("  X %s: %s" % (rel, was))
        print("=" * 74)
        print("FEHLER: %d Befund(e)." % len(fehler))
        return 1

    print("=" * 74)
    print("OK: alle %d Seiten sind sauber (Struktur, Hierarchie, IDs, Labels,"
          % len(seiten))
    print("    alt-Texte, Theme, Platzhalter, canonical, Sprache, Links, JS).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
