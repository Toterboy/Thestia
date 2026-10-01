"""
tool/check_release_artifacts_selftest.py
=========================================
Prueft, dass `check_release_artifacts.py` FEHLER meldet, wenn er
fehlschlagen muss.

Hintergrund: der Checker ist entstanden, nachdem ein Admin-Build unter
oeffentlichem Namen gelandet war. Ein Checker, der nur "gruene Null"
oder "irgendetwas gefunden" sagt, ist schlimmer als keiner - er
verspricht eine Sicherheit, die er nicht hat. Deshalb hier die
Negativfaelle, jeweils gegen eine kuenstliche Release-Struktur.

Aufruf:
    python tool/check_release_artifacts_selftest.py

Exit 0 = alle Negativfaelle wurden erkannt.
"""

import importlib.util
import io
import pathlib
import shutil
import sys
import tempfile
import uuid
import zipfile
from contextlib import redirect_stderr, redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = ROOT / 'tool' / 'check_release_artifacts.py'

spec = importlib.util.spec_from_file_location('cra', TARGET)
cra = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cra)


def make_zip(path, entries, compress=True):
    """Baut eine APK/AAB-artige Datei mit den angegebenen Eintraegen."""
    mode = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
    with zipfile.ZipFile(path, 'w', mode) as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return path


def uuid_str():
    return str(uuid.uuid4())


def make_world(tmp, public_names, admin_uuid, secret_in=(), with_admin=True):
    """Legt eine Release-Welt an.

    public_names: Dateinamen der oeffentlichen Artefakte
    admin_uuid:   die UUID, die nur im Admin-Build steckt
    secret_in:    Namen oeffentlicher Dateien, die die UUID enthalten
    with_admin:   ohne Admin-Build laeuft der UUID-Diff nicht - fuer
                  den Test "leerer Versionsordner" gebraucht
    """
    releases = tmp / 'releases'
    vdir = releases / 'v9.9.9'
    (vdir / 'admin').mkdir(parents=True, exist_ok=True)

    common = (b'x' * 4096) + uuid_str().encode()   # oeffentliche UUID
    for n in public_names:
        payload = common
        if n in secret_in:
            payload = common + admin_uuid.encode()
        # Der Dateiname wandert als eigener Eintrag mit in das Archiv.
        # Sonst waere ein kontaminierter .aab byte-identisch zum
        # Admin-APK, und der Kollisionscheck wuerde feuern, bevor der
        # eigentliche AAB-Test etwas zu sehen bekommt.
        make_zip(vdir / n, {
            'lib/arm64-v8a/libapp.so': payload,
            'AndroidManifest.xml': b'manifest',
            f'public-marker-{n}': n.encode(),
        }, compress=(n.endswith('.aab')))

    if with_admin:
        # Der Admin-Build heisst <oeffentlicher Name>-ADMIN.apk. Der
        # Name ist nicht kosmetisch: der Checker paart Admin- und
        # oeffentlichen Build ueber genau diesen Namensrest. Ohne die
        # Paarung muesste er raten und koennte nicht melden.
        mate = public_names[0] if public_names else 'play.apk'
        make_zip(vdir / 'admin' / f'{mate[:-4]}-ADMIN.apk', {
            'lib/arm64-v8a/libapp.so': common + admin_uuid.encode(),
            'AndroidManifest.xml': b'manifest',
            'public-marker-admin': b'admin',
        }, compress=False)
    return releases


def run_checker():
    """Fuehrt main() aus und liefert (exit_code, ausgabe).

    apksigner wird auf None gesetzt: die Testartefakte sind keine
    echten APKs, apksigner scheitert daran mit einer
    MinSdkVersionException - und das wuerde jeden Negativfall mit
    einem Grundfehler drownen, den man nicht pruefen wollte. Der
    Signaturpfad wird dadurch nicht getestet; der Inhalts- und der
    Kollisionspfad schon.
    """
    buf = io.StringIO()
    err = io.StringIO()
    old_argv = sys.argv[:]
    old_root = cra.ROOT
    old_current = cra.current_version
    old_signer = cra.find_apksigner
    try:
        sys.argv = ['check_release_artifacts.py']
        cra.find_apksigner = lambda: None
        # Beide Kanaele: sys.exit("text") schreibt nach stderr, und genau
        # diese Faelle (fehlender Versionsordner) sind die, die man
        # pruefen will.
        with redirect_stdout(buf), redirect_stderr(err):
            try:
                cra.main()
                code = 0
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                # sys.exit("Text") gibt eine Zeichenkette als Code. Die
                # schreibt Python erst dann auf stderr, wenn die
                # Exception UNBEHANDELT bleibt - wir fangen sie aber ab.
                # Also selbst uebernehmen, sonst fehlt genau die
                # Meldung, die man pruefen will.
                if isinstance(e.code, str):
                    err.write(e.code)
    finally:
        sys.argv = old_argv
        cra.ROOT = old_root
        cra.current_version = old_current
        cra.find_apksigner = old_signer
    return code, buf.getvalue() + err.getvalue()


CASES = []

# Zwei moegliche-detektionswege. Der Unterschied ist Absicht: das
# Artefakt kann ueber die UUID-Differenz auffallen (es enthaelt die
# Admin-UUID, der Partnerbuild ist sauber) oder ueber die
# Superset-Regel (es enthaelt saemtliche UUIDs des Admin-Builds). Beide
# sind korrekt, die Diagnose unterscheidet sich nur im Wortlaut.
DETECTED = ('nur im Admin-Build', 'sämtliche UUIDs',
            'Admin-Zugang', 'Admin-UUID')


