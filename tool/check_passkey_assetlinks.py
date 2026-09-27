#!/usr/bin/env python3
"""Prueft die Passkey-Asset-Dateien gegen die Realitaet.

Fehler, die dieser Pruefer fangen soll - alle drei sind in diesem Repo
tatsaechlich aufgetreten:

1) assetlinks.json enthielt dasselbe Zertifikat zweimal (zweimal
   colon-getrennt, zweimal als kompakter Hex). Funktioniert, ist aber
   Ballast und macht Diff-Vergleiche unlesbar.
2) apple-app-site-association enthielt die unausgefuellte Vorlage
   "REPLACE_WITH_APPLE_TEAM_ID" - dadurch sind iOS-Passkeys tot,
   ohne dass irgendwo ein Fehler sichtbar wird.
3) Der Fingerprint des Play-App-Signing-Keys fehlt. Der ist erst nach
   dem ERSTEN Upload vorhanden; bis dahin ist er nicht erzeugbar und
   darf nicht geraten werden. Der Pruefer sagt das explizit, statt es
   stillschweigend durchzuwinken.

Aufruf:
    python tool/check_passkey_assetlinks.py            # lokal
    python tool/check_passkey_assetlinks.py --live     # + gegen thestia.de
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETLINKS = ROOT / 'passkey-assets' / 'assetlinks.json'
AASA = ROOT / 'passkey-assets' / 'apple-app-site-association'
PROPS = ROOT / 'android' / 'key.properties'
PUBLIC_URLS = [
    'https://auth.thestia.de/.well-known/assetlinks.json',
    'https://thestia.de/.well-known/assetlinks.json',
]
AASA_URL = 'https://auth.thestia.de/.well-known/apple-app-site-association'
PLACEHOLDER = re.compile(r'REPLACE_|_HERE|XXX|TODO_|<[a-z_]+>', re.I)
HEX64 = re.compile(r'^[0-9A-Fa-f]{64}$')

fail: list[str] = []
warn: list[str] = []


def norm(fp: str) -> str:
    """Fingerabdruck auf kanonischen Hex normalisieren."""
    return fp.replace(':', '').replace(' ', '').lower()


def keytool_sha256(alias: str, keystore: str, password: str) -> str | None:
    try:
        p = subprocess.run(
            ['keytool', '-list', '-v', '-alias', alias, '-keystore', keystore,
             '-storepass', password],
            capture_output=True, text=True, encoding='utf-8', errors='replace',
        )
    except FileNotFoundError:
        return None
    m = re.search(r'SHA256:\s*([0-9A-Fa-f:]{60,})', p.stdout + p.stderr)
    return norm(m.group(1)) if m else None


def read_props() -> dict[str, str]:
    out: dict[str, str] = {}
    if not PROPS.exists():
        return out
    for line in PROPS.read_text(encoding='utf-8', errors='replace').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def check_assetlinks(expected: dict[str, str | None]) -> set[str]:
    print('--- assetlinks.json ---')
    if not ASSETLINKS.exists():
        fail.append('assetlinks.json fehlt')
        return set()
    raw = ASSETLINKS.read_text(encoding='utf-8')
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        fail.append(f'assetlinks.json ist kein gueltiges JSON: {e}')
        return set()

    if not isinstance(data, list):
        fail.append('assetlinks.json muss eine Liste von Target-Objekten sein')
        return set()
    print(f'  Top-Level-Eintraege: {len(data)}')

    android = [e for e in data
               if e.get('target', {}).get('namespace') == 'android_app']
    web = [e for e in data if e.get('target', {}).get('namespace') == 'web']

    if len(android) != 1:
        fail.append(f'es muss genau 1 android_app-Eintrag geben, gefunden {len(android)}')
        return set()
    a = android[0]['target']
    if a.get('package_name') != 'com.thestia.app':
        fail.append(f'package_name ist {a.get("package_name")!r}, erwartet com.thestia.app')
    rel = ('delegate_permission/common.handle_all_urls',
           'delegate_permission/common.get_login_creds')
    missing = [r for r in rel if r not in a.get('relation', android[0].get('relation', []))]
    if missing:
        fail.append('android_app-Eintrag verliert relation(s): ' + ', '.join(missing))

    fps = a.get('sha256_cert_fingerprints', [])
    print(f'  android_app fingerprints: {len(fps)}')
    seen: dict[str, int] = {}
    for i, fp in enumerate(fps):
        if not isinstance(fp, str) or not fp.strip():
            fail.append(f'Fingerprint #{i} ist leer - ungueltiger Eintrag')
            continue
        if PLACEHOLDER.search(fp):
            fail.append(f'Fingerprint #{i} enthaelt eine Vorlage: {fp!r}')
            continue
        n = norm(fp)
        if not HEX64.match(n):
            fail.append(f'Fingerprint #{i} ist kein SHA-256-Hex: {fp!r}')
            continue
        if n in seen:
            fail.append(f'Fingerprint #{i} ist ein Duplikat von #{seen[n]}: {fp!r}')
        else:
            seen[n] = i

    # Beide echten Keystores muessen vertreten sein
    for label, fp in expected.items():
        if fp is None:
            warn.append(f'{label}-Keystore nicht lesbar, nicht verglichen')
        elif norm(fp) not in seen:
            fail.append(f'Fingerprint des {label}-Keystores fehlt in assetlinks.json')

    for e in web:
        site = e.get('target', {}).get('site', '')
        print(f'  web target: {site}')
    if not web:
        warn.append('kein web-Target - iOS/web Passkeys nicht verknuepft')

    return set(seen)


def check_aasa() -> None:
    print('--- apple-app-site-association ---')
    if not AASA.exists():
        fail.append('apple-app-site-association fehlt')
        return
    raw = AASA.read_text(encoding='utf-8')
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        fail.append(f'AASA ist kein gueltiges JSON: {e}')
        return
    m = PLACEHOLDER.search(raw)
    if m:
        fail.append(
            'AASA enthaelt eine unausgefuellte Vorlage '
            f'({m.group(0)!r}) - iOS-Passkeys sind damit NICHT nutzbar. '
            'Apple Team-ID aus Apple Developer -> Membership einsetzen.')
    apps = data.get('webcredentials', {}).get('apps', [])
    if not apps:
        fail.append('AASA: webcredentials.apps ist leer')
    for app in apps:
        if not PLACEHOLDER.search(app):
            print(f'  app: {app}')


def check_live(local_android: set[str]) -> None:
    import ssl
    import urllib.request
    print('--- Live-Abgleich ---')
    ctx = ssl.create_default_context()
    for url in PUBLIC_URLS:
        host = url.split('/')[2]
        try:
            with urllib.request.urlopen(url, timeout=30, context=ctx) as r:
                ctype = r.headers.get('Content-Type', '')
                data = json.loads(r.read().decode('utf-8'))
        except Exception as e:  # noqa: BLE001
            fail.append(f'{url} nicht abrufbar/parsebar: {e}')
            continue
        got: set[str] = set()
        for e in data:
            t = e.get('target', {})
            if t.get('namespace') == 'android_app':
                got = {norm(f) for f in t.get('sha256_cert_fingerprints', [])}
        ok = got == local_android
        print(f'  {host:22s} {len(got)} Zertifikate  '
              f'{"identisch" if ok else "ABWEICHEND"}')
        if 'json' not in ctype.lower():
            fail.append(f'{url}: Content-Type ist {ctype!r}, muss application/json sein')
        if not ok:
            only_live = got - local_android
            only_local = local_android - got
            if only_live:
                warn.append(f'{host} hat mehr als lokal: {len(only_live)}')
            if only_local:
                fail.append(f'{host} fehlen lokal vorhandene Zertifikate: '
                            f'{len(only_local)} - Live-Datei ist veraltet')
    try:
        with urllib.request.urlopen(AASA_URL, timeout=30, context=ctx) as r:
            live_aasa = r.read().decode('utf-8')
        m = PLACEHOLDER.search(live_aasa)
        if m:
            fail.append(f'LIVE {AASA_URL} liefert die Vorlage {m.group(0)!r} aus')
    except Exception as e:  # noqa: BLE001
        warn.append(f'AASA live nicht pruefbar: {e}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--live', action='store_true',
                    help='zusaetzlich gegen die oeffentlichen URLs pruefen')
    args = ap.parse_args()

    p = read_props()
    expected = {
        'Release/Upload': keytool_sha256(p.get('keyAlias', 'upload'),
                                        p.get('storeFile', ''),
                                        p.get('storePassword', ''))
        if p else None,
    }
    dbg = pathlib.Path.home() / '.android' / 'debug.keystore'
    expected['Debug'] = keytool_sha256('androiddebugkey', str(dbg), 'android') \
        if dbg.exists() else None

    local_set = check_assetlinks(expected)
    check_aasa()
    if args.live:
        check_live(local_set)

    print('--- Bewusst offen ---')
    print('  Play-App-Signing-Fingerprint: 0/1 - noch nicht erzeugbar.')
    print('  Play erstellt den App-Signing-Key erst beim ERSTEN Upload.')
    print('  Danach: Play Console -> Setup -> App Signing ->')
    print('  App-signing key certificate -> SHA-256 in assetlinks.json')
    print('  UND als android:apk-key-hash-Origin in Supabase ergaenzen.')

    print()
    for w in warn:
        print('WARNUNG :', w)
    for f in fail:
        print('FEHLER  :', f)
    if fail:
        print(f'\n{fail and len(fail)} Problem(e) gefunden.')
        return 1
    print('OK: Passkey-Assets sind konsistent.')
    if warn:
        print(f'({len(warn)} Warnung(en), kein Fehler.)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
