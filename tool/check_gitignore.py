"""Prueft die .gitignore auf Luecken in beide Richtungen.

Eine .gitignore ist nur eine Seite. Zu pruefen sind zwei Fragen, und die
zweite wird routinemaessig vergessen:

  1) Kommt alles Reinliche NICHT ins Repo?  (zu breite Regeln)
  2) Kommt nichts Geheimes INS Repo?         (zu schmale Regeln)

Fuer (2) ist die entscheidende Einsicht: .gitignore wirkt nur auf
UNVERSIONIERTE Dateien. Wer eine Datei einmal committet hat, laeuft
dauerhaft aus jeder Ignore-Regel heraus. Genau daran ist im Projekt ein
Firebase-API-Key gescheitert: android/app/google-services.json lag im
Initial-Commit und ist heute im oeffentlichen Verlauf sichtbar, obwohl
die Regel in Zeile 74 steht. Deshalb wird hier beides getrennt
geprueft und bei Trackern-Dateien ausdruecklich unterschieden.

Aufruf:
    python tool/check_gitignore.py
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(r'C:\Users\Thoralf\AppData\Local\Temp\opencode\gitignore_audit.txt')

# ---------------------------------------------------------------
# 1) Geheim-Muster: MUSS ignoriert sein, sonst geraten sie per
#    "git add -A" mit hoch.
# ---------------------------------------------------------------
SECRET_PATTERNS: list[tuple[str, str, str]] = [
    (r'(^|/)\.env(\..*)?$', 'Umgebungsdatei', 'Kann Supabase-Keys enthalten'),
    (r'(^|/)key\.properties$', 'Signing-Konfiguration', 'Enthaelt Keystore-Passwoerter'),
    (r'\.keystore$', 'Keystore', 'Enthaelt den privaten Schluessel'),
    (r'\.(jks|p12|pfx|pem|key)$', 'Schluesselmaterial', 'Privater Schluessel oder Zertifikat'),
    (r'\.mobileprovision$', 'iOS-Provisioning', 'Entwickler-Zertifikat'),
    (r'google-services\.json$', 'Firebase-Client-Config', 'Enthaelt den API-Key'),
    (r'GoogleService-Info\.plist$', 'Firebase-Client-Config', 'Enthaelt den API-Key'),
    (r'(^|/)service-account.*\.json$', 'Service-Account', 'Google-Cloud-Zugangsschluessel'),
    (r'(^|/)local\.properties$', 'Android-lokal', 'Enthaelt lokale SDK-Pfade'),
    (r'\.envrc$', 'direnv', 'Kann Schluessel enthalten'),
    (r'firebase_options\.dart$', 'Firebase-Options', 'Enthaelt den API-Key'),
]

# Ausnahmen, die bewusst versioniert werden
ALLOWED_TRACKED = {
    '.env.example',
    'android/app/google-services.json.example',
    # Beide Modelle sind laut .gitignore eine bewusste Betreiber-Entscheidung
    # (9f843fa): das 81-MB-Altersschaetzer-Modell bleibt draussen, die zwei
    # kleineren bleiben drin, damit die On-Device-Moderation im Repo
    # nachvollziehbar ist. Ohne Ausnahme meldet der Audit sie als
    # Beanstandung und wird damit bei jeder spaeteren echten Luecke
    # uebergangen.
    'assets/models/face_detector.onnx',
    'assets/models/image-safety-classifier-xs.onnx',
}

# ---------------------------------------------------------------
# 2) Build-Artefakte: MUESSEN ignoriert sein (Groesse, Binaries)
# ---------------------------------------------------------------
BUILD_PATTERNS = [
    (r'\.apk$', 'Release-APK'),
    (r'\.aab$', 'Android App Bundle'),
    (r'\.ipa$', 'iOS-App'),
    (r'\.onnx$', 'KI-Modell'),
    (r'\.so$', 'Native Bibliothek'),
    (r'^\.dart_tool/', 'Dart-Werkzeugcache'),
    (r'(^|/)build/', 'Build-Ausgabe'),
]

# Verzeichnisse, in denen nicht gesucht wird.
# .dart_tool gehoert ausdruecklich dazu: ohne diesen Eintrag laeuft der
# Audit durch den kompletten Werkzeugcache und meldet several tausend
# "OK ignoriert"-Zeilen fuer Dateien, die ohnehin niemanden interessieren.
# Der Cache ist per .gitignore abgedeckt - Abschnitt A prueft Regeln, nicht
# Cache-Inhalte.
SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.dart_tool',
             '.gradle', '.kotlin', 'ephemeral', 'Pods', '.symlinks'}

# Beide Listen auf dieselbe Form bringen: (muster, label, begruendung).
# SECRET_PATTERNS hat drei Felder, BUILD_PATTERNS zwei - das Zusammenfuehren
# mit anschliessendem Entpacken als Paar ist der Fehler, der hier zuerst
# aufgetreten ist. Eine gemeinsame Form ist die Ursache, nicht die
# Zusammenfuehrung.
ALL_PATTERNS: list[tuple[str, str, str]] = list(SECRET_PATTERNS) + [
    (pat, label, 'Build-Ausgabe, regenerierbar') for pat, label in BUILD_PATTERNS
]


def git(*args: str) -> str:
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True,
                          text=True, encoding='utf-8', errors='replace').stdout


def ignored(path: str) -> bool:
    r = subprocess.run(['git', 'check-ignore', '-q', '--', path], cwd=ROOT,
                       capture_output=True)
    return r.returncode == 0


# ---------------------------------------------------------------------
# PERFORMANCE (01.11.2026)
#
# BEFUND: Diese Pruefung hat den CI-Lauf minutenlang blockiert. Der
# Grund war nicht die Logik, sondern der Weg, wie sie gearbeitet hat:
#
#   Fuer JEDE Datei, die auf ein Muster passte, wurde ein eigener
#   `git check-ignore`-Prozess gestartet. Nach einem Release-Build
#   liegen unter build/ ueber 44 000 Dateien - und fast jede davon
#   passt auf `(^|/)build/` oder auf `\.so$`. Das waren also rund
#   44 000 git-Prozesse, jeder mit seinem eigenen Start, seiner
#   eigenen Index-Ladung und seiner eigenen Ausgabe.
#
#   Ein Hintergrundlauf war nach 15 Minuten noch nicht durch - und
#   zwei parallele Laeufe machten es nicht schneller.
#
# ZWEI GEGENMASSNAHMEN:
#
#   1) Die Ignore-Pruefung laeuft GESAMMELT. `git check-ignore
#      --stdin` nimmt viele Pfade auf einmal entgegen und liefert
#      die ignorierten zurueck. Aus 44 000 Prozessen wird EINE.
#
#   2) Die Traversierung beschneidet die Ordner, in denen ohnehin
#      nichts gefunden werden kann: build/ und releases/ sind
#      ignoriert - eine Datei dort kann also nie "NICHT IGNORIERT"
#      sein. os.walk mit dirs[:]-Beschneidung laeuft gar nicht erst
#      in sie hinein.
#
# BEIDES aendert das Ergebnis nicht: die Befunde sind dieselben. Was
# sich aendert, ist die Zahl in der Kopfzeile ("N Dateien
# durchsucht") - sie bezieht sich jetzt auf die durchsuchten Ordner
# und nicht mehr auf den Build-Ordner.
# ---------------------------------------------------------------------


def ignored_batch(paths: list[str]) -> set[str]:
    """Welche der uebergebenen Pfade sind ignoriert? EIN git-Aufruf.

    Verwendet `git check-ignore -z --stdin`: die Pfade kommen
    NUL-getrennt ueber stdin, die Antwort ebenfalls. Ohne -z waere
    die Zeilentrennung (und damit ein Pfad mit Zeilenumbruch) der
    stille Fehler.
    """
    if not paths:
        return set()
    r = subprocess.run(
        ['git', 'check-ignore', '-z', '--stdin'],
        cwd=ROOT,
        input='\0'.join(paths) + '\0',
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    return {p for p in r.stdout.split('\0') if p}


def check_ignore_verbose(paths: list[str]) -> dict[str, tuple[str, str, str]]:
    """Regel, Zeilennummer und Muster je Pfad. EIN git-Aufruf.

    Rueckgabe: Pfad -> (quelle, zeilennummer, muster).

    ACHTUNG - das Ausgabeformat mit -z ist VIERFELDERIG:

        <quelle>\\0<zeilennummer>\\0<muster>\\0<pfad>\\0

    Ohne -z waere es "<quelle>:<nummer>:<muster><TAB><pfad>". Wer die
    beiden Formen verwechselt, findet NICHTS - der Check meldet dann
    nie eine Inkonsistenz und ist genau damit blind. Das ist an dieser
    Stelle schon einmal passiert (der Test oben).
    """
    if not paths:
        return {}
    r = subprocess.run(
        ['git', 'check-ignore', '-v', '-z', '--no-index', '--stdin'],
        cwd=ROOT,
        input='\0'.join(paths) + '\0',
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    felder = r.stdout.split('\0')
    ergebnis: dict[str, tuple[str, str, str]] = {}
    i = 0
    while i + 3 < len(felder):
        quelle = felder[i]
        nummer = felder[i + 1]
        muster = felder[i + 2]
        pfad = felder[i + 3]
        i += 4
        if not pfad:
            continue
        ergebnis[pfad] = (quelle, nummer, muster)
    return ergebnis


# Ordner, in denen nicht gesucht wird - ZUSAETZLICH zu SKIP_DIRS.
#
# build/ und releases/ sind komplett ignoriert. Eine Datei dort kann
# also nie "NICHT IGNORIERT" sein, und der Weg in sie hinein kostet
# allein Zeit (44 000 Dateien nach einem Release-Build).
EXTRA_SKIP_DIRS = {'build', 'releases'}


def dateien_unter_root() -> list[pathlib.Path]:
    """Alle Dateien unter ROOT, ohne die uebersprungenen Ordner.

    os.walk mit dirs[:]-Beschneidung: die uebersprungenen Ordner
    werden nicht betreten. pathlib.rglob laeuft in sie hinein und
    liefert sie trotzdem - das war der Unterschied zwischen "wird
    nicht ausgewertet" und "wird ausgewertet und kostet 44 000
    git-Prozesse".
    """
    ergebnis: list[pathlib.Path] = []
    for wurzel, dirs, dateien in os.walk(ROOT):
        dirs[:] = [d for d in dirs
                   if d not in SKIP_DIRS and d not in EXTRA_SKIP_DIRS]
        for name in dateien:
            ergebnis.append(pathlib.Path(wurzel) / name)
    return ergebnis


def main() -> int:
    out: list[str] = []
    tracked = set(filter(None, git('ls-files').splitlines()))
    out.append('=' * 74)
    out.append('.GITIGNORE-PRUEFUNG')
    out.append('=' * 74)
    out.append(f'\nVersionierte Dateien: {len(tracked)}')

    # ---- A) Geheimdateien auf der Platte
    out.append('')
    out.append('--- A) Geheim-Muster auf der Platte ---')
    findings_a: list[str] = []
    ok_count = 0
    scanned = 0
    # Die Ignore-Pruefung wird GESAMMELT nachgeholt (siehe ignored_batch).
    # Deshalb sammelt dieser Durchlauf erst einmal die Kandidaten.
    # Die Reihenfolge der Befunde bleibt dabei erhalten.
    eintraege: list[tuple[str, str, str, str]] = []
    for p in sorted(dateien_unter_root()):
        rel = p.relative_to(ROOT).as_posix()
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        scanned += 1
        for pat, label, why in ALL_PATTERNS:
            if re.search(pat, rel):
                if rel in ALLOWED_TRACKED:
                    eintraege.append((rel, 'ok', label, why))
                elif rel in tracked:
                    eintraege.append((rel, 'versioniert', label, why))
                else:
                    eintraege.append((rel, 'offen', label, why))
                break

    # EIN git-Aufruf fuer alle Kandidaten statt eines je Datei.
    kandidaten = [rel for rel, art, _, _ in eintraege if art == 'offen']
    ignoriert = ignored_batch(kandidaten)

    for rel, art, label, why in eintraege:
        if art == 'ok':
            ok_count += 1
        elif art == 'versioniert':
            findings_a.append(
                f'  X  VERSIONIERT trotz Muster: {rel}  ({label})')
        elif rel in ignoriert:
            ok_count += 1
        else:
            findings_a.append(
                f'  X  NICHT IGNORIERT: {rel}  ({label}) - {why}')
    out.append(f'  {scanned} Dateien durchsucht, {ok_count} korrekt behandelt, '
               f'{len(findings_a)} Beanstandung(en)')
    out.append('  (Treffer im Detail nur bei Beanstandungen - korrekt behandelte')
    out.append('   Dateien wuerden den Bericht unbrauchbar aufblaehen.)')
    out.extend(findings_a)

    # ---- B) Versionsierte Datei, die eine Ignore-Regel trifft
    # WICHTIG --no-index: ohne diesen Schalter meldet git check-ignore
    # versionierte Dateien grundsaetzlich NICHT als ignoriert, weil sie
    # es real auch nicht sind. Genau dadurch ist beim ersten Lauf die
    # zentrale Inkonsistenz durchgerutscht: die Store-Screenshots sind
    # versioniert, gleichzeitig greift die Regel in Zeile 130. Wer die
    # Datei anfasst, scheitert mit "ignored by one of your .gitignore
    # files" - und niemand sieht warum.
    out.append('')
    out.append('--- B) Versioniert, traegt aber eine Ignore-Regel ---')
    out.append('    (Pruefung mit --no-index; ohne ihn sieht git versionierte')
    out.append('     Dateien grundsaetzlich nie als ignoriert an.)')
    findings_b: list[str] = []
    # EIN git-Aufruf fuer alle versionierten Dateien (vorher einer
    # je Datei - bei ueber 500 Dateien sind das 500 Prozesse).
    regeln = check_ignore_verbose(sorted(tracked))
    for rel in sorted(tracked):
        eintrag = regeln.get(rel)
        if eintrag is None:
            continue
        quelle, nummer, muster = eintrag
        if muster.lstrip().startswith('!'):
            continue
        findings_b.append(
            f'  !  {rel}\n            Regel: {quelle}:{nummer}  Muster: {muster}')
    out.append(f'  {len(findings_b)} Treffer')
    if findings_b:
        out.append('  (Bedeutung: die Datei ist versioniert, die Regel ist aber')
        out.append('   scharf. Aenderungen daran scheitern mit "ignored by')
        out.append('   ...", bis die Regel gestrichen oder mit -f aufgenommen')
        out.append('   wird. Beides gleichzeitig darf nicht bleiben.)')
    out.extend(findings_b)

    # ---- C) Build-Artefakte, die versehentlich im Repo liegen
    out.append('')
    out.append('--- C) Build-Artefakte (sollen nicht im Repo sein) ---')
    findings_c: list[str] = []
    for rel in sorted(tracked):
        if rel in ALLOWED_TRACKED:
            continue  # bewusste Betreiber-Entscheidung, siehe Kommentar dort
        for pat, label in BUILD_PATTERNS:
            if re.search(pat, rel):
                findings_c.append(f'  X  {rel}  ({label})')
                break
    out.append(f'  {len(findings_c)} Build-Artefakt(e) ohne dokumentierte Ausnahme')
    out.extend(findings_c)

    # ---- D) Unversioniert und NICHT ignoriert
    out.append('')
    out.append('--- D) Unversioniert und nicht ignoriert (gefaehrlichster Fall) ---')
    status = git('status', '--porcelain', '--untracked-files=all')
    untracked = [ln[3:] for ln in status.splitlines()
                 if ln.startswith('??')]
    findings_d: list[str] = []
    for rel in untracked:
        for pat, label, _why in ALL_PATTERNS:
            if re.search(pat, rel):
                findings_d.append(f'  X       {rel}  ({label})')
                break
    if not untracked:
        out.append('  OK      Arbeitsverzeichnis sauber, nichts Unversioniertes')
    else:
        out.append(f'  {len(untracked)} unversionierte Datei(en)')
        out.extend(findings_d or [f'  OK      keine davon sensibel ({len(untracked)} Stueck)'])

    # ---- E) Nur-gitignore-Pflicht
    out.append('')
    out.append('--- E) Reine Ignore-Pruefung (stille Wiki-Dateien) ---')
    findings_e: list[str] = []
    env_dateien = [p for p in dateien_unter_root()
                   if p.name.startswith('.env')]
    # EIN git-Aufruf fuer alle .env-Kandidaten.
    offen = [p.relative_to(ROOT).as_posix() for p in env_dateien]
    nicht_ignoriert = ignored_batch(offen)
    for rel in offen:
        if rel not in ALLOWED_TRACKED and rel not in nicht_ignoriert:
            findings_e.append(f'  X       {rel} waere per "git add -A" aufnehmbar')
    out.append('  OK      keine aufnehmbaren Ignore-Dateien' if not findings_e
               else '\n'.join(findings_e))

    total = len(findings_a) + len(findings_c) + len(findings_d) + len(findings_e)
    out.append('')
    out.append('=' * 74)
    out.append(f'SUMMAR: {total} Beanstandung(en), '
               f'{len(findings_b)} Inkonsistenz(en), {len(tracked)} versioniert')
    OUT.write_text('\n'.join(out) + '\n', encoding='utf-8')
    print(f'{total} Beanstandung(en), {len(findings_b)} Inkonsistenz(en)')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
