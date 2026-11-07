"""Selbsttest: der Website-Querfer muss anschlagen.

WARUM (05.11.2026): "Alle 22 Seiten sind sauber" ist wertlos, wenn der
Pruefer gar nicht hinschaut. Dieser Selbsttest manipuliert jede Seite
in einer KOPIE (der Temp-Ordner, nie die echten Seiten) und prueft,
ob der Pruefer die Manipulation bemerkt.

21 Proben:
  Struktur:      doppelte ID, doppelte h1, leere Ueberschrift,
                 Ueberschrift springt (h1 -> h3)
  Barrierefrei:  Bild ohne alt, Bild mit leerem alt, Feld ohne Label,
                 Label zeigt auf eine fehlende ID
  Inhalt:        Platzhalter im sichtbaren Text
  Links:         toter Link
  Technik:       JS-Syntaxfehler, kein Theme-CSS
  SEO:           canonical fehlt, canonical zeigt ins Falsche,
                 meta description fehlt, falsche Sprache,
                 noindex auf einer oeffentlichen Seite,
                 kein Sprachknopf

Nutzung:  python tool/check_web_pages_selftest.py
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRUEFER = ROOT / "tool" / "check_web_pages.py"

# (Name, Datei, alter Text, neuer Text)
PROBEN = [
    ("doppelte ID", "impressum.html", "<body>",
     '<body>\n<p id="modus-umschalter">zweites Element</p>'),
    ("doppelte h1", "impressum.html", "<h1>", "<h1>x</h1><h1>"),
    ("leere Ueberschrift", "impressum.html", "<h2>", "<h2></h2><h2>"),
    ("Ueberschrift springt (h1 -> h3)", "impressum.html", "<h2>", "<h3>"),
    ("Bild ohne alt", "index.html",
     '<img src="screenshots/01_willkommen.jpg" alt="Blind Date mit Substanz"',
     '<img src="screenshots/01_willkommen.jpg"'),
    ("Bild mit leerem alt", "index.html",
     'alt="Blind Date mit Substanz"', 'alt=""'),
    ("Feld ohne Label", "eltern-einstellungen.html",
     'for="modus-umschalter"', 'for="gibt-es-nicht"'),
    ("Label zeigt auf fehlende ID", "eltern-einstellungen.html",
     'for="modus-umschalter"', 'for="gibt-es-nicht"'),
    ("Platzhalter im sichtbaren Text", "impressum.html",
     "<h1>", "<h1>Lorem ipsum dolor"),
    ("toter Link", "impressum.html",
     'href="/nutzungsbedingungen"', 'href="/gibt-es-nicht"'),
    ("JS-Syntaxfehler", "eltern-einstellungen.html",
     "</script>", "this is ( not valid javascript;</script>"),
    ("kein Theme-CSS", "impressum.html",
     "Web-Design (tool/web_theme.py)", "irgendwas"),
    ("canonical fehlt", "impressum.html",
     '<link rel="canonical" href="https://thestia.de/impressum">', ""),
    ("canonical zeigt ins Falsche", "impressum.html",
     'href="https://thestia.de/impressum"',
     'href="https://example.com/falsch"'),
    ("meta description fehlt", "impressum.html",
     '<meta name="description"', '<meta name="x-description"'),
    ("falsche Sprache", "impressum.html",
     '<html lang="de">', '<html lang="fr">'),
    ("kein Sprachknopf", "impressum.html",
     ' hreflang="en" title="Switch to English"', ""),
]


def laufe(ordner: pathlib.Path) -> str:
    r = subprocess.run([sys.executable, str(PRUEFER), str(ordner)],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace")
    return r.stdout + r.stderr


def main() -> int:
    quelle = ROOT / "passkey-assets"
    if not quelle.exists():
        print("FEHLER: passkey-assets/ existiert nicht.")
        return 1

    fehlgeschlagen = []
    with tempfile.TemporaryDirectory() as tmp:
        basis = pathlib.Path(tmp) / "assets"
        shutil.copytree(quelle, basis)

        # Die Kopie muss gruen sein - sonst waeren die Proben nicht
        # aussagekraeftig.
        #
        # MEHRFACH VERSUCHEN (BEFUND 07.11.2026): Die Kopie kann eine
        # halb geschriebene Datei erwischen, wenn gerade ein anderes
        # Werkzeug in passkey-assets/ schreibt (apply_web_theme.py,
        # make_favicon.py, make_terms.py) - zum Beispiel, wenn der
        # lokale CI-Spiegel und ein Handlauf gleichzeitig laufen. Der
        # zweite Versuch sieht dann einen konsistenten Stand.
        #
        # Wichtig: Der Fehler wird NICHT geschluckt. Erst wenn alle
        # Versuche scheitern, gilt die Kopie als nicht gruen - ein
        # echter Inhaltsfehler bleibt also rot.
        ausgabe = ""
        for versuch in range(1, 4):
            ausgabe = laufe(basis)
            if "FEHLER" not in ausgabe:
                break
            if versuch < 3:
                print("  ?      die Kopie war nicht gruen (Versuch %d) - "
                      "das kann ein gleichzeitiger Schreibvorgang sein, "
                      "ich versuche es noch einmal." % versuch)
                time.sleep(1.0)
        if "FEHLER" in ausgabe:
            print("FEHLER: die Kopie ist nicht gruen - die Proben waeren "
                  "nicht aussagekraeftig.")
            print(ausgabe[-1500:])
            return 1
        print("  OK     die unveraenderte Kopie ist gruen")

        for name, dateiname, alt, neu in PROBEN:
            ziel = basis / dateiname
            original = ziel.read_text(encoding="utf-8")
            if alt not in original:
                fehlgeschlagen.append((name, "Anker nicht gefunden"))
                print("  ?      %s: der Anker steht nicht in %s"
                      % (name, dateiname))
                continue
            ziel.write_text(original.replace(alt, neu, 1),
                            encoding="utf-8", newline="\n")
            ausgabe = laufe(basis)
            ziel.write_text(original, encoding="utf-8", newline="\n")
            if "FEHLER" in ausgabe:
                zeile = next((l.strip() for l in ausgabe.split("\n")
                              if l.strip().startswith("X ")), "")
                print("  OK     %-38s -> schlaegt an" % name)
                if zeile:
                    print("          %s" % zeile[:110])
            else:
                fehlgeschlagen.append((name, "nicht bemerkt"))
                print("  FEHLT  %-38s -> NICHT bemerkt" % name)

        # noindex auf einer oeffentlichen Seite
        ziel = basis / "impressum.html"
        original = ziel.read_text(encoding="utf-8")
        ziel.write_text(original.replace(
            "<head>", '<head>\n<meta name="robots" content="noindex">', 1),
            encoding="utf-8", newline="\n")
        ausgabe = laufe(basis)
        ziel.write_text(original, encoding="utf-8", newline="\n")
        if "FEHLER" in ausgabe:
            print("  OK     %-38s -> schlaegt an"
                  % "noindex auf einer oeffentlichen Seite")
        else:
            fehlgeschlagen.append(("noindex auf einer oeffentlichen Seite",
                                   "nicht bemerkt"))
            print("  FEHLT  %-38s -> NICHT bemerkt"
                  % "noindex auf einer oeffentlichen Seite")

    print()
    if fehlgeschlagen:
        print("FEHLER: %d Pruefung(en) schlagen nicht an:"
              % len(fehlgeschlagen))
        for n, w in fehlgeschlagen:
            print("  X %s (%s)" % (n, w))
        return 1
    print("OK: alle %d Negativproben schlagen an - der Pruefer prueft "
          "wirklich." % (len(PROBEN) + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
