#!/usr/bin/env python3
"""Richtet den Admin-Posteingang ein - interaktiv, in einem Durchgang.

WER (04.11.2026): "Den Posteingang moechte ich selbst einrichten
koennen, wenn ich es dann brauche." Genau das macht dieses Skript:
es fragt die noetigen Werte ab, legt die Secret-Datei ausserhalb des
Projekts an, schraenkt deren Rechte ein und richtet optional den
Task-Planer ein.

Was gemacht wird:

  1. Fragen: IMAP-Host, Postfach-Login, Passwort, Ordner, internes
     Secret. Vorgaaben werden angeboten, bereits Vorhandenes wird
     unveraendert uebernommen.
  2. Schreiben: %USERPROFILE%\\.secrets\\thestia-mail.properties
     (ausserhalb des Repos, Rechte nur fuer den Besitzer).
  3. Pruefen: Verbindung zum IMAP-Server (Login), danach ein Probelauf
     ohne zu senden.
  4. Aufgabenplaner (nur Windows, mit --task): alle 5 Minuten.

Aufruf:

  python tool/setup_mail_inbox.py            # fragen, schreiben, pruefen
  python tool/setup_mail_inbox.py --task     # zusaetzlich Task-Planer
  python tool/setup_mail_inbox.py --status   # nur Status zeigen
  python tool/setup_mail_inbox.py --remove   # Task-Planer wieder loeschen

FINGERABDRUCK DER WERTE (fuer die Fehlersuche):

  IMAP_HOST             z. B. imap.ionos.de  (IMAPS, Port 993)
  IMAP_USER             die Postfach-Adresse
  IMAP_PASSWORD         das Passwort bzw. ein App-Passwort
                        (bei 2FA: ein eigener App-Passwort, NICHT das
                        normale Kontopasswort - die meisten Anbieter
                        lehnen IMAP mit dem normalen Passwort ab)
  IMAP_FOLDER           INBOX
  THESTIA_FUNCTIONS_URL https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1
  THESTIA_INTERNAL_SECRET  das interne Secret der Edge Functions

Das interne Secret steht NICHT im Repository und laesst sich nicht
auslesen - `supabase secrets list` zeigt nur einen Digest. Ist es
verloren, wird ein neues gesetzt:

  supabase secrets set THESTIA_INTERNAL_SECRET=<neuer-wert>

Danach muss DERSELBE Wert hier eingetragen werden (sonst lehnt die
Edge Function die Mails mit 401 ab - die Mails gehen dann nicht
verloren, sie werden nur nicht gespeichert).
"""

import getpass
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mail_secrets  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent

TASK_NAME = 'Thestia Mail-Poll (IMAP)'

FRAGEN = [
    ('IMAP_HOST', 'IMAP-Server (Hostname)',
     'z. B. imap.ionos.de oder imap.gmail.com'),
    ('IMAP_USER', 'Postfach-Login (E-Mail-Adresse)',
     'die Adresse, unter der die Mails ankommen'),
    ('IMAP_FOLDER', 'Ordner im Postfach',
     'INBOX (Standard)'),
    ('THESTIA_INTERNAL_SECRET', 'Internes Secret der Edge Functions',
     'steht in Supabase unter Secrets; ohne dieses Secret werden '
     'die Mails abgewiesen'),
]


def frage_wert(key: str, label: str, hinweis: str, alt: str) -> str:
    while True:
        vorgegeben = alt
        if vorgegeben:
            print('\n  %s' % label)
            print('    %s' % hinweis)
            print('    aktuell: %s' % vorgegeben)
            antwort = input('    neue Eingabe (Enter = beibehalten): ').strip()
            return antwort or vorgegeben
        print('\n  %s' % label)
        print('    %s' % hinweis)
        antwort = input('    > ').strip()
        if antwort:
            return antwort
        print('    (Eingabe benoetigt)')


def frage_passwort(alt: str) -> str:
    print('\n  IMAP-Passwort (Eingabe wird nicht angezeigt)')
    print('    Bei 2FA: ein eigener App-Passwort, NICHT das Kontopasswort.')
    if alt:
        print('    aktuell: gesetzt (Enter = beibehalten)')
        antwort = getpass.getpass('    neu (Enter = beibehalten): ')
        return antwort or alt
    while True:
        antwort = getpass.getpass('    > ')
        if antwort:
            return antwort
        print('    (Eingabe benoetigt)')


