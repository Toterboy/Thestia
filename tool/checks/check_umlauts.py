#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""Prüfen, dass nutzersichtbare Texte echte Umlaute benutzen.

WARUM (16.11.2026, Wunsch des Betreibers): In deutschsprachigen Texten
wird häufig "ä/oe/ü/ss" geschrieben, wenn eigentlich "ä/ö/ü/ß"
gemeint ist - "für" statt "für", "Überblick" statt "Überblick",
"müssen" statt "müssen". Das sieht nach Maschine aus und fällt in
einem deutschen Text sofort auf.

WICHTIG - der Umfang (25.11.2026): Bis dahin stand in diesem Projekt
die Konvention "die Kommentare bleiben ASCII". Der Betreiber hat das
umgedreht - die echten Umlaute gehören überall hinein. Geprüft
werden deshalb jetzt ALLES:

  * die deutschen L10n-Strings (lib/l10n/strings/*.dart, Abschnitt 'de')
  * die deutsche Datenschutzerklärung (Quelle + generierte Datei)
  * die deutschen Webseiten (passkey-assets/ ohne en/)
  * das README, das CHANGELOG und die ROADMAP
  * die deutschen Dokumente (docs/) und die Release-Dokumente (releases/)
  * die deutschen Store-Texte (fastlane/.../de-DE/)
  * die Kommentare im Quelltext (lib/, test/, tool/)

GESCHÜTZT bleiben die Stellen, an denen kein Prosatext steht: der
Inline-Code (``...``), die URLs, die Dateinamen, die technischen
Attribute im HTML und die Bezeichner in den L10n-Schlüsseln (z.B.
"del.geraete").

Die gesperrte Schrift (Großbuchstaben) ist erlaubt: dort schreibt man
das "ss" als "SS" - "GROSSE" ist richtig, "GROßE" nicht.

Aufruf:  python tool/checks/check_umlauts.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zählen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe ändert.
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
# Wortgrenzen gesucht; Groß-/Kleinschreibung wird nicht unterschieden
# (die Form in der Meldung ist die Korrektur, nicht der Originaltext).
#
# NUR Einträge mit hoher Trefferquote - ein Fehlalarm kostet mehr als
# ein nicht gefundener Fehler. Eigennamen, englische Wörter und
# Bezeichner stehen deshalb NICHT hier.
# ---------------------------------------------------------------------------
WORTE: list[tuple[str, str]] = [
    # --- Stammwörter mit ä/oe/ü ------------------------------------
    (r"fuer", "für"),
    (r"ueber", "über"),
    (r"koennen", "können"),
    (r"muesste", "müste"),
    (r"muessen", "müssen"),
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
    (r"begruesst", "begrüßt"),
    (r"begruessen", "begrüßen"),
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
    (r"massgeblich", "maßgeblich"),
    (r"massgebliche", "maßgebliche"),
    (r"massgeblichen", "maßgeblichen"),
    (r"massgeblicher", "maßgeblicher"),
    (r"massgebliches", "maßgebliches"),
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
    # --- Wörter mit ss statt ß --------------------------------------
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
    # --- Die Wörter, die der Konverter nicht kennt (25.11.2026) -------
    # (Das sind die Wörter mit "ss" statt "ß" und ein paar Wortformen,
    # die das Wörterbuch nicht kennt.)
    (r"ausserhalb", "außerhalb"),
    (r"aussen", "außen"),
    (r"liess", "ließ"),
    (r"anstossen", "anstoßen"),
    (r"sass", "saß"),
    (r"fuss", "fuß"),
    (r"waehle", "wähle"),
    (r"hoerst", "hörst"),
    (r"pruefe", "prüfe"),
    (r"bestaetigst", "bestätigst"),
    (r"schaetz(en|t)", "schätzen"),
    (r"moechtest", "möchtest"),
    # --- Die Wörter aus der Umstellung (25.11.2026) ---------------
    # (Der Projekttext schrieb die Umlaute als "ä/ö/ü/ss" - das sieht
    # nach Maschine aus. Diese Einträge sichern die Umstellung ab.)
    (r"wuerde", "würde"),
    (r"geraet", "gerät"),
    (r"unveraendert", "unverändert"),
    (r"aendert", "ändert"),
    (r"pruefung", "prüfung"),
    (r"prueft", "prüft"),
    (r"zaehlen", "zählen"),
    (r"pruefen", "prüfen"),
    (r"faellt", "fällt"),
    (r"schlaegt", "schlägt"),
    (r"loeschen", "löschen"),
    (r"geraete", "geräte"),
    (r"naechsten", "nächsten"),
    (r"linksbuendig", "linksbündig"),
    (r"datenschutzerklaerung", "datenschutzerklärung"),
    (r"ueberschrift", "überschrift"),
    (r"hoehe", "höhe"),
    (r"haelt", "hält"),
    (r"zaehlt", "zählt"),
    (r"oeffnen", "öffnen"),
    (r"geloescht", "gelöscht"),
    (r"bestaetigt", "bestätigt"),
    (r"waeren", "wären"),
    (r"vollstaendig", "vollständig"),
    (r"enthaelt", "enthält"),
    (r"laedt", "lädt"),
    (r"aenderung", "änderung"),
    (r"haengt", "hängt"),
    (r"oeffentlichen", "öffentlichen"),
    (r"uebrig", "übrig"),
    (r"oeffnet", "öffnet"),
    (r"huelle", "hülle"),
    (r"menue", "menü"),
    (r"gehoeren", "gehören"),
    (r"dafuer", "dafür"),
    (r"eintraege", "einträge"),
    (r"erklaerung", "erklärung"),
    (r"fuellt", "füllt"),
    (r"darueber", "darüber"),
    (r"duerfen", "dürfen"),
    (r"verschluesselt", "verschlüsselt"),
    (r"grosser", "großer"),
    (r"oeffentliche", "öffentliche"),
    (r"bloecke", "blöcke"),
    (r"loescht", "löscht"),
    (r"waehlen", "wählen"),
    (r"geraeten", "geräten"),
    (r"zustaende", "zustände"),
    (r"ausdruecklich", "ausdrücklich"),
    (r"aeltere", "ältere"),
    (r"naechste", "nächste"),
    (r"praefix", "präfix"),
    (r"bestaetigen", "bestätigen"),
    (r"zusaetzlich", "zusätzlich"),
    (r"verschluesselten", "verschlüsselten"),
    (r"haengen", "hängen"),
    (r"geaendert", "geändert"),
    (r"geoeffnet", "geöffnet"),
    (r"oberflaeche", "oberfläche"),
    (r"minderjaehrige", "minderjährige"),
    (r"geraets", "geräts"),
    (r"begruendung", "begründung"),
    (r"bestaetigungsseite", "bestätigungsseite"),
    (r"unabhaengig", "unabhängig"),
    (r"verschluesselung", "verschlüsselung"),
    (r"zaehler", "zähler"),
    (r"gespraech", "gespräch"),
    (r"empfaenger", "empfänger"),
    (r"tatsaechlich", "tatsächlich"),
    (r"uebernommen", "übernommen"),
    (r"wuerden", "würden"),
    (r"flaeche", "fläche"),
    (r"getoentem", "getöntem"),
    (r"luecke", "lücke"),
    (r"primaer", "primär"),
    (r"specificitaet", "specificität"),
    (r"kopfschaltflaechen", "kopfschaltflächen"),
    (r"zwischenueberschrift", "zwischenüberschrift"),
    (r"dazugehoerig", "dazugehörig"),
    (r"waehlt", "wählt"),
    (r"ueberschrieben", "überschrieben"),
    (r"schriftgroesse", "schriftgrösse"),
    (r"aenderungen", "änderungen"),
    (r"verschluesselungs", "verschlüsselungs"),
    (r"loest", "löst"),
    (r"fuegt", "fügt"),
    (r"koerper", "körper"),
    (r"pruefer", "prüfer"),
    (r"groesste", "größte"),
    (r"uebrigen", "übrigen"),
    (r"haarlaenge", "haarlänge"),
    (r"alterspruefung", "altersprüfung"),
    (r"aufraeum", "aufräum"),
    (r"jaehrige", "jährige"),
    (r"gefuellt", "gefüllt"),
    (r"groesser", "größer"),
    (r"boegen", "bögen"),
    (r"verknuepfung", "verknüpfung"),
    (r"aelter", "älter"),
    (r"faengt", "fängt"),
    (r"uebersprungen", "übersprungen"),
    (r"zurueckgesetzt", "zurückgesetzt"),
    (r"naehe", "nähe"),
    (r"strichstaerke", "strichstärke"),
    (r"genuegt", "genügt"),
    (r"uebersetzung", "übersetzung"),
    (r"ueberall", "überall"),
    (r"waechst", "wächst"),
    (r"laenger", "länger"),
    (r"bestaetigungs", "bestätigungs"),
    (r"abstuerzen", "abstürzen"),
    (r"stuende", "stünde"),
    (r"haelfte", "hälfte"),
    (r"pruefsummen", "prüfsummen"),
    (r"loesch", "lösch"),
    (r"uebertragung", "übertragung"),
    (r"rueckgaengig", "rückgängig"),
    (r"veraendert", "verändert"),
    (r"oeffnete", "öffnete"),
    (r"abstaende", "abstände"),
    (r"aufloesung", "auflösung"),
    (r"pruefte", "prüfte"),
    (r"aelteren", "älteren"),
    (r"fuehren", "führen"),
    (r"identitaet", "identität"),
    (r"erfaehrt", "erfährt"),
    (r"pruefbar", "prüfbar"),
    (r"erklaert", "erklärt"),
    (r"raeumt", "räumt"),
    (r"rueckfall", "rückfall"),
    (r"unberuehrt", "unberührt"),
    (r"aufraeumen", "aufräumen"),
    (r"ueberspringen", "überspringen"),
    (r"jaehriger", "jähriger"),
    (r"schreibvorgaenge", "schreibvorgänge"),
    (r"ueberschreibt", "überschreibt"),
    (r"voellig", "völlig"),
    (r"zufaellig", "zufällig"),
    (r"abgeraeumt", "abgeräumt"),
    (r"entschluesseln", "entschlüsseln"),
    (r"uebersetzt", "übersetzt"),
    (r"groessen", "größen"),
    (r"rueckgabe", "rückgabe"),
    (r"gewaehlten", "gewählten"),
    (r"ueberlaufen", "überlaufen"),
    (r"grossen", "großen"),
    (r"schraegstrich", "schrägstrich"),
    (r"erfuellt", "erfüllt"),
    (r"verfuegbar", "verfügbar"),
    (r"aufgeloest", "aufgelöst"),
    (r"fingerabdruecke", "fingerabdrücke"),
    (r"geraeteliste", "geräteliste"),
    (r"vollstaendiger", "vollständiger"),
    (r"faelschlich", "fälschlich"),
    (r"gewaehlte", "gewählte"),
    (r"pruefungen", "prüfungen"),
    (r"kaeme", "käme"),
    (r"eingefuegt", "eingefügt"),
    (r"ungeprueft", "ungeprüft"),
    (r"gueltigkeit", "gültigkeit"),
    (r"rueckmeldung", "rückmeldung"),
    (r"stueck", "stück"),
    (r"gueltige", "gültige"),
    (r"zurueckkommt", "zurückkommt"),
    (r"hoert", "hört"),
    (r"geschuetzt", "geschützt"),
    (r"hintergruende", "hintergründe"),
    (r"entfaellt", "entfällt"),
    (r"datenloeschung", "datenlöschung"),
    (r"mindestlaenge", "mindestlänge"),
    (r"praeferenzen", "präferenzen"),
    (r"verhaelt", "verhält"),
    (r"gueltiges", "gültiges"),
    (r"kuerzel", "kürzel"),
    (r"stoert", "stört"),
    (r"auffaellt", "auffällt"),
    (r"kanaele", "kanäle"),
    (r"luecken", "lücken"),
    (r"abhaengigkeit", "abhängigkeit"),
    (r"praeferenz", "präferenz"),
    (r"einrueckung", "einrückung"),
    (r"anhoeren", "anhören"),
    (r"ueberspringt", "überspringt"),
    (r"uebergang", "übergang"),
    (r"ausloesen", "auslösen"),
    (r"einfuegen", "einfügen"),
    (r"unterdrueckung", "unterdrückung"),
    (r"stoerend", "störend"),
    (r"uebernehmen", "übernehmen"),
    (r"verhaeltnis", "verhältnis"),
    (r"uebergeben", "übergeben"),
    (r"haeufigste", "häufigste"),
    (r"zerstoeren", "zerstören"),
    (r"muell", "müll"),
    (r"staerke", "stärke"),
    (r"ueberschreiben", "überschreiben"),
    (r"zurueckgibt", "zurückgibt"),
    (r"passwoerter", "passwörter"),
    (r"spaetere", "spätere"),
    (r"fuellen", "füllen"),
    (r"altersschaetzung", "altersschätzung"),
    (r"entschluesselt", "entschlüsselt"),
    (r"spaeterer", "späterer"),
    (r"gekuehlt", "gekühlt"),
    (r"ausgeloest", "ausgelöst"),
    (r"ueberlebt", "überlebt"),
    (r"vollstaendige", "vollständige"),
    (r"knoepfe", "knöpfe"),
    (r"faellen", "fällen"),
    (r"veroeffentlicht", "veröffentlicht"),
    (r"auswaehlt", "auswählt"),
    (r"gedrueckt", "gedrückt"),
    (r"haertung", "härtung"),
    (r"maechtige", "mächtige"),
    (r"druecken", "drücken"),
    (r"stoeren", "stören"),
    (r"bildschirmhoehe", "bildschirmhöhe"),
    (r"gueltig", "gültig"),
    (r"gezaehlt", "gezählt"),
    (r"waehler", "wähler"),
    (r"laengengrad", "längengrad"),
    (r"gefuellter", "gefüllter"),
    (r"minderjaehrigen", "minderjährigen"),
    (r"gruene", "grüne"),
    (r"ersatzwaerter", "ersatzwärter"),
    (r"laeufe", "läufe"),
    (r"uebereinander", "übereinander"),
    (r"zeilenumbrueche", "zeilenumbrüche"),
    (r"entschluesselung", "entschlüsselung"),
    (r"empfaengers", "empfängers"),
    (r"sicherheitspruefung", "sicherheitsprüfung"),
    (r"vortaeuschen", "vortäuschen"),
    (r"ungeschuetzt", "ungeschützt"),
    (r"ungueltig", "ungültig"),
    (r"erklaeren", "erklären"),
    (r"gespraechs", "gesprächs"),
    (r"schuetzen", "schützen"),
    (r"eingefuehrt", "eingeführt"),
    (r"endgueltig", "endgültig"),
    (r"moeglichkeit", "möglichkeit"),
    (r"faerbt", "färbt"),
    (r"saetze", "sätze"),
    (r"zuhoerer", "zuhörer"),
    (r"haengender", "hängender"),
    (r"ruecksetzen", "rücksetzen"),
    (r"ueberschriften", "überschriften"),
    (r"schaetzung", "schätzung"),
    (r"videoerifizierung", "videörifizierung"),
    (r"fuellung", "füllung"),
    (r"uebereinstimmen", "übereinstimmen"),
    (r"verschluesselte", "verschlüsselte"),
    (r"wofuer", "wofür"),
    (r"veraendern", "verändern"),
    (r"seitenverhaeltnis", "seitenverhältnis"),
    (r"ersatzkaestchen", "ersatzkästchen"),
    (r"laengste", "längste"),
    (r"fehlerfaelle", "fehlerfälle"),
    (r"oeffentlicher", "öffentlicher"),
    (r"ausgefuehrt", "ausgeführt"),
    (r"geraeumt", "geräumt"),
    (r"gegenstueck", "gegenstück"),
    (r"einfuehrung", "einführung"),
    (r"raender", "ränder"),
    (r"gruss", "gruß"),
    (r"maenner", "männer"),
    (r"negativfaelle", "negativfälle"),
    (r"ausfuehrung", "ausführung"),
    (r"woerter", "wörter"),
    (r"duenn", "dünn"),
    (r"randstaerke", "randstärke"),
    (r"verschluesseln", "verschlüsseln"),
    (r"abhaengigkeiten", "abhängigkeiten"),
    (r"sicherheitsluecken", "sicherheitslücken"),
    (r"jaehrlich", "jährlich"),
    (r"ausfuehren", "ausführen"),
    (r"abstaenden", "abständen"),
    (r"abgestuerzt", "abgestürzt"),
    (r"gegenueber", "gegenüber"),
    (r"ueberleben", "überleben"),
    (r"waehlbar", "wählbar"),
    (r"drueckt", "drückt"),
    # ACHTUNG: Das Adjektiv heißt "grau" (ohne Umlaut) - grau, graue,
    # grauer, grauem. Die früheren Einträge "grauer" -> "graür" usw.
    # waren falsch und meldeten einen Fehler, den es nicht gab (27.11.2026).
    (r"zurueckgefallen", "zurückgefallen"),
    (r"juenger", "jünger"),
    (r"schaedlicher", "schädlicher"),
    (r"groessten", "größten"),
    (r"auswaehlen", "auswählen"),
    (r"ungefaehre", "ungefähre"),
    (r"ueberladen", "überladen"),
    (r"beruehrt", "berührt"),
    (r"veroeffentlichten", "veröffentlichten"),
    (r"zulaesst", "zulässt"),
    (r"zusaetzliche", "zusätzliche"),
    (r"verstaendliche", "verständliche"),
    (r"loeschte", "löschte"),
    (r"kuenstler", "künstler"),
    (r"standardmaessig", "standardmässig"),
    (r"uebliche", "übliche"),
    (r"irrefuehrend", "irreführend"),
    (r"weiterlaeuft", "weiterläuft"),
    (r"ungefaehr", "ungefähr"),
    (r"spaeteren", "späteren"),
    (r"gefuellte", "gefüllte"),
    (r"boesartige", "bösartige"),
    (r"hoechste", "höchste"),
    (r"tatsaechliche", "tatsächliche"),
    (r"zurueckgeben", "zurückgeben"),
    (r"ausloeser", "auslöser"),
    (r"zurueckgerechnet", "zurückgerechnet"),
    (r"mindestlaengen", "mindestlängen"),
    (r"beschraenkung", "beschränkung"),
    (r"jaehrigen", "jährigen"),
    (r"aequator", "äquator"),
    (r"kachelgroesse", "kachelgrösse"),
    (r"verfuegbaren", "verfügbaren"),
    (r"zurueckgenommen", "zurückgenommen"),
    (r"gefuelltes", "gefülltes"),
    (r"verhaltensaenderung", "verhaltensänderung"),
    (r"stuerzt", "stürzt"),
    (r"aufzaehlungen", "aufzählungen"),
    (r"gewuenschten", "gewünschten"),
    (r"vollstaendigen", "vollständigen"),
    (r"zuruecknehmen", "zurücknehmen"),
    (r"gekuehlter", "gekühlter"),
    (r"verdaechtig", "verdächtig"),
    (r"aufklaerung", "aufklärung"),
    (r"testkoerper", "testkörper"),
    (r"zuruecklesen", "zurücklesen"),
    (r"zusammenfuehrung", "zusammenführung"),
    (r"duenne", "dünne"),
    (r"funktionskoerper", "funktionskörper"),
    (r"tatsaechlichen", "tatsächlichen"),
    (r"moegliche", "mögliche"),
    (r"qualitaet", "qualität"),
    (r"signalbaenke", "signalbänke"),
    (r"nachpruefbar", "nachprüfbar"),
    (r"ueberholt", "überholt"),
    (r"minderjaehrigkeitsfall", "minderjährigkeitsfall"),
    (r"aufloesen", "auflösen"),
    (r"kaemen", "kämen"),
    (r"geraetetest", "gerätetest"),
    (r"schaerfer", "schärfer"),
    (r"schueler", "schüler"),
    (r"bestaetigte", "bestätigte"),
    (r"gebuendelten", "gebündelten"),
    (r"ergaenzt", "ergänzt"),
    (r"prioritaet", "priorität"),
    (r"zurueckwechseln", "zurückwechseln"),
    (r"verlaengern", "verlängern"),
    (r"eingeloest", "eingelöst"),
    (r"ergaenzen", "ergänzen"),
    (r"erklaerenden", "erklärenden"),
    (r"erhaelt", "erhält"),
    (r"abhoerbar", "abhörbar"),
    (r"fuehrende", "führende"),
    (r"frueheren", "früheren"),
    (r"kontoloeschung", "kontolöschung"),
    (r"stoebern", "stöbern"),
    (r"profilaenderungen", "profiländerungen"),
    (r"domaene", "domäne"),
    (r"gewuenschte", "gewünschte"),
    (r"taegliche", "tägliche"),
    (r"ungefaehren", "ungefähren"),
    (r"mitzaehlt", "mitzählt"),
    (r"verzoegerung", "verzögerung"),
    (r"geschuetzter", "geschützter"),
    (r"erklaerungsseiten", "erklärungsseiten"),
    (r"auswaehlbar", "auswählbar"),
    (r"erklaerungstext", "erklärungstext"),
    (r"zulaessig", "zulässig"),
    (r"loeschungen", "löschungen"),
    (r"wuerfe", "würfe"),
    (r"ueberblendung", "überblendung"),
    (r"saehe", "sähe"),
    (r"begruessung", "begrüßung"),
    (r"empfaengt", "empfängt"),
    (r"rueckt", "rückt"),
    (r"abhaengig", "abhängig"),
    (r"natuerlich", "natürlich"),
    (r"hoeren", "hören"),
    (r"persoenlichkeitstyp", "persönlichkeitstyp"),
    (r"bestaetigungsdialog", "bestätigungsdialog"),
    (r"gehaengt", "gehängt"),
    (r"aelterer", "älterer"),
    (r"uebertragen", "übertragen"),
    (r"minderjaehriger", "minderjähriger"),
    (r"laengsten", "längsten"),
    (r"fuellzeichen", "füllzeichen"),
    (r"noetigen", "nötigen"),
    (r"binaerdaten", "binärdaten"),
    (r"ausloest", "auslöst"),
    (r"zurueckschreibt", "zurückschreibt"),
    (r"zerstoert", "zerstört"),
    (r"kontinuitaet", "kontinuität"),
    (r"urspruengliche", "ursprüngliche"),
    (r"kaestchen", "kästchen"),
    (r"gueltigen", "gültigen"),
    (r"naeherung", "näherung"),
    (r"ueberarbeitet", "überarbeitet"),
    (r"hochlaedt", "hochlädt"),
    (r"ae", "ä"),
    (r"ue", "ü"),
    (r"uebergebenen", "übergebenen"),
    (r"duenner", "dünner"),
    (r"verstaendlichen", "verständlichen"),
    (r"fremdkoerper", "fremdkörper"),
    (r"zusaetzliches", "zusätzliches"),
    (r"formatpruefung", "formatprüfung"),
    (r"wuesste", "wüsste"),
    (r"gefuellten", "gefüllten"),
    (r"wegraeumen", "wegräumen"),
    (r"unbestaetigte", "unbestätigte"),
    (r"spaet", "spät"),
    (r"uebergibt", "übergibt"),
    (r"unnoetig", "unnötig"),
    (r"menuepunkt", "menüpunkt"),
    (r"staerken", "stärken"),
    (r"koenntest", "könntest"),
    (r"gekuehlten", "gekühlten"),
    (r"fuehrenden", "führenden"),
    (r"textaenderung", "textänderung"),
    (r"groessere", "größere"),
    (r"paritaet", "parität"),
    (r"geraetes", "gerätes"),
    (r"ueberfluessig", "überflüssig"),
    (r"anruehren", "anrühren"),
    (r"verraet", "verrät"),
    (r"grossbuchstabe", "großbuchstabe"),
    (r"erwaehnen", "erwähnen"),
    (r"anschlaegt", "anschlägt"),
    (r"ausfuehrungsrecht", "ausführungsrecht"),
    (r"rueckwaerts", "rückwärts"),
    (r"mitgeprueft", "mitgeprüft"),
    (r"sicherheitspruefungen", "sicherheitsprüfungen"),
    (r"aufzaehlung", "aufzählung"),
    (r"kaesten", "kästen"),
    (r"koerpers", "körpers"),
    (r"oeffentlichem", "öffentlichem"),
    (r"zielpruefung", "zielprüfung"),
    (r"bildhoehe", "bildhöhe"),
    (r"gewuellt", "gewüllt"),
    (r"raendern", "rändern"),
    (r"mass", "maß"),
    (r"akkukoerperhoehe", "akkukörperhöhe"),
    (r"schraeg", "schräg"),
    (r"unterdrueckt", "unterdrückt"),
    (r"ueberein", "überein"),
    (r"geraetewechsel", "gerätewechsel"),
    (r"veraenderlich", "veränderlich"),
    (r"fuettert", "füttert"),
    (r"waechter", "wächter"),
    (r"zertifikatspruefung", "zertifikatsprüfung"),
    (r"faelschen", "fälschen"),
    (r"gefaelschtes", "gefälschtes"),
    (r"uebergehen", "übergehen"),
    (r"aufgeraeumt", "aufgeräumt"),
    (r"oefter", "öfter"),
    (r"stoesst", "stösst"),
    (r"moeglichkeiten", "möglichkeiten"),
    (r"ueblichen", "üblichen"),
    (r"antwortschluessel", "antwortschlüssel"),
    (r"unvollstaendige", "unvollständige"),
    (r"spaeteres", "späteres"),
    (r"naehefunk", "nähefunk"),
    (r"unregelmaessigen", "unregelmässigen"),
    (r"hinzufuegen", "hinzufügen"),
    (r"verschaerft", "verschärft"),
    (r"veroeffentlichte", "veröffentlichte"),
    (r"geoeffneten", "geöffneten"),
    (r"anzeegeraete", "anzeegeräte"),
    (r"erfahrungsgemaess", "erfahrungsgemäss"),
    (r"ueberspringbar", "überspringbar"),
    (r"fruehere", "frühere"),
    (r"geloeschte", "gelöschte"),
    (r"weggedrueckt", "weggedrückt"),
    (r"nachtraeglich", "nachträglich"),
    (r"nachtraeglicher", "nachträglicher"),
    (r"gewuerfelt", "gewürfelt"),
    (r"ungueltige", "ungültige"),
    (r"einsprueche", "einsprüche"),
    (r"braeuchte", "bräuchte"),
    (r"eingerueckt", "eingerückt"),
    (r"entstuende", "entstünde"),
    (r"anfuehlt", "anfühlt"),
    (r"spaetestens", "spätestens"),
    (r"buendig", "bündig"),
    (r"menues", "menüs"),
    (r"ausdruecklichen", "ausdrücklichen"),
    (r"gedaempft", "gedämpft"),
    (r"rueckfeder", "rückfeder"),
    (r"fluessig", "flüssig"),
    (r"zurueckflackern", "zurückflackern"),
    (r"zurueckgelegt", "zurückgelegt"),
    (r"fluessigen", "flüssigen"),
    (r"zuegiger", "zügiger"),
    (r"uebersetzungen", "übersetzungen"),
    (r"frueh", "früh"),
    (r"ueberlappt", "überlappt"),
    (r"ueberlappung", "überlappung"),
    (r"kuerzer", "kürzer"),
    (r"ausgewaehlt", "ausgewählt"),
    (r"plausibilitaets", "plausibilitäts"),
    (r"laender", "länder"),
    (r"ungueltiger", "ungültiger"),
    (r"lueckenlos", "lückenlos"),
    (r"gegenpruefung", "gegenprüfung"),
    (r"fuehrendem", "führendem"),
    (r"schaltflaeche", "schaltfläche"),
    (r"schoener", "schöner"),
    (r"volljaehrige", "volljährige"),
    (r"volljaehrig", "volljährig"),
    (r"fehlschlaegt", "fehlschlägt"),
    (r"gruenden", "gründen"),
    (r"zurueckgemeldet", "zurückgemeldet"),
    (r"verknuepfte", "verknüpfte"),
    (r"zaehlte", "zählte"),
    (r"ungueltigem", "ungültigem"),
    (r"kuerzere", "kürzere"),
    (r"zurueckgewiesen", "zurückgewiesen"),
    (r"zufaellige", "zufällige"),
    (r"unterdruecken", "unterdrücken"),
    (r"juengste", "jüngste"),
    (r"verdraengte", "verdrängte"),
    (r"beruehrung", "berührung"),
    (r"aehm", "ähm"),
    (r"rueckgabewert", "rückgabewert"),
    (r"fehlergruende", "fehlergründe"),
    (r"schluesseltabelle", "schlüsseltabelle"),
    (r"spuerbar", "spürbar"),
    (r"zustaendig", "zuständig"),
    (r"bessaessigt", "bessässigt"),
    (r"kreisfoermig", "kreisförmig"),
    (r"naeher", "näher"),
    (r"anfaengt", "anfängt"),
    (r"faehig", "fähig"),
    (r"zunaechst", "zunächst"),
    (r"zielgroesse", "zielgrösse"),
    (r"vorgaenge", "vorgänge"),
    (r"trefferflaeche", "trefferfläche"),
    (r"angehaengt", "angehängt"),
    (r"haeufigsten", "häufigsten"),
    (r"zeilenhoehe", "zeilenhöhe"),
    (r"profilflaeche", "profilfläche"),
    (r"ueberblenden", "überblenden"),
    (r"unzuverlaessig", "unzuverlässig"),
    (r"stuetzstellen", "stützstellen"),
    (r"gekuerzter", "gekürzter"),
    (r"verlaessliche", "verlässliche"),
    (r"ueberschreibbar", "überschreibbar"),
    (r"gewaehlter", "gewählter"),
    (r"erklaerungen", "erklärungen"),
    (r"sonderfaelle", "sonderfälle"),
    (r"staerker", "stärker"),
    (r"geaenderter", "geänderter"),
    (r"erklaerungstexte", "erklärungstexte"),
    (r"angehaengten", "angehängten"),
    (r"ueberholen", "überholen"),
    (r"frueherer", "früherer"),
    (r"formularpruefung", "formularprüfung"),
    (r"raeumen", "räumen"),
    (r"bestaetigungsschritt", "bestätigungsschritt"),
    (r"gaebe", "gäbe"),
    (r"schluesseln", "schlüsseln"),
    (r"aufloest", "auflöst"),
    (r"hochzaehlen", "hochzählen"),
    (r"hinzugefuegt", "hinzugefügt"),
    (r"loeschbar", "löschbar"),
    (r"passwoertern", "passwörtern"),
    (r"schluesselpaar", "schlüsselpaar"),
    (r"wiederoeffnen", "wiederöffnen"),
    (r"zurueckfallen", "zurückfallen"),
    (r"oeffentliches", "öffentliches"),
    (r"testkoerpers", "testkörpers"),
    (r"aktionsmenue", "aktionsmenü"),
    (r"gaengt", "gängt"),
    (r"kuehlung", "kühlung"),
    (r"aeussere", "äussere"),
    (r"aktivitaet", "aktivität"),
    (r"koennten", "könnten"),
    (r"ueberschneidung", "überschneidung"),
    (r"zusammengefuegt", "zusammengefügt"),
    (r"muenchen", "münchen"),
    (r"grossbuchstaben", "großbuchstaben"),
    (r"auffaellig", "auffällig"),
    (r"persoenlichkeitstest", "persönlichkeitstest"),
    (r"kompatibilitaet", "kompatibilität"),
    (r"aufklaeung", "aufkläung"),
    (r"gefaellt", "gefällt"),
    (r"gueltiger", "gültiger"),
    (r"oberflaechen", "oberflächen"),
    (r"regulaerer", "regulärer"),
    (r"aufloesungen", "auflösungen"),
    (r"ausfuellen", "ausfüllen"),
    (r"staerkste", "stärkste"),
    (r"abhaengt", "abhängt"),
    (r"schluesselverwaltung", "schlüsselverwaltung"),
    (r"zaeh", "zäh"),
    (r"fehleranfaellig", "fehleranfällig"),
    (r"mitgeloescht", "mitgelöscht"),
    (r"sprachbloecke", "sprachblöcke"),
    (r"zurueckgespielt", "zurückgespielt"),
    (r"uebersieht", "übersieht"),
    (r"zurueckkehrt", "zurückkehrt"),
    (r"gruener", "grüner"),
    (r"grosste", "großte"),
    (r"ueberlappen", "überlappen"),
    (r"pruefst", "prüfst"),
    (r"zeichenvorgaenge", "zeichenvorgänge"),
    (r"grueesse", "grüesse"),
    (r"ueberladung", "überladung"),
    (r"uebersprungenen", "übersprungenen"),
    (r"gebuendelte", "gebündelte"),
    (r"schluesselbytes", "schlüsselbytes"),
    (r"typpruefung", "typprüfung"),
    (r"aufloesungsreihenfolge", "auflösungsreihenfolge"),
    (r"aepfel", "äpfel"),
    (r"zusammenhaengende", "zusammenhängende"),
    (r"regulaeres", "reguläres"),
    (r"geprueften", "geprüften"),
    (r"unabhaengige", "unabhängige"),
    (r"woertlich", "wörtlich"),
    (r"ergaebe", "ergäbe"),
    (r"zurueckgerollt", "zurückgerollt"),
    (r"erwaehnt", "erwähnt"),
    (r"temporaeren", "temporären"),
    (r"vorpruefung", "vorprüfung"),
    (r"anfuehrungszeichen", "anführungszeichen"),
    (r"signaturaenderung", "signaturänderung"),
    (r"rueckgabetyp", "rückgabetyp"),
    (r"binaer", "binär"),
    (r"verifikationspruefung", "verifikationsprüfung"),
    (r"beruecksichtigt", "berücksichtigt"),
    (r"waehlbare", "wählbare"),
    (r"aussagekraeftig", "aussagekräftig"),
    (r"eigenstaendigkeit", "eigenständigkeit"),
    (r"sprachlaeufe", "sprachläufe"),
    (r"gesaettigt", "gesättigt"),
    (r"unuebersetzter", "unübersetzter"),
    (r"aufzaehlungszeichen", "aufzählungszeichen"),
    (r"ueberblick", "überblick"),
    (r"duennen", "dünnen"),
    (r"vollgroesse", "vollgrösse"),
    (r"hoehen", "höhen"),
    (r"uebernahme", "übernahme"),
    (r"huellkurve", "hüllkurve"),
    (r"grosszuegig", "großzügig"),
    (r"fensterhoehe", "fensterhöhe"),
    (r"koerperbreite", "körperbreite"),
    (r"zurueckgezeichnet", "zurückgezeichnet"),
    (r"vergroessert", "vergrössert"),
    (r"aehnlich", "ähnlich"),
    (r"symbolhoehe", "symbolhöhe"),
    (r"waechsen", "wächsen"),
    (r"aeusseren", "äusseren"),
    (r"kastenhoehe", "kastenhöhe"),
    (r"raende", "rände"),
    (r"verlaeuft", "verläuft"),
    (r"hoehenbegrenzung", "höhenbegrenzung"),
    (r"blockhoehe", "blockhöhe"),
    (r"einloest", "einlöst"),
    (r"gegenstuecke", "gegenstücke"),
    (r"absaetze", "absätze"),
    (r"originalgroesse", "originalgrösse"),
    (r"womoeglich", "womöglich"),
    (r"haertungen", "härtungen"),
    (r"stoerfall", "störfall"),
    (r"fuehrten", "führten"),
    (r"unschaedlich", "unschädlich"),
    (r"zurueckgenommenen", "zurückgenommenen"),
    (r"generationszaehler", "generationszähler"),
    (r"uebernahm", "übernahm"),
    (r"pruefwerkzeuge", "prüfwerkzeuge"),
    (r"bestaetigungspflicht", "bestätigungspflicht"),
    (r"benoetigter", "benötigter"),
    (r"durchgefuehrt", "durchgeführt"),
    (r"bildschirmablaeufe", "bildschirmabläufe"),
    (r"ausgeraeumt", "ausgeräumt"),
    (r"standardsmaessige", "standardsmässige"),
    (r"zurueckliegt", "zurückliegt"),
    (r"pruefkommandos", "prüfkommandos"),
    (r"gehaertet", "gehärtet"),
    (r"reziprozitaetsfilter", "reziprozitätsfilter"),
    (r"taeglicher", "täglicher"),
    (r"aenderbar", "änderbar"),
    (r"autoerkennung", "autörkennung"),
    (r"dateigroessen", "dateigrössen"),
    (r"haeufiger", "häufiger"),
    (r"nuernberg", "nürnberg"),
    (r"ruehrt", "rührt"),
    (r"persoenlich", "persönlich"),
    (r"abwaegung", "abwägung"),
    (r"gegenpruefen", "gegenprüfen"),
    (r"endpruefung", "endprüfung"),
    (r"einruecken", "einrücken"),
    (r"gekuendigt", "gekündigt"),
    (r"zuerich", "zürich"),
    (r"verknuepft", "verknüpft"),
    (r"braeuchten", "bräuchten"),
    (r"erklaerungs", "erklärungs"),
    (r"schuechterne", "schüchterne"),
    (r"privatsphaere", "privatsphäre"),
    (r"unregelmaessig", "unregelmässig"),
    (r"zuverlaessiger", "zuverlässiger"),
    (r"stoeberst", "stöberst"),
    (r"haettest", "hättest"),
    (r"loesungsweg", "lösungsweg"),
    (r"ueberblicken", "überblicken"),
    (r"gebuendelt", "gebündelt"),
    (r"lokalitaet", "lokalität"),
    (r"befuelltes", "befülltes"),
    (r"identitaetsverifikation", "identitätsverifikation"),
    (r"veroeffentlichen", "veröffentlichen"),
    (r"uebergebene", "übergebene"),
    (r"stroeme", "ströme"),
    (r"haarlaengen", "haarlängen"),
    (r"minderjaehrig", "minderjährig"),
    (r"loeschkette", "löschkette"),
    (r"ueberlebten", "überlebten"),
    (r"ueberdimensionierung", "überdimensionierung"),
    (r"ueberprueft", "überprüft"),
    (r"stuendlich", "stündlich"),
    (r"waehlte", "wählte"),
    (r"zurueckholen", "zurückholen"),
    (r"geraeteklasse", "geräteklasse"),
    (r"grosszuehige", "großzühige"),
    (r"zwangslaeufig", "zwangsläufig"),
    (r"umstaenden", "umständen"),
    (r"gruende", "gründe"),
    (r"vergleichsgroesse", "vergleichsgrösse"),
    (r"ueberschneiden", "überschneiden"),
    (r"absenderidentitaet", "absenderidentität"),
    (r"braeren", "brären"),
    (r"geruest", "gerüst"),
    (r"geraests", "gerästs"),
    (r"nutzeroberflaeche", "nutzeroberfläche"),
    (r"leerfaelle", "leerfälle"),
    (r"kuerzerer", "kürzerer"),
    (r"uebersehen", "übersehen"),
    (r"stuerzte", "stürzte"),
    (r"haengendes", "hängendes"),
    (r"rueckschritt", "rückschritt"),
    (r"einrueckungs", "einrückungs"),
    (r"nachzaehlen", "nachzählen"),
    (r"aufgeklaert", "aufgeklärt"),
    (r"ausdruecklicher", "ausdrücklicher"),
    (r"ausfuehrlich", "ausführlich"),
    (r"knoepfen", "knöpfen"),
    (r"whaehrend", "whährend"),
    (r"quetschten", "qütschten"),
    (r"lesebestaetigung", "lesebestätigung"),
    (r"praesenz", "präsenz"),
    (r"zaehlung", "zählung"),
    (r"sinngemaessen", "sinngemässen"),
    (r"ausdruecksform", "ausdrücksform"),
    (r"fuellte", "füllte"),
    (r"spuerbarer", "spürbarer"),
    (r"sperrflaeche", "sperrfläche"),
    (r"gewuenscht", "gewünscht"),
    (r"zurueckgelegte", "zurückgelegte"),
    (r"ueberzeichnen", "überzeichnen"),
    (r"fluessiger", "flüssiger"),
    (r"gedaempften", "gedämpften"),
    (r"ueberschritten", "überschritten"),
    (r"fuehlt", "fühlt"),
    (r"zoeodert", "zöodert"),
    (r"waech", "wäch"),
    (r"zuruecklegt", "zurücklegt"),
    (r"zuruecksprang", "zurücksprang"),
    (r"unschoen", "unschön"),
    (r"zurueckfedern", "zurückfedern"),
    (r"zuruecklegen", "zurücklegen"),
    (r"raeumlich", "räumlich"),
    (r"laege", "läge"),
    (r"ausgewaehlten", "ausgewählten"),
    (r"drueber", "drüber"),
    (r"missverstaendlich", "missverständlich"),
    (r"maessigen", "mässigen"),
    (r"mindesthoehe", "mindesthöhe"),
    (r"zurueckweisung", "zurückweisung"),
    (r"ausdrueckliches", "ausdrückliches"),
    (r"spruenge", "sprünge"),
    (r"weitergeblaettert", "weitergeblättert"),
    (r"aufgewaecht", "aufgewächt"),
    (r"zurueckbringen", "zurückbringen"),
    (r"kuer", "kür"),
    (r"naturgroesse", "naturgrösse"),
    (r"bundeslaender", "bundesländer"),
    (r"hoeberem", "höberem"),
    (r"zurueckgehen", "zurückgehen"),
    (r"zurueckgegangen", "zurückgegangen"),
    (r"ruecken", "rücken"),
    (r"plausibilitaet", "plausibilität"),
    (r"zurueckersetzen", "zurückersetzen"),
    (r"unguenstigste", "ungünstigste"),
    (r"verzoegerter", "verzögerter"),
    (r"pruefungsort", "prüfungsort"),
    (r"ausdruecke", "ausdrücke"),
    (r"belaestigung", "belästigung"),
    (r"bewaehrt", "bewährt"),
    (r"aufflaechen", "aufflächen"),
    (r"zerstoererisch", "zerstörerisch"),
    (r"druecke", "drücke"),
    (r"profilaenderung", "profiländerung"),
    (r"unbeschraenkt", "unbeschränkt"),
    (r"ergaenzung", "ergänzung"),
    (r"irrefuehrendem", "irreführendem"),
    (r"verschluesselter", "verschlüsselter"),
    (r"kanaloeffnung", "kanalöffnung"),
    (r"zugaenglich", "zugänglich"),
    (r"voelliges", "völliges"),
    (r"nuetzlich", "nützlich"),
    (r"aussaehe", "aussähe"),
    (r"zukuenftig", "zukünftig"),
    (r"handpruefung", "handprüfung"),
    (r"dazugehoeren", "dazugehören"),
    (r"aufgeloestes", "aufgelöstes"),
    (r"uebersetzungsschluessel", "übersetzungsschlüssel"),
    (r"loeschdienste", "löschdienste"),
    (r"aelteres", "älteres"),
    (r"tatsaechlichem", "tatsächlichem"),
    (r"schluesselverteilung", "schlüsselverteilung"),
    (r"loeschende", "löschende"),
    (r"voruebergehend", "vorübergehend"),
    (r"binaernachricht", "binärnachricht"),
    (r"behaelt", "behält"),
    (r"geraetemodell", "gerätemodell"),
    (r"temporaere", "temporäre"),
    (r"uebermittelt", "übermittelt"),
    (r"zurueckgelesen", "zurückgelesen"),
    (r"auffaelligen", "auffälligen"),
    (r"unverschluesselter", "unverschlüsselter"),
    (r"zurueckblinzelt", "zurückblinzelt"),
    (r"hoechstzahl", "höchstzahl"),
    (r"aeltesten", "ältesten"),
    (r"verschluesselungsschluessel", "verschlüsselungsschlüssel"),
    (r"projektabhaengig", "projektabhängig"),
    (r"dazugefuegt", "dazugefügt"),
    (r"aufgefuehrten", "aufgeführten"),
    (r"waehrenddessen", "währenddessen"),
    (r"testaerkenden", "testärkenden"),
    (r"laengere", "längere"),
    (r"kopfhoerer", "kopfhörer"),
    (r"unverschluesselt", "unverschlüsselt"),
    (r"grossflaechige", "großflächige"),
    (r"bildschirmfuellende", "bildschirmfüllende"),
    (r"laendern", "ländern"),
    (r"koordinatenaenderung", "koordinatenänderung"),
    (r"unzulaessig", "unzulässig"),
    (r"primaerfarbe", "primärfarbe"),
    (r"foermiger", "förmiger"),
    (r"linksbuendige", "linksbündige"),
    (r"fuellig", "füllig"),
    (r"tastaturhuelle", "tastaturhülle"),
    (r"einzufuegen", "einzufügen"),
    (r"fremdgeraet", "fremdgerät"),
    (r"dunkelblauem", "dunkelblaüm"),
    (r"ueberragen", "überragen"),
    (r"hoechstbreite", "höchstbreite"),
    (r"moeglicherweise", "möglicherweise"),
    (r"zugkoerper", "zugkörper"),
    (r"spurgroesse", "spurgrösse"),
    (r"duennere", "dünnere"),
    (r"zeichenstaerke", "zeichenstärke"),
    (r"konturstaerke", "konturstärke"),
    (r"entwuerfe", "entwürfe"),
    (r"fuenfmal", "fünfmal"),
    (r"willkuer", "willkür"),
    (r"ausfuellte", "ausfüllte"),
    (r"duennerer", "dünnerer"),
    (r"nadeloehr", "nadelöhr"),
    (r"bogenstaerke", "bogenstärke"),
    (r"anhoert", "anhört"),
    (r"huerde", "hürde"),
    (r"pillfoermige", "pillförmige"),
    (r"zustaenden", "zuständen"),
    (r"displaygroesse", "displaygrösse"),
    (r"aufzuloesen", "aufzulösen"),
    (r"drueckte", "drückte"),
    (r"unzulaessiger", "unzulässiger"),
    (r"bekaeme", "bekäme"),
    (r"unzulaessige", "unzulässige"),
    (r"ueblicher", "üblicher"),
    (r"schwarzflaeche", "schwarzfläche"),
    (r"uebergaengen", "übergängen"),
    (r"ueberschreitung", "überschreitung"),
    (r"ablaeuft", "abläuft"),
    (r"frueherige", "früherige"),
    (r"fuenffach", "fünffach"),
    (r"binaere", "binäre"),
    (r"fuenfstufiger", "fünfstufiger"),
    (r"staerkeres", "stärkeres"),
    (r"baenke", "bänke"),
    (r"zaehlfunktionen", "zählfunktionen"),
    (r"gehoerte", "gehörte"),
    (r"waechseln", "wächseln"),
    (r"zurueckweisen", "zurückweisen"),
    (r"geraetename", "gerätename"),
    (r"gestoert", "gestört"),
    (r"unbestaetigten", "unbestätigten"),
    (r"aufwaermen", "aufwärmen"),
    (r"erfuellen", "erfüllen"),
    (r"sperrpruefung", "sperrprüfung"),
    (r"urspruenglich", "ursprünglich"),
    (r"bestaetigtes", "bestätigtes"),
    (r"zuruecklassen", "zurücklassen"),
    (r"unauffaelligen", "unauffälligen"),
    (r"gewuenschter", "gewünschter"),
    (r"verschluesselungsdienst", "verschlüsselungsdienst"),
    (r"bestaetigten", "bestätigten"),
    (r"bestaetigtem", "bestätigtem"),
    (r"bestaetigungsschleife", "bestätigungsschleife"),
    (r"mitabwuergen", "mitabwürgen"),
    (r"zeitueberschreitung", "zeitüberschreitung"),
    (r"kuenstlich", "künstlich"),
    (r"abstuerzte", "abstürzte"),
    (r"uebersetzte", "übersetzte"),
    (r"pfadpruefung", "pfadprüfung"),
    (r"gespraeche", "gespräche"),
    (r"naemen", "nämen"),
    (r"bloecken", "blöcken"),
    (r"schluessels", "schlüssels"),
    (r"gedaechtnis", "gedächtnis"),
    (r"verschluesselungsdienstes", "verschlüsselungsdienstes"),
    (r"dazugehoert", "dazugehört"),
    (r"nachrichtenloeschen", "nachrichtenlöschen"),
    (r"uebersteht", "übersteht"),
    (r"entschluesselbar", "entschlüsselbar"),
    (r"entschluesselungsweg", "entschlüsselungsweg"),
    (r"bestandspruefung", "bestandsprüfung"),
    (r"ausgaenge", "ausgänge"),
    (r"sprachluecke", "sprachlücke"),
    (r"boesartig", "bösartig"),
    (r"stuertzt", "stürtzt"),
    (r"schluesselsatz", "schlüsselsatz"),
    (r"binaerhuelle", "binärhülle"),
    (r"haengenden", "hängenden"),
    (r"haenge", "hänge"),
    (r"hoehenlos", "höhenlos"),
    (r"kuenftige", "künftige"),
    (r"bestaetigungsstand", "bestätigungsstand"),
    (r"eingaenge", "eingänge"),
    (r"nachpruefung", "nachprüfung"),
    (r"zurueckpoppen", "zurückpoppen"),
    (r"bestaetigungsknopf", "bestätigungsknopf"),
    (r"haekchen", "häkchen"),
    (r"zurueckspringen", "zurückspringen"),
    (r"zeitueberlauf", "zeitüberlauf"),
    (r"ausgewaehlter", "ausgewählter"),
    (r"anwaehlen", "anwählen"),
    (r"knoepfchen", "knöpfchen"),
    (r"entzueenden", "entzüenden"),
    (r"gekuehlte", "gekühlte"),
    (r"entzuendeten", "entzündeten"),
    (r"zurueckziehen", "zurückziehen"),
    (r"noerdlich", "nördlich"),
    (r"oestlich", "östlich"),
    (r"zurueckgerutschter", "zurückgerutschter"),
    (r"verzoegert", "verzögert"),
    (r"nachgefuehrt", "nachgeführt"),
    (r"umgefuehrt", "umgeführt"),
    (r"groessengrenze", "größengrenze"),
    (r"loeschenden", "löschenden"),
    (r"persoenliche", "persönliche"),
    (r"zusammengehoeren", "zusammengehören"),
    (r"aussaehen", "aussähen"),
    (r"geburtstagsflaeche", "geburtstagsfläche"),
    (r"schwaeche", "schwäche"),
    (r"waer", "wär"),
    (r"geraeteinformationen", "geräteinformationen"),
    (r"geraeteinformation", "geräteinformation"),
    (r"testfaelle", "testfälle"),
    (r"haengenbleiben", "hängenbleiben"),
    (r"kernstueck", "kernstück"),
    (r"anfuehlen", "anfühlen"),
    (r"aeusserste", "äusserste"),
    (r"weiterzaehlt", "weiterzählt"),
    (r"muelleimer", "mülleimer"),
    (r"zurueckspringt", "zurückspringt"),
    (r"persoenlichkeitstypen", "persönlichkeitstypen"),
    (r"gewuenschtes", "gewünschtes"),
    (r"erklaerungskommentar", "erklärungskommentar"),
    (r"moegen", "mögen"),
    (r"anstoessige", "anstössige"),
    (r"bildpruefung", "bildprüfung"),
    (r"anstoessig", "anstössig"),
    (r"oesterreich", "österreich"),
    (r"ueberlauf", "überlauf"),
    (r"eingeschraenkt", "eingeschränkt"),
    (r"ueberstrahlt", "überstrahlt"),
    (r"herzensstaerken", "herzensstärken"),
    (r"rueckfallebene", "rückfallebene"),
    (r"leerzustaenden", "leerzuständen"),
    (r"serverzaehler", "serverzähler"),
    (r"zusaetzlichen", "zusätzlichen"),
    (r"kuehlen", "kühlen"),
    (r"zurueckgekommen", "zurückgekommen"),
    (r"bildschirmgroesse", "bildschirmgrösse"),
    (r"begruendet", "begründet"),
    (r"angewaehlt", "angewählt"),
    (r"endgueltige", "endgültige"),
    (r"weiterblaettern", "weiterblättern"),
    (r"geaenderten", "geänderten"),
    (r"einlaesst", "einlässt"),
    (r"inhaltshoehe", "inhaltshöhe"),
    (r"dateikoepfe", "dateiköpfe"),
    (r"ungewoehnlich", "ungewöhnlich"),
    (r"innehaelt", "innehält"),
    (r"schwaeren", "schwären"),
    (r"kraenkend", "kränkend"),
    (r"grosses", "großes"),
    (r"aufloesungsunabhaengig", "auflösungsunabhängig"),
    (r"volljaehrigen", "volljährigen"),
    (r"einhaengen", "einhängen"),
    (r"bildgroesse", "bildgrösse"),
    (r"gaelte", "gälte"),
    (r"aenderungszeit", "änderungszeit"),
    (r"aufraeums", "aufräums"),
    (r"ueberstehen", "überstehen"),
    (r"videolaenge", "videolänge"),
    (r"ausloeste", "auslöste"),
    (r"loeschbaren", "löschbaren"),
    (r"zerstoererischer", "zerstörerischer"),
    (r"abstuerzt", "abstürzt"),
    (r"testflaeche", "testfläche"),
    (r"mitlaeuft", "mitläuft"),
    (r"abgeprueft", "abgeprüft"),
    (r"aergerlicher", "ärgerlicher"),
    (r"auswahlmoeglichkeiten", "auswahlmöglichkeiten"),
    (r"abschnittsueberschrift", "abschnittsüberschrift"),
    (r"taeglich", "täglich"),
    (r"abwaehlen", "abwählen"),
    (r"stuenden", "stünden"),
    (r"juengsten", "jüngsten"),
    (r"geraetedrehung", "gerätedrehung"),
    (r"haendler", "händler"),
    (r"zurueckgespiegelt", "zurückgespiegelt"),
    (r"nachpruefen", "nachprüfen"),
    (r"ueberzuppringen", "überzuppringen"),
    (r"ueberlaesst", "überlässt"),
    (r"formulierungsaenderung", "formulierungsänderung"),
    (r"unausloeslich", "unauslöslich"),
    (r"teilstuecke", "teilstücke"),
    (r"durchschlaegt", "durchschlägt"),
    (r"augenmaessung", "augenmässung"),
    (r"farbkanaele", "farbkanäle"),
    (r"ueberlagerungen", "überlagerungen"),
    (r"fehlerzustaende", "fehlerzustände"),
    (r"ueberschneidungsflaeche", "überschneidungsfläche"),
    (r"schnittflaeche", "schnittfläche"),
    (r"alterschaetzung", "alterschätzung"),
    (r"ueberlappende", "überlappende"),
    (r"ausgewaehlte", "ausgewählte"),
    (r"vernachlaessigbar", "vernachlässigbar"),
    (r"muetze", "mütze"),
    (r"erklaerende", "erklärende"),
    (r"schwaecher", "schwächer"),
    (r"signalstaerke", "signalstärke"),
    (r"schluesselpruefungen", "schlüsselprüfungen"),
    (r"ueberfuellt", "überfüllt"),
    (r"vorschlaegen", "vorschlägen"),
    (r"zusammenhaengender", "zusammenhängender"),
    (r"uebertrieben", "übertrieben"),
    (r"abgeraeumten", "abgeräumten"),
    (r"praezision", "präzision"),
    (r"lueftiger", "lüftiger"),
    (r"wegkuerzen", "wegkürzen"),
    (r"aenderungstabelle", "änderungstabelle"),
    (r"syntaxpruefung", "syntaxprüfung"),
    (r"auszufuehren", "auszuführen"),
    (r"ausfuehrungsrichtlinie", "ausführungsrichtlinie"),
    (r"ueberladungen", "überladungen"),
    (r"routinemaessig", "routinemässig"),
    (r"altersschaetzer", "altersschätzer"),
    (r"uebergangen", "übergangen"),
    (r"zusammenfuehren", "zusammenführen"),
    (r"signaturpruefung", "signaturprüfung"),
    (r"moeglichen", "möglichen"),
    (r"beruecksichtigen", "berücksichtigen"),
    (r"vollstaendiges", "vollständiges"),
    (r"schluesselnamen", "schlüsselnamen"),
    (r"boesen", "bösen"),
    (r"boese", "böse"),
    (r"aufraeumlauf", "aufräumlauf"),
    (r"pruef", "prüf"),
    (r"pruefern", "prüfern"),
    (r"alterskompatibilitaet", "alterskompatibilität"),
    (r"veraendertes", "verändertes"),
    (r"parserluecke", "parserlücke"),
    (r"entschaerfen", "entschärfen"),
    (r"rueckdekodierung", "rückdekodierung"),
    (r"tatsaetzlich", "tatsätzlich"),
    (r"muessten", "müssten"),
    (r"erwaehnung", "erwähnung"),
    (r"widerspruechlich", "widersprüchlich"),
    (r"aufraeumung", "aufräumung"),
    (r"einheitenabkuerzung", "einheitenabkürzung"),
    (r"realitaet", "realität"),
    (r"unausgefuellte", "unausgefüllte"),
    (r"fuellbar", "füllbar"),
    (r"staendig", "ständig"),
    (r"binaerdatei", "binärdatei"),
    (r"uebereinstimmt", "übereinstimmt"),
    (r"zurueckbleibt", "zurückbleibt"),
    (r"zeilenumbruechen", "zeilenumbrüchen"),
    (r"ueblich", "üblich"),
    (r"vollpruefung", "vollprüfung"),
    (r"ladungsfaehige", "ladungsfähige"),
    (r"rueckabetyp", "rückabetyp"),
    (r"ueberladene", "überladene"),
    (r"aelttere", "älttere"),
    (r"geloeschten", "gelöschten"),
    (r"muendlich", "mündlich"),
    (r"geaendertes", "geändertes"),
    (r"geaenderte", "geänderte"),
    (r"geaecherten", "geächerten"),
    (r"kontaminationspruefung", "kontaminationsprüfung"),
    (r"stoerung", "störung"),
    (r"kuenstliche", "künstliche"),
    (r"saemtliche", "sämtliche"),
    (r"erwaehnte", "erwähnte"),
    (r"taeuschen", "täuschen"),
    (r"aerger", "ärger"),
    (r"fenstergroesse", "fenstergrösse"),
    (r"ueberbruecken", "überbrücken"),
    (r"ueberzaehligen", "überzähligen"),
    (r"hoehere", "höhere"),
    (r"gegenlaeufige", "gegenläufige"),
    (r"privatsphaerenschutz", "privatsphärenschutz"),
    (r"hinzugefuegte", "hinzugefügte"),
    (r"hinzugefuegten", "hinzugefügten"),
    (r"schriftgroessen", "schriftgrössen"),
    (r"klammerzzaehlen", "klammerzzählen"),
    (r"spaeteste", "späteste"),
    (r"urspruenglichen", "ursprünglichen"),
    (r"funktionskoerpers", "funktionskörpers"),
    (r"wegfaellt", "wegfällt"),
    (r"haelte", "hälte"),
    (r"angriffsflaeche", "angriffsfläche"),
    (r"mitloescht", "mitlöscht"),
    (r"unvollstaendigen", "unvollständigen"),
    (r"unauffaelliger", "unauffälliger"),
    (r"genuegen", "genügen"),
    (r"kanaelen", "kanälen"),
    (r"volatilitaet", "volatilität"),
    (r"aenderungstext", "änderungstext"),
    (r"vollstaendigkeit", "vollständigkeit"),
    (r"ueberschreitet", "überschreitet"),
    (r"kachelhoehe", "kachelhöhe"),
    (r"screenhoehe", "screenhöhe"),
    (r"uebergrossen", "übergrossen"),
    (r"datenschutzerklaerlung", "datenschutzerklärlung"),
    (r"erwaehnungen", "erwähnungen"),
    (r"saetzen", "sätzen"),
    (r"faenge", "fänge"),
    (r"woert", "wört"),
    (r"stammwoerter", "stammwörter"),
    (r"uebermotive", "übermotive"),
    (r"qualitaetspruefer", "qualitätsprüfer"),
    (r"prueften", "prüften"),
    (r"qualitaetspruefung", "qualitätsprüfung"),
    (r"ueberlagert", "überlagert"),
    (r"aenderte", "änderte"),
    (r"invaliditaet", "invalidität"),
    (r"abhaengigkeitsfrei", "abhängigkeitsfrei"),
    (r"grundgroesse", "grundgrösse"),
    (r"zeilenlaenge", "zeilenlänge"),
    (r"rueckte", "rückte"),
    (r"eigenstaendigen", "eigenständigen"),
    (r"eingefuegten", "eingefügten"),
    (r"eigenstaendige", "eigenständige"),
    (r"laeufen", "läufen"),
    (r"kreissilhouette", "kreissilhoütte"),
    (r"saettigungs", "sättigungs"),
    (r"loecher", "löcher"),
    (r"sichtpruefung", "sichtprüfung"),
    (r"vollflaechig", "vollflächig"),
    (r"koepfe", "köpfe"),
    (r"verfaelscht", "verfälscht"),
    (r"gleichgueltig", "gleichgültig"),
    (r"loesen", "lösen"),
    (r"gleichmaessigem", "gleichmässigem"),
    (r"seitenverhaelt", "seitenverhält"),
    (r"ueberabtastet", "überabtastet"),
    (r"kantenverlaengert", "kantenverlängert"),
    (r"vorwaerts", "vorwärts"),
    (r"groesserer", "größerer"),
    (r"begruenden", "begründen"),
    (r"eigenstaendig", "eigenständig"),
    (r"ablaeufe", "abläufe"),
    (r"annaeherung", "annäherung"),
    (r"kraeftiger", "kräftiger"),
    (r"verlaufsflaeche", "verlaufsfläche"),
    (r"kraeftigste", "kräftigste"),
    (r"allerstaerkste", "allerstärkste"),
    (r"huellbreite", "hüllbreite"),
    (r"boegenhuellbreite", "bögenhüllbreite"),
    (r"verfaelschen", "verfälschen"),
    (r"tintenkaesten", "tintenkästen"),
    (r"mitgefuehrt", "mitgeführt"),
    (r"spaltenluecke", "spaltenlücke"),
    (r"tintenhoehe", "tintenhöhe"),
    (r"ueberzeugt", "überzeugt"),
    (r"farbverlaeufe", "farbverläufe"),
    (r"geraetemasse", "gerätemasse"),
    (r"zeitgeraeten", "zeitgeräten"),
    (r"rueckfallloesung", "rückfalllösung"),
    (r"akkukoerpers", "akkukörpers"),
    (r"geraetefeld", "gerätefeld"),
    (r"fuehrendes", "führendes"),
    (r"ziffernhoeh", "ziffernhöh"),
    (r"ziffernhoehe", "ziffernhöhe"),
    (r"kuerzeste", "kürzeste"),
    (r"missverstaendnis", "missverständnis"),
    (r"straeche", "sträche"),
    (r"ueberlaeuft", "überläuft"),
    (r"schaedlich", "schädlich"),
    (r"fuellungskante", "füllungskante"),
    (r"geschaetzte", "geschätzte"),
    (r"naeherungen", "näherungen"),
    (r"verhaeltnissen", "verhältnissen"),
    (r"natuerliches", "natürliches"),
    (r"geraetekorpus", "gerätekorpus"),
    (r"darueberliegen", "darüberliegen"),
    (r"dunkelblaue", "dunkelblaü"),
    (r"zusaetzlicher", "zusätzlicher"),
    (r"groesseren", "größeren"),
    (r"groesster", "größter"),
    (r"ueberdecken", "überdecken"),
    (r"kuerze", "kürze"),
    (r"ueberschriftskachel", "überschriftskachel"),
    (r"zeilenabstaende", "zeilenabstände"),
    (r"leerraeume", "leerräume"),
    (r"fuenfzehn", "fünfzehn"),
    (r"rasterhoehe", "rasterhöhe"),
    (r"zirkulaer", "zirkulär"),
    (r"flaechen", "flächen"),
    (r"glaettet", "glättet"),
    (r"haelften", "hälften"),
    (r"unbegruendete", "unbegründete"),
    (r"zerstueckeltes", "zerstückeltes"),
    (r"ueberschriftenposition", "überschriftenposition"),
    (r"durchlaeufe", "durchläufe"),
    (r"beschaedigte", "beschädigte"),
    (r"staenden", "ständen"),
    (r"verdraengt", "verdrängt"),
    (r"zaeunen", "zäunen"),
    (r"zaeune", "zäune"),
    (r"zerstoerte", "zerstörte"),
    (r"pruefmittel", "prüfmittel"),
    (r"gaenstriche", "gänstriche"),
    (r"unaufgeloeste", "unaufgelöste"),
    (r"zusatzabhaengigkeiten", "zusatzabhängigkeiten"),
    (r"eingeraenkt", "eingeränkt"),
    (r"entsaettetes", "entsättetes"),
    (r"breitenpruefung", "breitenprüfung"),
    (r"anlaengeuehr", "anlängeühr"),
    (r"anlaenge", "anlänge"),
    (r"spielexpectspruefung", "spielexpectsprüfung"),
    (r"ausgefuehrte", "ausgeführte"),
    (r"mitfuehren", "mitführen"),
    (r"schraenkt", "schränkt"),
    (r"wuehlen", "wühlen"),
    (r"nachaendert", "nachändert"),
    (r"benoetigten", "benötigten"),
    (r"gefaess", "gefäss"),
    (r"dateigroesse", "dateigrösse"),
    (r"umbrueche", "umbrüche"),
    (r"pruefmodus", "prüfmodus"),
    (r"formatunabhaengig", "formatunabhängig"),
    (r"gefaehrden", "gefährden"),
    (r"anhaengen", "anhängen"),
    (r"geschuetztem", "geschütztem"),
    (r"einzelauzaehlungen", "einzelauzählungen"),
    (r"zuruecklaesst", "zurücklässt"),
    (r"erklaerungspflicht", "erklärungspflicht"),
    (r"beschraenkt", "beschränkt"),
    (r"nachgeprueft", "nachgeprüft"),
    (r"gaenge", "gänge"),
    (r"kantenlaenge", "kantenlänge"),
]

# Die Muster werden einmal kompiliert (Wortgrenzen + Groß/Klein egal).
MUSTER = [
    (re.compile(r"\b" + muster + r"\b", re.IGNORECASE), korrekt)
    for muster, korrekt in WORTE
]

# ---------------------------------------------------------------------------
# Ausnahmen: Wörter, die ASCII geschrieben sein DÜRFEN.
#
# Jede Ausnahme braucht eine Begründung - sonst wird sie stillschweigend
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
    # unten auf seine Dateien aufgelöst.
    ("lib/l10n/strings", "strings_de_ordner"),
    ("lib/generated/privacy_policy_de.dart", "strings"),
    ("docs/recht/DATENSCHUTZ.md", "ganz"),
    ("README.md", "ganz"),
    # DIE WEBSEITEN: alle deutschen Seiten (ohne den Ordner "en").
    ("passkey-assets", "html_ordner_de"),
    # DIE STORE-TEXTE: alle Fassungen (nicht nur die letzten drei).
    ("fastlane/metadata/android/de-DE", "ganz_ordner_txt"),
    # DIE DOKUMENTE: der Betreiber liest sie - die Umlaute gehören
    # dort genauso hinein wie in den App-Texten.
    ("CHANGELOG.md", "ganz"),
    ("ROADMAP.md", "ganz"),
    ("docs", "ganz_ordner_md"),
    ("releases", "ganz_ordner_md"),
    # DIE KOMMENTARE IM DAHIN: seit dem 25.11.2026 stehen dort auch
    # die echten Umlaute (vorher: bewusst ASCII).
    ("lib", "kommentare_ordner"),
    ("test", "kommentare_ordner"),
    ("tool", "kommentare_ordner"),
]


def _folgt_doppelpunkt(text: str, pos: int) -> bool:
    """Steht nach dem String-Literal ein Doppelpunkt? Dann ist es der
    Schlüssel einer Karte (und nicht der Wert)."""
    while pos < len(text) and text[pos] in " \t":
        pos += 1
    return pos < len(text) and text[pos] == ":"


def lies_string_literale(
    text: str, mit_ist_wert: bool = False
) -> list[tuple[int, str]] | list[tuple[int, str, bool]]:
    """Holt die String-Literale (mit Zeilennummer) aus einem Quelltext.

    Kommentare werden übersprungen - die sind im Projekt bewusst ASCII.
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
                _ist_wert = not _folgt_doppelpunkt(text, i)
                if mit_ist_wert:
                    treffer.append((start_zeile, "".join(inhalt), _ist_wert))
                else:
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
            _ist_wert = not _folgt_doppelpunkt(text, i)
            if mit_ist_wert:
                treffer.append((start_zeile, "".join(inhalt), _ist_wert))
            else:
                treffer.append((start_zeile, "".join(inhalt)))
            continue
        i += 1
    return treffer


def _ohne_zeilenwechsel(text: str, ersatz: str) -> str:
    """Ersetzt Text, ohne die Zeilennummern zu verschieben.

    Wichtig: der Ersatz muss dieselbe Zahl Zeilenumbrüche haben wie
    der Originaltext - sonst stimmen die gemeldeten Zeilen nicht mehr.
    """
    return re.sub(
        r"[^\n]",
        lambda _treffer: ersatz if ersatz != "" else " ",
        text,
    )


def kommentarzeilen(text: str) -> list[tuple[int, str]]:
    """Holt die Kommentarzeilen aus einem Quelltext (mit Zeilennummer).

    DER WEG: Zeilen, die mit "//" (Dart) oder "#" (Python, PowerShell)
    beginnen. Die Strings (Nutzertexte, Bezeichner) bleiben unangetastet.
    """
    zeilen = []
    for nummer, zeile in enumerate(text.split("\n"), start=1):
        eingerueckt = zeile.lstrip()
        if eingerueckt.startswith("//"):
            zeilen.append((nummer, zeile[zeile.find("//") :]))
        elif eingerueckt.startswith("#"):
            zeilen.append((nummer, zeile[zeile.find("#") :]))
    return zeilen


def ohne_code_und_urls(text: str) -> str:
    """Entfernt alles, was nicht nutzersichtbarer Text ist.

    - Inline-Code (`...`), URLs und HTML-Attribute
    - Script-, Style- und Kommentar-Blöcke (Code, kein Text)

    Die Zeilennummern bleiben dabei erhalten (die Zeilenumbrüche der
    entfernten Blöcke bleiben an Ort und Stelle).
    """
    # Script-, Style- und Kommentar-Blöcke: Inhalt raus, Zeilen bleiben.
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
    # Text-Attribute (alt, title, placeholder, aria-label) bleiben geprüft
    # - sie sind für Screenreader und Tooltips sichtbar.
    for muster in (
        r"`[^`]*`",
        r"https?://\S+",
        # DER HINWEIS: Der Wert eines Attributs steht in EINER Zeile.
        # Ohne diese Grenze frisst der Regex den Text bis zum nächst
        # Anführungszeichen - und der CSS-Klassenname (z.B.
        # "tabellen-hülle") wird dann fälschlich gemeldet.
        r"(?:href|src|content)\s*=\s*\"[^\n\"]*\"",
        r"(?:(?:id|class|style|d|points|viewBox|fill|stroke|xmlns|transform)"
        r"|data-[\w-]+)\s*=\s*\"[^\n\"]*\"",
        # DIE DATEINAMEN: "geraete.dart" ist ein Name, kein Prosatext.
        r"\b[\w-]+\.(?:dart|py|ps1|md|txt|json|ya?ml|html|css|js|xml|kts"
        r"|gradle|lock|properties|kt)\b",
        # DIE SCHLÜSSEL UND PFADE: "del.geraete" ist ein Bezeichner.
        r"\b[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\b",
        # DIE RELATIVEN PFADE: "/konto-loeschen" ist ein Link, kein Text.
        r"(?<![\w/])/[a-z0-9][\w./-]*",
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
                # DIE GESPERRTE SCHRIFT: Wer den ganzen Wortschatz in
                # Großbuchstaben schreibt, schreibt das "ss" als "SS" -
                # "GROSSE" ist richtig, "GROßE" nicht. Solche Wörter
                # sind deshalb KEIN Fund.
                if wort.isupper() and len(wort) > 1 and wort == korrekt.upper():
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
            # Der Ordner mit den Texten: jede Datei wird einzeln geprüft.
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
                for start_zeile, literal, ist_wert in lies_string_literale(
                    ausschnitt, mit_ist_wert=True
                ):
                    # NUR DIE WERTE: Der Schlüssel ("del.geraete") ist ein
                    # Bezeichner - er darf bleiben, wie er ist.
                    if not ist_wert:
                        continue
                    pruefe(
                        literal,
                        funde,
                        name,
                        basiszeile=basis + start_zeile - 1,
                    )
            continue
        if art == "html_ordner_de":
            # Der Ordner mit den Webseiten: jede deutsche Seite wird
            # einzeln geprüft (der Ordner "en" bleibt außen vor).
            for datei in sorted(pfad.rglob("*.html")):
                if "en" in datei.parts:
                    continue
                geprueft += 1
                rohtext = datei.read_text(encoding="utf-8", errors="replace")
                pruefe(
                    ohne_code_und_urls(rohtext),
                    funde,
                    str(datei.relative_to(ROOT)),
                )
            continue
        if art in ("ganz_ordner_md", "ganz_ordner_txt", "kommentare_ordner"):
            # Ein ganzer Ordner: jede passende Datei wird einzeln
            # geprüft.
            endung = {
                "ganz_ordner_md": ".md",
                "ganz_ordner_txt": ".txt",
                "kommentare_ordner": None,
            }[art]
            for datei in sorted(pfad.rglob("*")):
                if not datei.is_file():
                    continue
                if endung is not None and datei.suffix != endung:
                    continue
                if endung is None and datei.suffix not in (
                    ".dart",
                    ".py",
                    ".ps1",
                ):
                    continue
                geprueft += 1
                rohtext = datei.read_text(encoding="utf-8", errors="replace")
                name = str(datei.relative_to(ROOT))
                if art == "kommentare_ordner":
                    for nummer, kommentar in kommentarzeilen(rohtext):
                        # Inline-Code und URLs bleiben unangetastet - dort
                        # steht ein Bezeichner, kein Prosatext.
                        pruefe(
                            ohne_code_und_urls(kommentar),
                            funde,
                            name,
                            basiszeile=nummer - 1,
                        )
                else:
                    pruefe(ohne_code_und_urls(rohtext), funde, name)
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
            for start_zeile, literal, ist_wert in lies_string_literale(
                ausschnitt, mit_ist_wert=True
            ):
                # NUR DIE WERTE: Der Schlüssel ("del.geraete") ist ein
                # Bezeichner - er darf bleiben, wie er ist.
                if not ist_wert:
                    continue
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
    print("HINWEIS: Es wird ALLES geprueft - die App-Texte, die")
    print("Dokumente UND die Kommentare im Quelltext.")
    return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
