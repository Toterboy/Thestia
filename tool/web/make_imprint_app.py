#!/usr/bin/env python3
"""Erzeugt den Impressum-Text fuer die App aus der Webfassung.

WARUM ES DIESES SKRIPT GIBT (20.11.2026, Betreiber): "Das Impressum in
der App funktioniert nicht."

DIE URSACHE: Die App verlinkte auf https://thestia.de/impressum. Diese
Domain ist ein VERIFIZIERTER APP-LINK (assetlinks.json, android:
autoVerify im Manifest) - Android oeffnet einen solchen Link in der App
selbst, nicht im Browser. Die App bekam also ihren eigenen Link und
zeigte nichts. Es gab keinen Browser, keine Seite und keinen Text in
der App.

DIE LOESUNG: Wie bei den Nutzungsbedingungen (14.11.2026) steht der
Text jetzt IN der App. Quelle ist die Webfassung - dieselbe Datei, die
auf thestia.de liegt. So koennen App und Website nicht auseinander-
laufen.

Das Skript liest `passkey-assets/impressum.html` und
`passkey-assets/en/impressum.html` und schreibt

    lib/generated/imprint_de.dart
    lib/generated/imprint_en.dart

Die Bloecke sind dieselben wie bei Datenschutzerklaerung und
Nutzungsbedingungen (PrivacyBlock), der Bildschirm ist derselbe
(LegalTextScreen).

Aufruf::

    python tool/web/make_imprint_app.py
"""

import html.parser
import pathlib
import re
import subprocess
import sys

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zaehlen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe aendert.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "pubspec.yaml").exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "supabase" / "migrations").is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()
GEN = ROOT / "lib" / "generated"

#: Die Webfassungen und die Dateien, die daraus entstehen.
QUELLEN = (
    ("passkey-assets/impressum.html", GEN / "imprint_de.dart", "kImprintDe"),
    ("passkey-assets/en/impressum.html", GEN / "imprint_en.dart", "kImprintEn"),
)

#: Die Bloecke, die der Bildschirm kennt.
BLOECKE = ("h1", "h2", "h3", "p", "li")


def dart_quote(s: str) -> str:
    """Dart-String-Literal (wie in make_terms_app.py).

    Dart kennt kein rohes Mehrzeilen-Literal - jeder Zeilenumbruch wird
    zu \\n im normalen String.
    """
    out = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + out + "'"


