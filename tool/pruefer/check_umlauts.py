#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""Prueft, dass nutzersichtbare Texte echte Umlaute benutzen.

WARUM (16.11.2026, Wunsch des Betreibers): In deutschsprachigen Texten
wird haeufig "ae/oe/ue/ss" geschrieben, wenn eigentlich "ä/ö/ü/ß"
gemeint ist - "fuer" statt "fuer", "Ueberblick" statt "Ueberblick",
"muesste" statt "muesste". Das sieht nach Maschine aus und faellt in
einem deutschen Text sofort auf.

WICHTIG - die Abgrenzung: Der Quelltext dieses Projekts schreibt die
**Kommentare** bewusst in ASCII (das ist eine dokumentierte
Projektkonvention: kein Encoding-Problem in jeder Datei). Geprueft
werden deshalb ausschliesslich **nutzersichtbare** Texte:

  * die deutschen L10n-Strings (lib/l10n/app_strings.dart, Abschnitt 'de')
  * die deutsche Datenschutzerklaerung (Quelle + generierte Datei)
  * die deutschen Webseiten (passkey-assets/ ohne en/)
  * das README
  * die deutschen Store-Texte (fastlane/.../de-DE/)

Aufruf:  python tool/pruefer/check_umlauts.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zaehlen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe aendert.
def _projektwurzel() -> Path:
    for kandidat in Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()


