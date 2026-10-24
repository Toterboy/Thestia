"""Prueft live, ob der Meldeweg alle Meldetypen annimmt (v0.10.0).

Hintergrund (Security-Audit 22.10.2026): der Client sendet
`ReportType.name` (camelCase), die Server-Whitelist in `submit_report`
kannte nur snake_case. Vier von sieben Meldetypen wurden serverseitig
abgewiesen - darunter `childSafety` (Hinweis auf Kindesmissbrauch) und
`inappropriateContent` (NSFW-Bilder). Die App zeigte dem Nutzer trotzdem
die gruene Bestaetigung, weil der Fehler nur geloggt wurde.

Ein reiner Blick auf die SQL-Zeile reicht nicht: der Fehler ist zur
Laufzeit entstanden und nur mit einem echten JWT sichtbar. Dieses
Skript legt deshalb einen Wegwerf-Nutzer an, meldet sich mit ihm an und
ruft `submit_report` mit jedem Typ auf.

Zwei Wege, wie der Test endet - und beide sind ein Befund:

  * Der Aufruf wird mit "Invalid report type" abgewiesen: die Whitelist
    kennt den Typ nicht. Genau der alte Zustand.
  * Der Aufruf scheitert an "invalid_reported_user": die Whitelist hat
    den Typ ANGENOMMEN, erst die Zielpruefung hat danach gestoppt. Das
    ist der gewuenschte Zustand. (Es wird dabei nichts geschrieben -
    die Pruefung laeuft bewusst VOR dem INSERT.)

Das Skript prueft beide Wege fuer jeden Typ: "wird angenommen" und
"wird abgelehnt". Ein unbekannter Typ muss abgelehnt werden - sonst
wuerde die Whitelist nichts taugen.

AUFRUF
------
    python tool/check_report_whitelist.py

Der service_role-Key wird NICHT gespeichert. Er kommt aus der
Umgebungsvariable SUPABASE_SERVICE_ROLE_KEY oder - falls die
Supabase-CLI angemeldet ist - aus deren Projekt-API. Der Wegwerf-Nutzer
wird am Ende wieder geloescht.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

PROJECT_REF = 'jftuigjbmmuvrckbchqo'
SUPABASE_URL = f'https://{PROJECT_REF}.supabase.co'

# Alle Typen, die der Client senden kann (lib/models/report_models.dart).
ERLAUBT = [
    'harassment',
    'inappropriateContent',
    'spam',
    'fakeProfile',
    'other',
    'wrongAge',
    'childSafety',
]

# Diese Ziel-UUID existiert nicht. Damit stoppt die Pruefung an der
# Zielpruefung - NACH der Whitelist, aber VOR dem INSERT. Es wird also
# nichts in die Datenbank geschrieben.
UNGUELTIGES_ZIEL = '00000000-0000-0000-0000-0000000000ff'


def service_role_key() -> str:
    """Service-Key aus der Umgebung oder aus der angemeldeten CLI."""
    aus_umgebung = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '').strip()
    if aus_umgebung:
        return aus_umgebung
    for befehl in (['supabase'], ['supabase.cmd'], ['npx', 'supabase']):
        try:
            proc = subprocess.run(
                [*befehl, 'projects', 'api-keys', '--project-ref', PROJECT_REF,
                 '--reveal'],
                capture_output=True, text=True, encoding='utf-8',
                errors='replace', timeout=120,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        neuer_key = ''
        alter_key = ''
        for zeile in proc.stdout.splitlines():
            zeile = zeile.strip()
            if not zeile.startswith('{'):
                continue
            try:
                daten = json.loads(zeile)
            except json.JSONDecodeError:
                continue
            for key in daten.get('keys', []):
                # Der neue Secret-Key (sb_secret_...) ist der aktuelle
                # Ersatz fuer die abgeschalteten Legacy-Keys. Er wird
                # nur zum Lesen benutzt und nirgends gespeichert.
                if key.get('type') == 'secret' and key.get('api_key'):
                    neuer_key = key['api_key']
                elif key.get('id') == 'service_role':
                    alter_key = key.get('api_key', '')
        if neuer_key:
            return neuer_key
        if alter_key:
            return alter_key
    return ''


def http(method: str, url: str, *, key: str, body=None, token: str = ''):
    """Ein HTTP-Aufruf mit JSON-Antwort; gibt (status, text) zurueck."""
    headers = {'apikey': key, 'Authorization': f'Bearer {token or key}'}
    daten = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        daten = json.dumps(body).encode('utf-8')
    req = urllib.request.Request(url, data=daten, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode('utf-8', errors='replace')
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode('utf-8', errors='replace')
    except urllib.error.URLError as err:
        return 0, str(err)


def main() -> int:
    key = service_role_key()
    if not key:
        print('FEHLER: kein service_role-Key. Entweder SUPABASE_SERVICE_ROLE_KEY '
              'setzen oder die Supabase-CLI anmelden.')
        return 2

    email = f'selftest-{uuid.uuid4().hex[:12]}@example.invalid'
    # Supabase verlangt Grossbuchstaben, Kleinbuchstaben, Ziffern und ein
    # Sonderzeichen - ein reiner Hex-String reicht nicht.
    passwort = ('Aa1!' + uuid.uuid4().hex + uuid.uuid4().hex)[:40]
    user_id = ''

    try:
        # 1) Wegwerf-Nutzer anlegen (bestaetigt, damit der Login klappt).
        status, text = http(
            'POST', f'{SUPABASE_URL}/auth/v1/admin/users', key=key,
            body={
                'email': email,
                'password': passwort,
                'email_confirm': True,
                # Der handle_new_user-Trigger legt das Profil an und
                # braucht diese Felder - ohne sie schlaegt die Anlage
                # mit einem Datenbankfehler fehl.
                'user_metadata': {
                    'name': 'Selbsttest',
                    'gender': 'unknown',
                    'birth_date': '1990-01-01',
                },
            },
        )
        if status not in (200, 201):
            print(f'FEHLER: Wegwerf-Nutzer konnte nicht angelegt werden '
                  f'(HTTP {status}): {text[:200]}')
            return 2
        user_id = (json.loads(text) or {}).get('id', '')

        # 2) Anmelden, um einen echten JWT zu bekommen.
        status, text = http(
            'POST',
            f'{SUPABASE_URL}/auth/v1/token?grant_type=password', key=key,
            body={'email': email, 'password': passwort},
        )
        if status != 200:
            print(f'FEHLER: Anmeldung des Wegwerf-Nutzers fehlgeschlagen '
                  f'(HTTP {status}): {text[:200]}')
            return 2
        token = (json.loads(text) or {}).get('access_token', '')
        if not token:
            print('FEHLER: kein access_token in der Antwort.')
            return 2

        # 3) Jeden Typ durch die Whitelist schicken.
        befunde = []
        for typ in ERLAUBT:
            status, text = http(
                'POST', f'{SUPABASE_URL}/rest/v1/rpc/submit_report', key=key,
                token=token,
                body={
                    'p_reported_user_id': UNGUELTIGES_ZIEL,
                    'p_report_type': typ,
                    'p_description': 'Selbsttest',
                    'p_messages': [],
                },
            )
            # Erwartet: der Typ wird von der Whitelist angenommen, und die
            # Zielpruefung stoppt danach mit "invalid_reported_user".
            angenommen = 'invalid_reported_user' in text
            abgelehnt = 'Invalid report type' in text
            if angenommen:
                print(f'  OK    {typ:22s} von der Whitelist angenommen')
            elif abgelehnt:
                print(f'  FEHLT {typ:22s} von der Whitelist ABGEWIESEN')
                befunde.append(f'{typ} wird abgewiesen')
            else:
                print(f'  ?     {typ:22s} HTTP {status}: {text[:110]}')
                befunde.append(f'{typ} unerwartetes Ergebnis (HTTP {status})')

        # 4) Gegenprobe: ein erfundener Typ muss abgelehnt werden.
        status, text = http(
            'POST', f'{SUPABASE_URL}/rest/v1/rpc/submit_report', key=key,
            token=token,
            body={
                'p_reported_user_id': UNGUELTIGES_ZIEL,
                'p_report_type': 'erfundenerTyp',
                'p_description': 'Selbsttest',
                'p_messages': [],
            },
        )
        if 'Invalid report type' in text:
            print('  OK    erfundener Typ wird abgewiesen')
        else:
            print(f'  FEHLT erfundener Typ wird NICHT abgewiesen: {text[:140]}')
            befunde.append('die Whitelist laesst unbekannte Typen durch')

        print()
        if befunde:
            for b in befunde:
                print('BEFUND:', b)
            return 1
        print(f'OK: alle {len(ERLAUBT)} Meldetypen werden angenommen, '
              'unbekannte werden abgewiesen.')
        return 0
    finally:
        if user_id:
            status, _ = http(
                'DELETE', f'{SUPABASE_URL}/auth/v1/admin/users/{user_id}',
                key=key,
            )
            print(f'Wegwerf-Nutzer {user_id} geloescht (HTTP {status}).')


if __name__ == '__main__':
    sys.exit(main())
