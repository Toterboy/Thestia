"""Zugangsdaten fuer den Admin-Posteingang (IMAP) - aufgeloest an einer Stelle.

GRUND (04.11.2026): Der Betreiber will den Posteingang SELBST
einrichten koennen, wenn er ihn braucht - nicht vorher. Deshalb ist
alles hier vorbereitet: eine Secret-Datei ausserhalb des Projekts, ein
Einrichtungs-Skript und ein Status-Check.

DIE REIHENFOLGE (dieselbe Logik wie bei den Keystore-Secrets):

  1. Umgebungsvariablen - der Weg fuer CI und Cron/Task-Planer:
       IMAP_HOST, IMAP_PORT, IMAP_USER, IMAP_PASSWORD, IMAP_FOLDER,
       THESTIA_FUNCTIONS_URL, THESTIA_INTERNAL_SECRET
  2. Secret-Datei AUSSERHALB des Projekts:
       %THESTIA_MAIL_PROPERTIES% oder (Vorgabe)
       %USERPROFILE%\\.secrets\\thestia-mail.properties
       bzw. ~/.secrets/thestia-mail.properties

VORGABEN (muessen nicht eingegeben werden):
  * IMAP_PORT            993 (IMAPS)
  * IMAP_FOLDER          INBOX
  * THESTIA_FUNCTIONS_URL https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1

Das Passwort wird weder geloggt noch gespeichert - ausser in dieser
Secret-Datei, und die liegt ausserhalb des Repos. Uebertragen wird es
nur an den IMAP-Server.
"""

import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRET_FILE_NAME = 'thestia-mail.properties'
ENV_SECRET_FILE = 'THESTIA_MAIL_PROPERTIES'

# Schluessel, die eingegeben werden muessen.
PFLICHT = ('IMAP_HOST', 'IMAP_USER', 'IMAP_PASSWORD')

# Schluessel mit Vorgabe.
VORGABEN = {
    'IMAP_PORT': '993',
    'IMAP_FOLDER': 'INBOX',
    'THESTIA_FUNCTIONS_URL':
        'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1',
}

SCHLUESSEL = tuple(VORGABEN) + PFLICHT + ('THESTIA_INTERNAL_SECRET',)


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


def read_settings() -> dict:
    """Alle Einstellungen, aufgeloest nach der Reihenfolge oben."""
    settings: dict = {}
    secret = secret_file_path()
    if secret is not None:
        settings.update(_read(secret))
    for k, v in VORGABEN.items():
        settings.setdefault(k, v)
    # Die Umgebungsvariablen haben Vorrang vor der Datei.
    for k in SCHLUESSEL:
        wert = os.environ.get(k, '').strip()
        if wert:
            settings[k] = wert
    return settings


def fehlende(settings: dict | None = None) -> list:
    """Welche Pflichtangaben fehlen?"""
    s = read_settings() if settings is None else settings
    return [k for k in PFLICHT if not s.get(k)]


def vollstaendig(settings: dict | None = None) -> bool:
    return not fehlende(settings)


def beschreibe(settings: dict | None = None) -> str:
    """Kurzstatus ohne Geheimnisse - fuer Logs und Bildschirme."""
    s = read_settings() if settings is None else settings
    secret = secret_file_path()
    quelle = 'Umgebungsvariablen' if os.environ.get('IMAP_HOST') else (
        str(secret) if secret is not None and secret.is_file() else 'keine')
    teile = []
    for k in ('IMAP_HOST', 'IMAP_PORT', 'IMAP_USER', 'IMAP_FOLDER'):
        teile.append('%s=%s' % (k, s.get(k) or '(fehlt)'))
    pw = s.get('IMAP_PASSWORD')
    teile.append('IMAP_PASSWORD=%s' % ('gesetzt' if pw else '(FEHLT)'))
    intern = s.get('THESTIA_INTERNAL_SECRET')
    teile.append('INTERNAL_SECRET=%s' % ('gesetzt' if intern else '(FEHLT)'))
    return '%s | Quelle: %s' % (' | '.join(teile), quelle)


if __name__ == '__main__':
    if '--status' in sys.argv:
        print(beschreibe())
        sys.exit(0 if vollstaendig() else 1)
    print(beschreibe())
    fehlt = fehlende()
    if fehlt:
        print('\nEs fehlt: %s' % ', '.join(fehlt))
        print('Einrichten:  python tool/setup_mail_inbox.py')
        sys.exit(1)
    print('\nAlles vorhanden. Test:  python tool/mail_imap_poll.py --dry-run')
    sys.exit(0)