# ---------------------------------------------------------------------------
# Die Wortliste: ASCII-Schreibweise -> richtige Schreibweise mit Umlauten.
#
# Jeder Eintrag ist (Regex, korrekte Form). Der Regex wird mit
# Wortgrenzen gesucht; Gross-/Kleinschreibung wird nicht unterschieden
# (die Form in der Meldung ist die Korrektur, nicht der Originaltext).
#
# NUR Eintraege mit hoher Trefferquote - ein Fehlalarm kostet mehr als
# ein nicht gefundener Fehler. Eigennamen, englische Woerter und
# Bezeichner stehen deshalb NICHT hier.
# ---------------------------------------------------------------------------
WORTE: list[tuple[str, str]] = [
    # --- Stammwoerter mit ae/oe/ue ------------------------------------
    (r"fuer", "für"),
    (r"ueber", "über"),
    (r"koennen", "können"),
    (r"muess(t|en|te)", "müssen"),
    (r"waehrend", "während"),
    (r"naechst(en|er|e)?", "nächst"),
    (r"zurueck", "zurück"),
    (r"moeglich", "möglich"),
    (r"hoechstens", "höchstens"),
    (r"aendern", "ändern"),
    (r"aenderung(en)?", "Änderung"),
    (r"Loeschung", "Löschung"),
    (r"loeschung", "löschung"),
    (r"Loesung", "Lösung"),
    (r"loesung", "lösung"),
    (r"Aufloesung", "Auflösung"),
    (r"bestaetig(en|t|ung)?", "bestätigen"),
    (r"Bestaetigung", "Bestätigung"),
    (r"bestaetigung", "bestätigung"),
    (r"schuetzt", "schützt"),
    (r"schuetzung", "schützung"),
    (r"Gefaehrdung", "Gefährdung"),
    (r"gefaehrlich", "gefährlich"),
    (r"Ungefaehr", "Ungefähr"),
    (r"pruef(en|t|ung)?", "prüfen"),
    (r"Pruefung", "Prüfung"),
    (r"geprueft", "geprüft"),
    (r"Pruef", "Prüf"),
    (r"Laenge", "Länge"),
    (r"laenge", "länge"),
    (r"Begruendung", "Begründung"),
    (r"begruend(en)?", "begründen"),
    (r"Erhoehung", "Erhöhung"),
    (r"erhoeht", "erhöht"),
    (r"Unterstuetzung", "Unterstützung"),
    (r"unterstuetzt", "unterstützt"),
    (r"Faehigkeit", "Fähigkeit"),
    (r"Frueh", "Früh"),
    (r"frueher", "früher"),
    (r"Fruehling", "Frühling"),
    (r"noetig", "nötig"),
    (r"Noetig", "Nötig"),
    (r"benoetigt", "benötigt"),
    (r"oeffn(en|et|t)", "öffnen"),
    (r"Oeffnung", "Öffnung"),
    (r"oeffentlich", "öffentlich"),
    (r"Oeffentlich", "Öffentlich"),
    (r"Gefuehl", "Gefühl"),
    (r"gefuehlt", "gefühlt"),
    (r"gruen", "grün"),
    (r"Gruesse", "Grüße"),
    (r"gruesse", "grüße"),
    (r"gruessen", "grüßen"),
    (r"erklaer(en|t|ung)", "erklären"),
    (r"Erklaerung", "Erklärung"),
    (r"erlaeutern", "erläutern"),
    (r"ausschliesslich", "ausschließlich"),
    (r"Ausschliesslich", "Ausschließlich"),
    (r"ausserdem", "außerdem"),
    (r"Ausserdem", "Außerdem"),
    (r"uebernimmt", "übernimmt"),
    (r"uebertrage(n|t)?", "übertragen"),
    (r"Uebertragung", "Übertragung"),
    (r"Uebersicht", "Übersicht"),
    (r"uebersicht", "übersicht"),
    (r"uebersetzen", "übersetzen"),
    (r"Uebersetzen", "Übersetzen"),
    (r"ueberhaupt", "überhaupt"),
    (r"Ueberhaupt", "Überhaupt"),
    (r"Uebrige", "Übrige"),
    (r"uebrige", "übrige"),
    (r"Ankoerpfung", "Anköpfung"),
    (r"koerperlich", "körperlich"),
    (r"Rueckfrage", "Rückfrage"),
    (r"rueckfrage", "rückfrage"),
    (r"Hoehe", "Höhe"),
    (r"hoeher", "höher"),
    (r"Puenktlich", "Pünktlich"),
    (r"spaeter", "später"),
    (r"Spaeter", "Später"),
    (r"Stueck", "Stück"),
    (r"Bruecke", "Brücke"),
    (r"Anhaenger", "Anhänger"),
    (r"Empfaenger", "Empfänger"),
    (r"Empfaengerin", "Empfängerin"),
    (r"Gehaeuse", "Gehäuse"),
    (r"geschaeft", "geschäft"),
    (r"Geschaeft", "Geschäft"),
    (r"Massnahme", "Maßnahme"),
    (r"Massnahmen", "Maßnahmen"),
    (r"Ausmass", "Ausmaß"),
    (r"Grundsaetze", "Grundsätze"),
    (r"grundsaetzlich", "grundsätzlich"),
    (r"Verfuegung", "Verfügung"),
    (r"verfuegung", "verfügung"),
    (r"Verfuegbarkeit", "Verfügbarkeit"),
    (r"Faelligkeit", "Fälligkeit"),
    (r"haeufig", "häufig"),
    (r"Haeufig", "Häufig"),
    (r"naemlich", "nämlich"),
    (r"Naemlich", "Nämlich"),
    (r"waere", "wäre"),
    (r"haette", "hätte"),
    (r"koennte", "könnte"),
    (r"duerfte", "dürfte"),
    (r"gehoert", "gehört"),
    (r"erhoert", "erhört"),
    (r"Erloes", "Erlös"),
    (r"erloes", "erlös"),
    (r"Erloese", "Erlöse"),
    (r"Vorlaeufer", "Vorgänger"),
    (r"vorlaeufer", "vorgänger"),
    (r"verstaendlich", "verständlich"),
    (r"Verstaendlich", "Verständlich"),
    (r"unverstaendlich", "unverständlich"),
    (r"eigentuemer", "Eigentümer"),
    (r"Eigentuemer", "Eigentümer"),
    (r"zuruecksetzen", "zurücksetzen"),
    (r"zurueckgegeben", "zurückgegeben"),
    (r"zurueckkommen", "zurückkommen"),
    (r"begruess(t|en)?", "begrüßen"),
    (r"Begruessung", "Begrüßung"),
    (r"anfuehren", "anführen"),
    (r"einfuehren", "einführen"),
    (r"Einfuehrung", "Einführung"),
    (r"gefuehrt", "geführt"),
    (r"gewaehlt", "gewählt"),
    (r"Gewaehlt", "Gewählt"),
    (r"verlaesst", "verlässt"),
    (r"Verlaesst", "Verlässt"),
    (r"faehrt", "fährt"),
    (r"faehren", "fahren"),
    (r"gefaehr", "gefähr"),
    (r"behoerde", "Behörde"),
    (r"Behoerde", "Behörde"),
    (r"Behoerden", "Behörden"),
    (r"staatsangehoer", "Staatsangehör"),
    (r"Gemaess", "Gemäß"),
    (r"gemaess", "gemäß"),
    (r"maessig", "mäßig"),
    (r"unmoeglich", "unmöglich"),
    (r"Unmoeglich", "Unmöglich"),
    (r"kuerzt", "kürzt"),
    (r"gekuerzt", "gekürzt"),
    (r"Kuerzel", "Kürzel"),
    (r"kuerzen", "kürzen"),
    (r"Schluessel", "Schlüssel"),
    (r"schluessel", "schlüssel"),
    (r"Schluesseln", "Schlüsseln"),
    # --- Beugung und Komposita, die im Projekt vorkommen -------------
    (r"oeffentlich(e|en|er|em|es)?", "öffentlich"),
    (r"zustaendig(e|en|er|em|es)?", "zuständig"),
    (r"unabhaengig(e|en|er|em|es)?", "unabhängig"),
    (r"Altersbeschraenkung", "Altersbeschränkung"),
    (r"Alterspruefung", "Altersprüfung"),
    (r"Massgeblich(e|en|er|es)?", "Maßgeblich"),
    (r"Minderjaehrig(en|er|te|ten)", "Minderjährig"),
    (r"zaehl(en|t|er)", "zählen"),
    (r"laeuft", "läuft"),
    (r"einschaetzen", "einschätzen"),
    (r"vollstaendig(e|en|er|es)?", "vollständig"),
    (r"Vollstaendig", "Vollständig"),
    (r"unvollstaendig", "unvollständig"),
    (r"gueltig(e|en|er|keit)?", "gültig"),
    (r"Gueltig(keit)?", "Gültig"),
    (r"Wuensche(n)?", "Wünsche"),
    (r"erwaehn(en|ung|t)", "erwähnen"),
    (r"Erwaehnung", "Erwähnung"),
    (r"ueberraschung", "Überraschung"),
    (r"erlaeuterung", "Erläuterung"),
    (r"zuverlaessig", "zuverlässig"),
    (r"laesslich", "lässlich"),
    (r"spaet(en|er|e)", "spät"),
    (r"Spaet(en|er|e)", "Spät"),
    (r"traegt", "trägt"),
    (r"Traeger", "Träger"),
    (r"betraegt", "beträgt"),
    (r"Pruef(en|t|ung|ungen|ling|bar)", "Prüf"),
    # --- Woerter mit ss statt ß --------------------------------------
    (r"schliesslich", "schließlich"),
    (r"Schliesslich", "Schließlich"),
    (r"schliesst", "schließt"),
    (r"schliessen", "schließen"),
    (r"beschliesst", "beschließt"),
    (r"beschliessen", "beschließen"),
    (r"laesst", "lässt"),
    (r"Laesst", "Lässt"),
    (r"heisst", "heißt"),
    (r"heissen", "heißen"),
    (r"weiss", "weiß"),
    (r"weisst", "weißt"),
    (r"gross", "groß"),
    (r"Grosse", "Große"),
    (r"grosse", "große"),
    (r"groesse", "Größe"),
    (r"Groesse", "Größe"),
    (r"fuenf", "fünf"),
    (r"haesslich", "hässlich"),
    (r"aengstlich", "ängstlich"),
    (r"ergoesslich", "ergötzlich"),
    (r"Strassen", "Straßen"),
    (r"Strasse", "Straße"),
    (r"Fussball", "Fußball"),
    (r"Fusspunkt", "Fußpunkt"),
    (r"Gruss", "Gruß"),
    (r"Mass", "Maß"),
    (r"Maerz", "März"),
    (r"Maerzchen", "Märzchen"),
    (r"Kaese", "Käse"),
    (r"Broetchen", "Brötchen"),
    (r"Loeffel", "Löffel"),
    (r"Hoernchen", "Hörnchen"),
    (r"schoen", "schön"),
    (r"Schoenheit", "Schönheit"),
    (r"zwoelf", "zwölf"),
    (r"Vergnuegen", "Vergnügen"),
    (r"vergnueglich", "vergnüglich"),
    (r"Aerger", "Ärger"),
    (r"aergern", "ärgern"),
]

