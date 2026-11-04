"""Prueft, dass die Signier-Passwoerter NICHT im Projektordner liegen.

GRUND (04.11.2026): Die Passwoerter des Release-Keystores lagen im
Klartext in `android/key.properties`. Die Datei war gitignored - aber
sie lag im Projektverzeichnis, also in Backups, in Sync-Mappen
(OneDrive, Dropbox) und in Screenshots des Ordners.

Jetzt liegen sie in einer Secret-Datei ausserhalb des Projekts bzw. in
Umgebungsvariablen fuer CI (siehe `tool/keystore_secrets.py`).

Geprueft wird:

  1. Im Projektverzeichnis steht kein Passwort mehr. Gesucht wird in
     JEDER `*.properties`-Datei unterhalb des Repositorys (nicht nur in
     key.properties) - eine Datei, die sich woanders einschleichen
     laesst, wird genauso gefunden.
  2. Die Aufloesungsreihenfolge ist in `android/app/build.gradle.kts`
     dokumentiert: Umgebungsvariablen, Secret-Datei, key.properties.
  3. Liegt eine Secret-Datei vor, liegt sie ausserhalb des Projekts
     und ist nicht fuer alle Benutzer lesbar (Windows: die ACL
     darf weder "Everyone" noch "Users"/"Authenticated Users" eine
     Leseberechtigung geben).

In der CI gibt es weder key.properties noch eine Secret-Datei - das
ist der normale Zustand und kein Fehler.

Aufruf:  python tool/check_keystore_secrets.py
"""

import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))
import keystore_secrets  # noqa: E402

GRADLE = ROOT / 'android' / 'app' / 'build.gradle.kts'

# Schluessel, die ein Passwort tragen.
PASSWORT_SCHLUESSEL = ('storePassword', 'keyPassword')

# Verzeichnisse, die nicht durchsucht werden (Bauausgaben).
UEBERSPRINGEN = {'.git', 'build', '.dart_tool', 'node_modules',
                  'releases', '.gradle'}


def alle_properties() -> list[pathlib.Path]:
    """Alle *.properties-Dateien im Repository."""
    treffer = []
    for p in ROOT.rglob('*.properties'):
        teile = set(p.relative_to(ROOT).parts)
        if teile & UEBERSPRINGEN:
            continue
        treffer.append(p)
    return sorted(treffer)


def passwoerter_in(datei: pathlib.Path) -> list[str]:
    """Die Schluessel mit Wert in dieser Datei."""
    raus = []
    try:
        inhalt = datei.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return raus
    for zeile in inhalt.splitlines():
        zeile = zeile.strip()
        if not zeile or zeile.startswith('#') or '=' not in zeile:
            continue
        k, v = zeile.split('=', 1)
        if k.strip() in PASSWORT_SCHLUESSEL and v.strip():
            raus.append(k.strip())
    return raus


def main() -> int:
    print('=' * 68)
    print('SIGNIER-SECRETS')
    print('=' * 68)

    problems = []

    # 1) Kein Passwort im Projektverzeichnis.
    print('\n1) Passwoerter im Projektverzeichnis')
    gefunden = False
    for datei in alle_properties():
        schluessel = passwoerter_in(datei)
        if schluessel:
            gefunden = True
            problems.append(
                f'{datei.relative_to(ROOT).as_posix()}: enthaelt '
                f'{", ".join(schluessel)} im Klartext - die Passwoerter '
                f'liegen in der Secret-Datei ausserhalb des Projekts')
            print('  X %s: %s' % (datei.relative_to(ROOT).as_posix(),
                                  ', '.join(schluessel)))
    if not gefunden:
        print('  OK  keine *.properties im Projekt enthaelt ein Passwort')

    # 2) Die Aufloesungsreihenfolge ist im Gradle-Skript hinterlegt.
    print('\n2) Aufloesungsreihenfolge in build.gradle.kts')
    if not GRADLE.is_file():
        problems.append('android/app/build.gradle.kts fehlt')
        print('  X Datei fehlt')
    else:
        quellytext = GRADLE.read_text(encoding='utf-8', errors='replace')
        erwartet = [
            ('THESTIA_KEYSTORE_PASSWORD', 'Umgebungsvariable'),
            ('THESTIA_KEY_PASSWORD', 'Umgebungsvariable'),
            ('THESTIA_KEYSTORE_PROPERTIES', 'Pfad der Secret-Datei'),
            ('.secrets/thestia-release.properties', 'Vorgabe-Pfad'),
        ]
        fehlend = [was for was, _ in erwartet if was not in quellytext]
        if fehlend:
            problems.append(
                'build.gradle.kts: die Aufloesung kennt nicht '
                f'{", ".join(fehlend)}')
            print('  X fehlt: %s' % ', '.join(fehlend))
        else:
            print('  OK  Umgebungsvariablen, Secret-Datei und Vorgabe-Pfad '
                  'sind hinterlegt')

    # 3) Die Secret-Datei liegt ausserhalb und ist nicht fuer alle lesbar.
    print('\n3) Secret-Datei')
    secret = keystore_secrets.secret_file_path()
    if secret is None:
        print('  -  keine Secret-Datei benannt (nur Umgebungsvariablen)')
    elif not secret.is_file():
        print('  -  %s existiert nicht (nur, wenn noch nichts gebaut wurde)'
              % secret)
    else:
        try:
            secret.relative_to(ROOT)
            problems.append(
                f'die Secret-Datei liegt IM Projektordner: {secret}')
            print('  X %s liegt im Projektordner' % secret)
        except ValueError:
            print('  OK  %s liegt ausserhalb des Projekts' % secret)

        # ACL pruefen (nur Windows, nur wenn icacls da ist).
        if sys.platform == 'win32':
            try:
                p = subprocess.run(['icacls', str(secret)],
                                   capture_output=True, text=True,
                                   encoding='utf-8', errors='replace',
                                   timeout=60)
                acl = p.stdout or ''
                offen = [m for m in ('Everyone', 'BUILTIN\\Users',
                                     'Authenticated Users', 'Jeder')
                         if m.lower() in acl.lower()]
                if offen:
                    problems.append(
                        'die Secret-Datei ist fuer weitere Benutzer lesbar '
                        f'({", ".join(offen)}) - Rechte einschraenken: '
                        f'icacls "{secret}" /inheritance:r /grant:r '
                        '"%USERNAME%:F"')
                    print('  X offen fuer: %s' % ', '.join(offen))
                else:
                    print('  OK  nur fuer den Besitzer lesbar')
            except (OSError, subprocess.SubprocessError):
                print('  -  ACL nicht pruefbar (icacls fehlt)')

    # 4) Ist ueberhaupt alles konfiguriert?
    print('\n4) Konfigurationsstand')
    p = keystore_secrets.read_props()
    vollstaendig = keystore_secrets.signing_ready(p)
    if vollstaendig:
        print('  OK  alle vier Angaben vorhanden (%s)'
              % keystore_secrets.describe())
    else:
        print('  -  nicht vollstaendig: %s' % keystore_secrets.describe())
        print('     (in der CI normal - dort wird nicht signiert)')

    print()
    if problems:
        for prob in problems:
            print(' X', prob)
        print()
        print('%d Befund(e).' % len(problems))
        return 1

    print('OK  keine Passwoerter im Projektverzeichnis.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
