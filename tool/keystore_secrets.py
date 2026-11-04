"""Woher kommen die Signier-Angaben? (Eine Quelle fuer alle Werkzeuge.)

GRUND (04.11.2026): Die Passwoerter des Release-Keystores lagen im
Klartext in `android/key.properties`. Die Datei war gitignored - aber
sie lag im Projektordner, also in Backups, in Sync-Mappen und in
Screenshots des Verzeichnisses.

Jetzt gilt eine Reihenfolge, die in drei Werkzeugen identisch ist
(Gradle, `tool/build_release.ps1`, `tool/check_passkey_assetlinks.py`):

  1. Umgebungsvariablen - der Weg fuer CI und Build-Server:
       THESTIA_KEYSTORE_PASSWORD, THESTIA_KEY_PASSWORD,
       THESTIA_KEY_ALIAS, THESTIA_KEYSTORE_FILE
  2. Eine Secret-Datei AUSSERHALB des Projekts:
       %THESTIA_KEYSTORE_PROPERTIES% oder (Vorgabe)
       %USERPROFILE%\\.secrets\\thestia-release.properties
       bzw. ~/.secrets/thestia-release.properties
  3. `android/key.properties` - enthaelt nur noch keyAlias und
     storeFile, also nichts Geheimes.

Dieses Modul ist bewusst abhaengigkeitsfrei (nur Standardbibliothek),
damit es ohne weitere Installation ueberall laeuft.
"""

import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROPS = ROOT / 'android' / 'key.properties'

ENV_ALIAS = 'THESTIA_KEY_ALIAS'
ENV_STORE_PASSWORD = 'THESTIA_KEYSTORE_PASSWORD'
ENV_KEY_PASSWORD = 'THESTIA_KEY_PASSWORD'
ENV_STORE_FILE = 'THESTIA_KEYSTORE_FILE'
ENV_SECRET_FILE = 'THESTIA_KEYSTORE_PROPERTIES'

SECRET_FILE_NAME = 'thestia-release.properties'


def secret_file_path() -> pathlib.Path | None:
    """Der Pfad der Secret-Datei (Vorgabe: im Benutzerordner)."""
    from_env = os.environ.get(ENV_SECRET_FILE, '').strip()
    if from_env:
        return pathlib.Path(from_env)
    home = (os.environ.get('USERPROFILE')
            or os.environ.get('HOME')
            or str(pathlib.Path.home()))
    if not home:
        return None
    return pathlib.Path(home) / '.secrets' / SECRET_FILE_NAME


def _read(path: pathlib.Path) -> dict:
    out: dict = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def read_props() -> dict:
    """Alle Signier-Angaben, aufgeloest nach der Reihenfolge oben."""
    props: dict = {}
    secret = secret_file_path()
    if secret is not None:
        props.update(_read(secret))
    props.update(_read(PROPS))     # Altlast: nur keyAlias/storeFile

    # Die Umgebungsvariablen haben Vorrang vor beiden Dateien.
    for name, env in (('keyAlias', ENV_ALIAS),
                      ('storePassword', ENV_STORE_PASSWORD),
                      ('keyPassword', ENV_KEY_PASSWORD),
                      ('storeFile', ENV_STORE_FILE)):
        value = os.environ.get(env, '').strip()
        if value:
            props[name] = value
    return props


def signing_ready(props: dict | None = None) -> bool:
    """Sind ALLE vier Angaben vorhanden?"""
    p = read_props() if props is None else props
    return all(p.get(k) for k in ('keyAlias', 'keyPassword',
                                  'storePassword', 'storeFile'))


def describe() -> str:
    """Ein kurzer, gefahrener Status fuer Logs und Fehlermeldungen."""
    p = read_props()
    secret = secret_file_path()
    quelle = []
    if os.environ.get(ENV_STORE_PASSWORD):
        quelle.append('Umgebungsvariablen')
    if secret is not None and secret.is_file():
        quelle.append(str(secret))
    if PROPS.is_file():
        quelle.append(str(PROPS))
    return ('Quelle: %s | vollstaendig: %s'
            % (', '.join(quelle) or 'keine',
               'ja' if signing_ready(p) else 'NEIN'))


if __name__ == '__main__':
    if '--status' in sys.argv:
        print(describe())
        sys.exit(0 if signing_ready() else 1)
    print(describe())
    p = read_props()
    for k in ('keyAlias', 'storeFile'):
        print('  %-14s %s' % (k, p.get(k, '(fehlt)')))
    for k in ('storePassword', 'keyPassword'):
        v = p.get(k, '')
        print('  %-14s %s' % (k, ('<VERBORGEN, %d Zeichen>' % len(v))
                              if v else '(fehlt)'))
    sys.exit(0 if signing_ready(p) else 1)