# Die Muster werden einmal kompiliert (Wortgrenzen + Gross/Klein egal).
MUSTER = [
    (re.compile(r"\b" + muster + r"\b", re.IGNORECASE), korrekt)
    for muster, korrekt in WORTE
]

# ---------------------------------------------------------------------------
# Ausnahmen: Woerter, die ASCII geschrieben sein DUERFEN.
#
# Jede Ausnahme braucht eine Begruendung - sonst wird sie stillschweigend
# zur Regel.
# ---------------------------------------------------------------------------
AUSNAHMEN: dict[str, str] = {}

# ---------------------------------------------------------------------------
# Die Ziele: nutzersichtbare Texte.
# ---------------------------------------------------------------------------

# (Pfad, Art) - Art: 'ganz' (die ganze Datei), 'strings' (nur die
# String-Literale) oder 'strings_de' (nur der deutsche L10n-Abschnitt).
ZIELE: list[tuple[str, str]] = [
    # DIE TEXTE LIEGEN NACH THEMEN GETRENNT: lib/l10n/strings/*.dart
    # (jede Datei ein Thema, je Deutsch und Englisch). Der Ordner wird
    # unten auf seine Dateien aufgeloest.
    ("lib/l10n/strings", "strings_de_ordner"),
    ("lib/generated/privacy_policy_de.dart", "strings"),
    ("docs/recht/DATENSCHUTZ.md", "ganz"),
    ("README.md", "ganz"),
    ("passkey-assets/index.html", "ganz"),
    ("passkey-assets/datenschutz.html", "ganz"),
    ("passkey-assets/kinderschutz.html", "ganz"),
    ("passkey-assets/impressum.html", "ganz"),
    ("passkey-assets/nutzungsbedingungen.html", "ganz"),
    ("passkey-assets/konto-loeschen.html", "ganz"),
    ("fastlane/metadata/android/de-DE/changelogs/56.txt", "ganz"),
]