class _Parser(html.parser.HTMLParser):
    """Liest die Absaetze aus dem <main>-Bereich einer Seite."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blöcke: list[tuple[str, str]] = []
        self._art: str | None = None
        self._text: list[str] = []
        self._im_main = False
        self._link: str | None = None
        self._link_text: list[str] = []
        self._fett = 0

    # -- Hilfen ----------------------------------------------------------
    def _flush(self) -> None:
        if self._art is None:
            return
        text = _normiere("".join(self._text))
        if text:
            self.blöcke.append((self._art, text))
        self._art = None
        self._text = []

    # -- HTMLParser ------------------------------------------------------
    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag == "main":
            self._im_main = True
            return
        if not self._im_main:
            return
        if tag in BLOECKE:
            self._flush()
            self._art = tag
            self._text = []
            return
        if tag in ("strong", "b"):
            self._fett += 1
            self._text.append("**")
        elif tag == "br":
            self._text.append("\n")
        elif tag == "a":
            self._link = dict(attrs).get("href")
            self._link_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "main":
            self._flush()
            self._im_main = False
            return
        if not self._im_main:
            return
        if tag in BLOECKE:
            self._flush()
        elif tag in ("strong", "b"):
            self._fett = max(0, self._fett - 1)
            self._text.append("**")
        elif tag == "a":
            # Der Linktext steht im Text; die Adresse kommt dahinter, damit
            # der Nutzer sie im App-Text sieht und kopieren kann (in der
            # App gibt es keine klickbaren Links im Rechtstext).
            ziel = self._link or ""
            text = _normiere("".join(self._link_text))
            self._text.append(text)
            if ziel.startswith("http") and ziel.rstrip("/") != text.rstrip("/"):
                self._text.append(" (%s)" % ziel)
            self._link = None
            self._link_text = []

    def handle_data(self, data: str) -> None:
        if not self._im_main:
            return
        if self._art is None:
            return
        # Die Zeilenumbrueche im HTML-Quelltext sind weiche Umbrueche
        # (der Quelltext ist um 80 Spalten umgebrochen) - nur <br> ist
        # ein echter Umbruch. Deshalb werden sie hier zu Leerzeichen.
        data = data.replace("\n", " ")
        # Im Link wandert der Text nur in den Linkpuffer - sonst stuende
        # er doppelt im Absatz (Text und Linktext).
        if self._link is not None:
            self._link_text.append(data)
            return
        self._text.append(data)


def _normiere(text: str) -> str:
    """Zeilenumbrueche bleiben, alles andere wird zusammengefasst."""
    zeilen = []
    for zeile in text.split("\n"):
        aufgeraeumt = " ".join(zeile.split())
        if aufgeraeumt:
            zeilen.append(aufgeraeumt)
    return "\n".join(zeilen).strip()


def parse(pfad: pathlib.Path) -> list[tuple[str, str]]:
    roh = pfad.read_text(encoding="utf-8")
    parser = _Parser()
    parser.feed(roh)
    parser.close()
    return parser.blöcke


def render_dart(blöcke: list[tuple[str, str]], klasse: str, quelle: str) -> str:
    zeilen = [
        "// GENERIERTE DATEI - NICHT VON HAND AENDERN.",
        "// Quelle: %s" % quelle,
        "// Neu erzeugen mit: python tool/web/make_imprint_app.py",
        "",
        "import 'package:thestia/generated/privacy_policy_blocks.dart';",
        "",
        "/// Das Impressum als Bloecke, in der Reihenfolge der Quelle.",
        "///",
        "/// BEFUND (20.11.2026, Betreiber): \"Das Impressum in der App",
        "/// funktioniert nicht.\" thestia.de ist ein verifizierter App-Link -",
        "/// Android oeffnete den Link in der App selbst statt im Browser.",
        "/// Der Text steht deshalb jetzt im Binary, wie Datenschutz und",
        "/// Nutzungsbedingungen.",
        "const List<PrivacyBlock> %s = <PrivacyBlock>[" % klasse,
    ]
    for art, inhalt in blöcke:
        zeilen.append("  PrivacyBlock('%s', %s)," % (art, dart_quote(inhalt)))
    zeilen.append("];")
    zeilen.append("")
    return "\n".join(zeilen)


def formatiere(pfad: pathlib.Path) -> None:
    """Formatiert die erzeugte Datei (die CI prueft das Format)."""
    for befehl in ('dart format "%s"' % pfad, 'flutter format "%s"' % pfad):
        try:
            subprocess.run(
                befehl, shell=True, check=True,
                capture_output=True, text=True, encoding="utf-8",
                errors="replace",
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Dart ist nicht installiert - der Inhalt ist trotzdem
            # richtig, das Format holt der naechste Lauf nach.
            continue


def bloecke_aus_dart(text: str) -> list[tuple[str, str]]:
    """Liest die Bloecke aus einer erzeugten Dart-Datei.

    WARUM NICHT DER ROHTEXT: `dart format` bricht die Zeilen um - der
    Vergleich muss das aushalten. Deshalb werden die Bloecke gelesen
    und verglichen, nicht die Bytes.
    """
    muster = re.compile(
        r"PrivacyBlock\(\s*'([a-z0-9_]+)'\s*,\s*'((?:[^'\\]|\\.)*)'",
        re.S,
    )
    ergebnis = []
    for treffer in muster.finditer(text):
        ergebnis.append((treffer.group(1), _dart_unescape(treffer.group(2))))
    return ergebnis


def _dart_unescape(text: str) -> str:
    """Dreht die Escapes der Dart-Dateien um."""
    out = []
    index = 0
    while index < len(text):
        zeichen = text[index]
        if zeichen == "\\" and index + 1 < len(text):
            naechste = text[index + 1]
            if naechste == "n":
                out.append("\n")
            elif naechste == "'":
                out.append("'")
            elif naechste == "\\":
                out.append("\\")
            else:
                out.append(naechste)
            index += 2
            continue
        out.append(zeichen)
        index += 1
    return "".join(out)


def main() -> int:
    # Der Pruefmodus: Erzeugt den Text im Speicher und vergleicht die
    # BLOECKE mit der Datei auf der Platte. Die CI ruft ihn auf - so
    # kann die App nicht von der Webfassung abweichen, ohne dass es
    # auffaellt. (Der Vergleich ist formatunabhaengig: `dart format`
    # bricht die Zeilen um.)
    nur_pruefen = "--check" in sys.argv

    for quelle_rel, ziel, klasse in QUELLEN:
        quelle = ROOT / quelle_rel
        if not quelle.exists():
            print("FEHLER: Quelle fehlt: %s" % quelle)
            return 1
        blöcke = parse(quelle)
        if not blöcke:
            print("FEHLER: keine Bloecke in %s" % quelle)
            return 1
        inhalt = render_dart(blöcke, klasse, quelle_rel)

        if nur_pruefen:
            if not ziel.exists():
                print("FEHLER: %s fehlt - bitte erzeugen." % ziel.name)
                return 1
            vorhanden = bloecke_aus_dart(ziel.read_text(encoding="utf-8"))
            if vorhanden != blöcke:
                print(
                    "FEHLER: %s stimmt nicht mit %s ueberein.\n"
                    "        Neu erzeugen: python tool/web/make_imprint_app.py"
                    % (ziel.name, quelle_rel)
                )
                return 1
            print("%s: aktuell (%d Bloecke)" % (ziel.name, len(vorhanden)))
            continue

        ziel.parent.mkdir(parents=True, exist_ok=True)
        ziel.write_text(inhalt, encoding="utf-8")
        formatiere(ziel)
        print("%s: %d Bloecke" % (ziel.name, len(blöcke)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