def detected(out: str) -> bool:
    return any(marker in out for marker in DETECTED)


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


@case('öffentlicher APK enthält die Admin-UUID -> FEHLER')
def _c1(tmp, admin):
    world = make_world(tmp, ['play.apk', 'fdroid.apk'], admin,
                      secret_in={'play.apk'})
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, 'muss fehlschlagen'
    assert detected(out), out[-400:]


@case('Admin-UUID im .aab -> FEHLER (deflateter Inhalt)')
def _c2(tmp, admin):
    world = make_world(tmp, ['play.apk', 'play.aab'], admin,
                       secret_in={'play.aab'})
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, f'muss fehlschlagen - .aab wird nicht entpackt gelesen'
    assert detected(out), out[-400:]


@case('Admin-Build unter öffentlichem Namen -> FEHLER')
def _c3(tmp, admin):
    world = make_world(tmp, ['play.apk', 'fdroid.apk'], admin)
    shutil.copyfile(world / 'v9.9.9' / 'admin' / 'play-ADMIN.apk',
                    world / 'v9.9.9' / 'play.apk')
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, 'muss fehlschlagen'
    assert 'byte-identisch' in out, out[-400:]


@case('leerer Versionsordner -> FEHLER statt grüner Null')
def _c4(tmp, admin):
    world = make_world(tmp, [], admin, with_admin=False)
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code == 1, f'muss mit 1 fehlschlagen, kam {code}'
    assert 'keine Artefakte' in out, out[-400:]


@case('fehlender Versionsordner -> FEHLER')
def _c8(tmp, admin):
    world = make_world(tmp, ['play.apk'], admin)
    cra.ROOT = tmp
    cra.RELEASES = world
    # Anderer Versionsordner als der, den make_world anlegt.
    cra.current_version = lambda: ('8.8.8', '88')
    code, out = run_checker()
    assert code == 1, f'muss mit 1 fehlschlagen, kam {code}'
    assert 'fehlt' in out, out[-400:]


@case('ALLE öffentlichen Artefakte kontaminiert -> trotzdem erkannt')
def _c9(tmp, admin):
    # Der haeufigste blinde Fleck: ist die Basis selbst verraet, ist die
    # Differenz leer und der Check sagt "keine unbekannte UUID".
    world = make_world(tmp, ['play.apk', 'fdroid.apk'], admin,
                       secret_in={'play.apk', 'fdroid.apk'})
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, 'muss fehlschlagen - sonst meldet er "sauber"'
    assert 'sämtliche UUIDs' in out or 'nur im Admin-Build' in out, out[-400:]


@case('sauberer Stand -> KEIN Fehler')
def _c5(tmp, admin):
    world = make_world(tmp, ['play.apk', 'fdroid.apk'], admin)
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert 'FEHLER' not in out, out[-600:]
    # 2 = alles in Ordnung, Signatur aber ungeprueft (kein apksigner).
    assert code == 2, f'erwartet 2 (ungepruefte Signatur), kam {code}'


@case('kaputtes .aab -> FEHLER, nicht "enthält nichts"')
def _c6(tmp, admin):
    world = make_world(tmp, ['play.apk'], admin)
    (world / 'v9.9.9' / 'kaputt.aab').write_bytes(b'PK\x03\x04 kaputt')
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, 'muss fehlschlagen'
    assert 'nicht lesbar' in out or 'kaputt' in out, out[-400:]


@case('Admin-Build im Unterordner testapk/ -> erkannt')
def _c7(tmp, admin):
    world = make_world(tmp, ['play.apk'], admin)
    shots = world / 'testapk'
    shots.mkdir(exist_ok=True)
    shutil.copyfile(world / 'v9.9.9' / 'admin' / 'play-ADMIN.apk',
                    shots / 'screenshots.apk')
    cra.ROOT = tmp
    cra.RELEASES = world
    cra.current_version = lambda: ('9.9.9', '99')
    code, out = run_checker()
    assert code != 0, 'muss fehlschlagen - testapk/ wurde nicht gescannt'
    assert 'byte-identisch' in out, out[-400:]


def main():
    admin = uuid_str()
    failures = []
    print('=' * 70)
    print('SELBSTTEST check_release_artifacts.py')
    print('=' * 70)
    for name, fn in CASES:
        tmp = pathlib.Path(tempfile.mkdtemp(prefix='cra_selftest_'))
        try:
            fn(tmp, admin)
            print(f'  OK    {name}')
        except AssertionError as e:
            failures.append((name, str(e)))
            print(f'  FEHL  {name}')
            print(f'        {e}')
        except Exception as e:                       # noqa: BLE001
            failures.append((name, f'{type(e).__name__}: {e}'))
            print(f'  FEHL  {name}  ({type(e).__name__}: {e})')
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    print()
    if failures:
        print(f'{len(failures)} von {len(CASES)} Negativfaellen NICHT erkannt.')
        print('Der Checker ist dann nicht vertrauenswuerdig.')
        sys.exit(1)
    print(f'OK  alle {len(CASES)} Negativfaelle erkannt.')


if __name__ == '__main__':
    main()