def lies_string_literale(text: str) -> list[tuple[int, str]]:
    """Holt die String-Literale (mit Zeilennummer) aus einem Quelltext.

    Kommentare werden uebersprungen - die sind im Projekt bewusst ASCII.
    """
    treffer: list[tuple[int, str]] = []
    zeile = 1
    i = 0
    n = len(text)
    while i < n:
        zeichen = text[i]
        if zeichen == "\n":
            zeile += 1
            i += 1
            continue
        # Kommentarzeilen
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            i += 2
            while i < n and not text.startswith("*/", i):
                if text[i] == "\n":
                    zeile += 1
                i += 1
            i += 2
            continue
        # String-Literal (einfach oder doppelt)
        if zeichen in "'\"":
            endezeichen = zeichen
            doppelt = text.startswith(zeichen * 2, i)
            if doppelt:
                i += 2
                start_zeile = zeile
                inhalt = []
                while i < n and not text.startswith(endezeichen * 2, i):
                    if text[i] == "\n":
                        zeile += 1
                    elif text[i] == "\\" and i + 1 < n:
                        inhalt.append(text[i + 1])
                        i += 2
                        continue
                    inhalt.append(text[i])
                    i += 1
                i += 2
                treffer.append((start_zeile, "".join(inhalt)))
                continue
            i += 1
            start_zeile = zeile
            inhalt = []
            while i < n and text[i] != endezeichen:
                if text[i] == "\\" and i + 1 < n:
                    inhalt.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == "\n":
                    zeile += 1
                inhalt.append(text[i])
                i += 1
            i += 1
            treffer.append((start_zeile, "".join(inhalt)))
            continue
        i += 1
    return treffer


def _ohne_zeilenwechsel(text: str, ersatz: str) -> str:
    """Ersetzt Text, ohne die Zeilennummern zu verschieben.

    Wichtig: der Ersatz muss dieselbe Zahl Zeilenumbrueche haben wie
    der Originaltext - sonst stimmen die gemeldeten Zeilen nicht mehr.
    """
    return re.sub(
        r"[^\n]",
        lambda _treffer: ersatz if ersatz != "" else " ",
        text,
    )


