"""Prueft die Release-Artefakte der AKTUELLEN Version.

Geprueft wird:
  * Signatur: CN muss Thestia sein. Aeltere Versionen im releases/-Ordner
    tragen absichtlich noch CN=WispDating (bis v0.9.1) - die werden hier
    NICHT geprueft, denn deren Signatur ist historisch und korrekt.
  * Admin-UUID: muss in den ADMIN-Builds stehen und in KEINEM
    oeffentlichen Build. Wird nur geprueft, wenn ADMIN_UUID gesetzt ist -
    die UUID ist ein Geheimnis und steht deshalb in KEINER Datei.

Zusaetzlich gemeldet (Warnung, kein Fehler): byte-identische Dateien
zwischen einem oeffentlichen und einem Admin-Build. Das ist der Fall,
wenn ein Admin-Build den oeffentlichen Pfad ueberschrieben hat.

Aufruf:
    $env:ADMIN_UUID="..."; python tool/check_release_artifacts.py
"""

import hashlib
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASES = ROOT / 'releases'

EXPECTED_CN = 'CN=Thestia'
FORBIDDEN_CN = 'WispDating'

# Die UUID kommt aus der Umgebung, damit sie nicht im Repo landet.
ADMIN_UUID = os.environ.get('ADMIN_UUID', '').strip()

problems = []
warnings = []
rows = []


def find_apksigner():
    candidates = [
        pathlib.Path(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk',
                     'build-tools'),
        pathlib.Path(r'C:\Program Files\Android\Android Studio\jbr\bin'),
        pathlib.Path(r'C:\Program Files\Android\Android Studio\jbr'),
    ]
    for base in candidates:
        if not base.is_dir():
            continue
        for exe in sorted(base.glob('**/apksigner*'), reverse=True):
            if exe.suffix == '.bat' or exe.name == 'apksigner':
                return exe
    return None


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def current_version():
    pub = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)',
                  pub, re.M)
    if not m:
        sys.exit('version in pubspec.yaml nicht lesbar')
    return m.group(1), m.group(2)


def main():
    version, code = current_version()
    vdir = RELEASES / f'v{version}'
    if not vdir.is_dir():
        sys.exit(f'{vdir} fehlt - erst bauen:\n'
                 f'  powershell -NoProfile -ExecutionPolicy Bypass '
                 f'-File tool\\build_release.ps1 -Flavor both -UniversalApk')

    public = sorted(p for p in vdir.glob('*')
                    if p.suffix in ('.apk', '.aab'))
    admin_dir = vdir / 'admin'
    admin = sorted(admin_dir.glob('*.apk')) if admin_dir.is_dir() else []

    print('=' * 78)
    print(f'RELEASE-ARTEFAKTE v{version} (build {code})')
    print('=' * 78)
    print(f'öffentlich: {len(public)} Dateien   Admin: {len(admin)} Dateien')
    print(f'ADMIN_UUID: {"gesetzt (wird geprüft)" if ADMIN_UUID else "NICHT gesetzt - UUID-Prüfung übersprungen"}')
    print()

    digests = {}
    for path in public + admin:
        is_admin = path in admin
        rel = path.relative_to(ROOT).as_posix()
        size_mb = path.stat().st_size / 1024 / 1024
        digest = sha256(path)
        digests.setdefault(digest, []).append(rel)

        note = ''
        if ADMIN_UUID:
            has = ADMIN_UUID.encode() in path.read_bytes()
            note = 'UUID ' + ('JA' if has else 'nein')
            if is_admin and not has:
                problems.append(f'{rel}: ADMIN_UUID fehlt - der Admin-Build '
                                f'kann keine Admins freischalten.')
            if not is_admin and has:
                problems.append(f'{rel}: ADMIN_UUID im öffentlichen Build. '
                                f'Das ist ein vollständiger Admin-Zugang '
                                f'für jeden, der die APK hat.')
        rows.append(f'  {rel:<52} {size_mb:7.1f} MB  {digest[:12]}  {note}')

    print('\n'.join(rows))

    # Admin-Build darf niemals als oeffentliche Datei identisch sein.
    print()
    admin_digests = {sha256(p): p.name for p in admin}
    for path in public:
        d = sha256(path)
        if d in admin_digests:
            problems.append(
                f'{path.name} ist byte-identisch mit dem Admin-Build '
                f'{admin_digests[d]} - der Admin-Build hat den '
                f'öffentlichen Pfad überschrieben.')

    # Signatur
    apksigner = find_apksigner()
    print()
    if apksigner:
        print(f'Signatur ({apksigner.name}):')
        for path in public + admin:
            if path.suffix != '.apk':
                continue
            try:
                out = subprocess.run(
                    ['cmd', '/c', str(apksigner), 'verify', '--print-certs',
                     str(path)],
                    capture_output=True, text=True, timeout=300).stdout
            except Exception as e:                       # noqa: BLE001
                problems.append(f'{path.name}: apksigner {e}')
                continue
            m = re.search(r'(CN=[^,\s]+)', out)
            cn = m.group(1) if m else '(kein CN)'
            if FORBIDDEN_CN in out:
                problems.append(
                    f'{path.name}: CN={cn} - das ist die alte Signatur aus '
                    f'v0.9.1. Ein Update vom Play Store scheitert mit '
                    f'INSTALL_FAILED_UPDATE_INCOMPATIBLE.')
            elif EXPECTED_CN not in out:
                problems.append(f'{path.name}: CN ist {cn}, erwartet '
                                f'{EXPECTED_CN}')
            print(f'  {path.name:<48} {cn}')
    else:
        warnings.append('apksigner nicht gefunden - Signatur ungeprüft')

    if warnings:
        print()
        for w in warnings:
            print('  !', w)

    # Alle Versionen: byte-identische Datei zwischen einem oeffentlichen
    # und einem Admin-Build. Genau das ist bei v0.9.1 passiert - der
    # Admin-Build hat beide universellen APKs ueberschrieben, sodass
    # unter "oeffentlichem" Namen ein Build mit vollstaendigem
    # Admin-Zugang lag. Ohne diesen Scan faellt es nicht auf, weil beide
    # Dateien gueltig signiert sind und die Publish-Pruefung nur die
    # aktuelle Version ansieht.
    print()
    collisions = []
    for vdir in sorted(p for p in RELEASES.iterdir()
                       if p.is_dir() and p.name.startswith('v')):
        adir = vdir / 'admin'
        if not adir.is_dir():
            continue
        adm = {sha256(p): p.name for p in sorted(adir.glob('*.apk'))}
        for p in sorted(vdir.glob('*.apk')):
            d = sha256(p)
            if d in adm:
                collisions.append(
                    f'{vdir.name}/{p.name} == {vdir.name}/admin/{adm[d]}')
    if collisions:
        print('ACHTUNG - Admin-Build im öffentlichen Ablageort:')
        for c in collisions:
            print('  X', c)
        problems.append(
            f'{len(collisions)} Datei(en) sind byte-identisch mit einem '
            f'Admin-Build. Die betroffenen öffentlichen APKs enthalten den '
            f'Admin-Zugang und müssen neu gebaut werden.')
    else:
        print('Kein Admin-Build im öffentlichen Ablageort.')

    print()
    if problems:
        print('FEHLER:')
        for p in problems:
            print('  X', p)
        sys.exit(1)
    print(f'OK  {len(public) + len(admin)} Artefakte: Signatur und '
          f'Admin-Trennung stimmen.')


if __name__ == '__main__':
    main()