def rechte_einschraenzen(datei: pathlib.Path) -> str:
    """Nur der Besitzer darf lesen (Windows)."""
    if sys.platform != 'win32':
        try:
            datei.chmod(0o600)
            return 'chmod 600 gesetzt'
        except OSError as e:
            return 'Rechte nicht setzbar: %s' % e
    cmd = ['icacls', str(datei), '/inheritance:r',
           '/grant:r', '%s:F' % os.environ.get('USERNAME', '')]
    p = subprocess.run(cmd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace', timeout=60)
    if p.returncode == 0:
        return 'nur fuer den Besitzer lesbar'
    return 'Rechte nicht eingeschraenkt: %s' % (p.stderr or p.stdout).strip()


def datei_schreiben(werte: dict) -> pathlib.Path:
    secret = mail_secrets.secret_file_path()
    if secret is None:
        raise SystemExit('FEHLER: Kein Benutzerordner gefunden.')
    secret.parent.mkdir(parents=True, exist_ok=True)
    zeilen = [
        '# Admin-Posteingang (IMAP) - Zugangsdaten.',
        '#',
        '# Angelegt von tool/setup_mail_inbox.py am %s.' % '',
        '#',
        '# Diese Datei liegt ABSICHTLICH ausserhalb des Projektordners:',
        '# die Zugangsdaten gehoeren nicht in Backups und Sync-Mappen des',
        '# Repositories. Sie wird von tool/mail_secrets.py gelesen.',
        '',
    ]
    for k in ('IMAP_HOST', 'IMAP_PORT', 'IMAP_USER', 'IMAP_PASSWORD',
              'IMAP_FOLDER', 'THESTIA_FUNCTIONS_URL',
              'THESTIA_INTERNAL_SECRET'):
        if k in werte:
            zeilen.append('%s=%s' % (k, werte[k]))
    zeilen.append('')
    secret.write_text('\n'.join(zeilen), encoding='utf-8', newline='\n')
    return secret


def verbindung_pruefen(settings: dict) -> bool:
    import imaplib
    import ssl
    host = settings.get('IMAP_HOST', '')
    user = settings.get('IMAP_USER', '')
    pw = settings.get('IMAP_PASSWORD', '')
    port = int(settings.get('IMAP_PORT', '993'))
    print('\n=== Verbindung zu %s:%d ===' % (host, port))
    try:
        box = imaplib.IMAP4_SSL(host, port,
                                ssl_context=ssl.create_default_context())
        box.login(user, pw)
        print('  OK  Anmeldung erfolgreich')
        box.logout()
        return True
    except Exception as e:  # noqa: BLE001
        print('  FEHLER  %s' % e)
        print('  Hinweise:')
        print('    * Port 993 = IMAPS. Manche Anbieter nutzen 143 (STARTTLS).')
        print('    * Bei 2FA: ein App-Passwort statt des Kontopassworts.')
        print('    * Manche Anbieter erlauben IMAP erst nach dem ersten')
        print('      Abruf im Web-Postfach.')
        return False


def task_einrichten() -> bool:
    if sys.platform != 'win32':
        print('  Der Task-Planer ist ein Windows-Feature - auf diesem')
        print('  System bitte Cron oder systemd-timer verwenden.')
        return False
    cmd = [
        'schtasks', '/Create', '/TN', TASK_NAME, '/TR',
        'python "%s"' % (ROOT / 'tool' / 'mail_imap_poll.py'),
        '/SC', 'MINUTE', '/MO', '5', '/F',
    ]
    p = subprocess.run(cmd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace', timeout=120)
    ok = p.returncode == 0
    print('  %s  Task-Planer: %s'
          % ('OK ' if ok else 'X  ', (p.stdout or p.stderr).strip()))
    if not ok:
        print('      Der Task muss mit der Python-Installation laufen, die')
        print('      auch den Aufgabenplaner startet (System-Python oder')
        print('      den vollen Pfad eintragen).')
    return ok


def task_entfernen() -> bool:
    p = subprocess.run(['schtasks', '/Delete', '/TN', TASK_NAME, '/F'],
                       capture_output=True, text=True, encoding='utf-8',
                       errors='replace', timeout=60)
    ok = p.returncode == 0
    print('  %s  Task entfernt: %s'
          % ('OK ' if ok else 'X  ', (p.stdout or p.stderr).strip()))
    return ok


def main() -> int:
    print('=' * 68)
    print('ADMIN-POSTEINGANG EINRICHTEN')
    print('=' * 68)

    if '--status' in sys.argv:
        print(mail_secrets.beschreibe())
        fehlt = mail_secrets.fehlende()
        if fehlt:
            print('\nEs fehlt: %s' % ', '.join(fehlt))
            print('Einrichten:  python tool/setup_mail_inbox.py')
            return 1
        print('\nAlles vorhanden.')
        return 0

    if '--remove' in sys.argv:
        return 0 if task_entfernen() else 1

    alt = mail_secrets.read_settings()
    werte = dict(alt)

    print('\nDie Angaben werden in einer Secret-Datei ausserhalb des')
    print('Projekts abgelegt: %s' % mail_secrets.secret_file_path())
    print('Vorhandene Werte werden uebernommen, wenn du Enter drueckst.')

    for key, label, hinweis in FRAGEN:
        werte[key] = frage_wert(key, label, hinweis, alt.get(key, ''))

    werte['IMAP_PASSWORD'] = frage_passwort(alt.get('IMAP_PASSWORD', ''))
    werte.setdefault('IMAP_PORT', '993')
    werte.setdefault('IMAP_FOLDER', 'INBOX')
    werte.setdefault('THESTIA_FUNCTIONS_URL', mail_secrets.VORGABEN[
        'THESTIA_FUNCTIONS_URL'])

    datei = datei_schreiben(werte)
    print('\n=== Secret-Datei ===')
    print('  %s (%d B)' % (datei, datei.stat().st_size))
    print('  Rechte: %s' % rechte_einschraenzen(datei))

    settings = mail_secrets.read_settings()
    ok = verbindung_pruefen(settings)

    if ok:
        print('\n=== Probelauf (nur zeigen, nicht senden) ===')
        p = subprocess.run(
            [sys.executable, str(ROOT / 'tool' / 'mail_imap_poll.py'),
             '--dry-run'],
            capture_output=True, text=True, encoding='utf-8',
            errors='replace', timeout=300, cwd=str(ROOT))
        for zeile in (p.stdout or '').splitlines()[:25]:
            print('  ' + zeile)
        if p.returncode != 0:
            print('  (Der Probelauf endete mit %d - die Meldung oben'
                  ' erklaeren das.)' % p.returncode)

    if '--task' in sys.argv:
        print('\n=== Aufgabenplaner ===')
        task_einrichten()

    print('\nFERTIG. Der Posteingang zeigt die Mails im Admin-Bereich der')
    print('App (nur lesbar, nach Adresse sortiert).')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