def ohne_code_und_urls(text: str) -> str:
    """Entfernt alles, was nicht nutzersichtbarer Text ist.

    - Inline-Code (`...`), URLs und HTML-Attribute
    - Script-, Style- und Kommentar-Bloecke (Code, kein Text)

    Die Zeilennummern bleiben dabei erhalten (die Zeilenumbrueche der
    entfernten Bloecke bleiben an Ort und Stelle).
    """
    # Script-, Style- und Kommentar-Bloecke: Inhalt raus, Zeilen bleiben.
    for muster in (
        r"<script\b[^>]*>.*?</script>",
        r"<style\b[^>]*>.*?</style>",
        r"<!--.*?-->",
    ):
        text = re.sub(
            muster,
            lambda treffer: _ohne_zeilenwechsel(treffer.group(0), ""),
            text,
            flags=re.DOTALL | re.IGNORECASE,
        )
    # Inline-Code, URLs, Attribute: Inhalt raus, Zeilen bleiben.
    #
    # NUR technische Attribute werden entfernt (id, class, SVG-Pfade ...).
    # Text-Attribute (alt, title, placeholder, aria-label) bleiben geprueft
    # - sie sind fuer Screenreader und Tooltips sichtbar.
    for muster in (
        r"`[^`]*`",
        r"https?://\S+",
        r"(?:href|src|content)\s*=\s*\"[^\"]*\"",
        r"(?:(?:id|class|style|d|points|viewBox|fill|stroke|xmlns|transform)"
        r"|data-[\w-]+)\s*=\s*\"[^\"]*\"",
    ):
        text = re.sub(
            muster,
            lambda treffer: _ohne_zeilenwechsel(treffer.group(0), ""),
            text,
        )
    return text


def pruefe(
    text: str,
    funde: list[tuple[str, int, str, str, str]],
    datei: str,
    basiszeile: int = 0,
) -> None:
    """Sucht die Muster im Text (zeilenweise, damit die Zeile stimmt)."""
    for nummer, zeile in enumerate(text.splitlines(), start=1):
        if not zeile.strip():
            continue
        for muster, korrekt in MUSTER:
            for treffer in muster.finditer(zeile):
                wort = treffer.group(0)
                if wort in AUSNAHMEN:
                    continue
                funde.append(
                    (datei, basiszeile + nummer, wort, korrekt, zeile.strip())
                )


def main() -> int:
    print("== Umlaute in nutzersichtbaren Texten ==")
    funde: list[tuple[str, int, str, str, str]] = []
    geprueft = 0

    for relativer, art in ZIELE:
        pfad = ROOT / relativer
        if not pfad.exists():
            continue
        if art == "strings_de_ordner":
            # Der Ordner mit den Texten: jede Datei wird einzeln geprueft.
            for datei in sorted(pfad.glob("*.dart")):
                geprueft += 1
                rohtext = datei.read_text(encoding="utf-8", errors="replace")
                start = rohtext.find("'de': {")
                ende = rohtext.find("'en': {")
                if start < 0 or ende < 0:
                    continue
                ausschnitt = rohtext[start:ende]
                basis = rohtext[:start].count("\n")
                name = str(datei.relative_to(ROOT))
                for start_zeile, literal in lies_string_literale(ausschnitt):
                    pruefe(
                        literal,
                        funde,
                        name,
                        basiszeile=basis + start_zeile - 1,
                    )
            continue
        geprueft += 1
        rohtext = pfad.read_text(encoding="utf-8", errors="replace")

        if art == "ganz":
            pruefe(ohne_code_und_urls(rohtext), funde, relativer)
        elif art == "strings":
            for start_zeile, literal in lies_string_literale(rohtext):
                if "://" in literal:
                    continue
                pruefe(literal, funde, relativer, basiszeile=start_zeile - 1)
        elif art == "strings_de":
            # Nur der deutsche Abschnitt der L10n-Datei.
            start = rohtext.find("'de': {")
            ende = rohtext.find("'en': {")
            if start < 0 or ende < 0:
                continue
            ausschnitt = rohtext[start:ende]
            basis = rohtext[:start].count("\n")
            for start_zeile, literal in lies_string_literale(ausschnitt):
                pruefe(literal, funde, relativer, basiszeile=basis + start_zeile - 1)

    if not funde:
        print(
            f"OK: {geprueft} nutzersichtbare Datei(en) geprueft - "
            "keine ASCII-Ersatzschreibweise gefunden."
        )
        return 0

    print()
    for datei, nummer, wort, korrekt, kontext in funde:
        print(f"{datei}:{nummer}   {wort}  ->  {korrekt}")
        print(f"    {kontext[:110]}")
    print()
    print(f"FEHLER: {len(funde)} Stelle(n) mit ASCII-Ersatzschreibweise.")
    print("In nutzersichtbaren Texten gehoeren echte Umlaute hinein")
    print("(ae/oe/ue/ss ist im Deutschen falsch).")
    print("HINWEIS: Kommentare im Quelltext bleiben bewusst ASCII - sie")
    print("werden hier nicht geprueft.")
    return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
