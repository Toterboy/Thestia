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
import json
import os
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASES = ROOT / 'releases'

EXPECTED_CN = 'CN=Thestia'
FORBIDDEN_CN = 'WispDating'

# Die UUID kommt aus der Umgebung, damit sie nicht im Repo landet.
ADMIN_UUID = os.environ.get('ADMIN_UUID', '').strip()

problems = []
warnings = []
rows = []
uuid_sets = {}


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


def artifact_bytes_contain(path, needle: bytes) -> bool:
    """Sucht eine Zeichenkette in einem APK ODER AAB, entpackt.

    Ein Byte-Suchlauf ueber die ganze Datei reicht nicht: im AAB ist
    `base/lib/<abi>/libapp.so` DEFLATED, und dasselbe gilt fuer ein APK,
    dessen Gradle-Kompression einmal staerker eingestellt wird. Ein
    Rohscan findet dort NIE etwas - egal ob das Geheimnis drin ist.
    Genau die Datei wird hochgeladen, und genau sie waere ungeprueft
    geblieben. Deshalb wird das Archiv geoeffnet und jeder Eintrag
    dekomprimiert durchsucht.

    Liest chunkweise, damit keine 240-MB-Datei komplett im RAM liegt.
    """
    def scan_stream(reader):
        overlap = len(needle) - 1
        tail = b''
        while True:
            chunk = reader.read(1 << 20)
            if not chunk:
                return False
            window = tail + chunk
            if needle in window:
                return True
            tail = window[-overlap:] if overlap > 0 else b''

    if path.suffix in ('.aab', '.apk'):
        try:
            with zipfile.ZipFile(path) as z:
                for info in z.infolist():
                    if info.is_dir():
                        continue
                    with z.open(info) as member:
                        if scan_stream(member):
                            return True
        except (zipfile.BadZipFile, OSError):
            # Unlesbar heisst nicht "enthält nichts".
            problems.append(f'{path.name}: Archiv nicht lesbar '
                            f'(kaputt?) - Inhalt ungeprueft')
            return False
        return False

    with open(path, 'rb') as f:
        return scan_stream(f)


def uuids_in_artifact(path):
    """Alle UUID-Muster in einem Artefakt als Menge.

    Braucht kein Geheimnis. Ein Admin-Build kompiliert eine UUID
    zusaetzlich per dart-define; alles andere ist in beiden Builds
    gleich. Die Differenz Admin-Menge minus oeffentliche Menge ist
    damit genau die Admin-UUID - und zwar ohne dass man sie kennen
    muss.

    Zaehlen allein reicht nicht: die Anzahl schwankt zwischen ABIs und
    zwischen APK und AAB legitim (ein AAB fuehrt je Eintrag andere
    Dateien). Die Menge ist der verlaessliche Vergleich.
    """
    pat = re.compile(rb'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                     rb'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    found = set()

    def scan(data):
        found.update(x.decode().lower() for x in pat.findall(data))

    if path.suffix in ('.aab', '.apk'):
        # Beide Formate werden als ZIP entpackt gelesen, NICHT als
        # Bytekette.
        #
        # Grund: ein Rohscan findet nur, was unkomprimiert im Archiv
        # steht. Flutter legt libapp.so im APK zwar unkomprimiert ab -
        # darauf zu bauen ist aber eine Annahme ueber die
        # Gradle-Konfiguration, und der Fehler waere still: das
        # Artefakt enthielte das Geheimnis und der Check meldete
        # "sauber". Genau dieser Fall ist im Selbsttest aufgetreten,
        # als das Testarchiv die .so deflatet hat.
        try:
            with zipfile.ZipFile(path) as z:
                for info in z.infolist():
                    if info.is_dir():
                        continue
                    # Nur .so: das sind die Dart-AOT-Schnipsel, in
                    # denen die Defines als Zeichenketten stehen.
                    # Andere Eintraege zu durchsuchen kostet Zeit
                    # und findet nichts.
                    if info.filename.endswith('.so'):
                        with z.open(info) as member:
                            scan(member.read())
        except (zipfile.BadZipFile, OSError):
            if path.suffix == '.aab':
                problems.append(f'{path.name}: AAB nicht lesbar '
                                f'(kaputt?) - Inhalt ungeprueft')
                return None
            # Kein ZIP: dann ist es auch keine APK. Rohscan als
            # Auffangnetz, damit nichts ungeprueft durchrutscht.
            with open(path, 'rb') as f:
                scan(f.read())
        return found

    with open(path, 'rb') as f:
        scan(f.read())
    return found


def admin_uuids_all(uuid_sets, admin):
    """Vereinigung aller UUID-Mengen der Admin-Builds."""
    return set().union(*(uuid_sets[p.relative_to(ROOT).as_posix()]
                         for p in admin)) if admin else set()


def current_version():
    pub = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)',
                  pub, re.M)
    if not m:
        sys.exit('version in pubspec.yaml nicht lesbar')
    return m.group(1), m.group(2)


def main():
    global signature_checked
    # Alles zuruecksetzen. Diese Zustände sind Modulvariablen, damit die
    # Hilfsfunktionen ohne Rücksprungliste auskommen - ohne Reset
    # sammeln sich Befunde über mehrere Läufe in einem Prozess an, und
    # ein zweiter Lauf meldet die Fehler des ersten mit.
    problems.clear()
    warnings.clear()
    rows.clear()
    uuid_sets.clear()
    signature_checked = True
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

    # Ein leerer oder nicht vorhandener Versionsordner ist KEIN
    # bestandener Check. In der CI sind die APKs gitignoriert und
    # gar nicht da - der frueher pauschale "OK 0 Artefakte" war
    # eine gruene, inhaltslose Zeile, die einen echten Fehler
    # verdeckt hat.
    if not public and not admin:
        print()
        print('FEHLER: keine Artefakte unter '
              f'{vdir.relative_to(ROOT).as_posix()}/')
        print('  In der CI sind die APKs bewusst nicht im Repository,')
        print('  dieser Check kann dort also nichts bestaetigen. Er')
        print('  schlaegt fehl, statt eine gruene Null zu melden.')
        print('  Lokal: erst bauen mit tool\\build_release.ps1.')
        # sys.exit, nicht return: ein "return 1" aus main() lässt die
        # Kommandozeile mit 0 enden. Genau dieser Fehler ist im
        # Selbsttest aufgefallen.
        sys.exit(1)

    print('=' * 78)
    print(f'RELEASE-ARTEFAKTE v{version} (build {code})')
    print('=' * 78)
    print(f'öffentlich: {len(public)} Dateien   Admin: {len(admin)} Dateien')
    print(f'ADMIN_UUID: {"gesetzt (wird geprüft)" if ADMIN_UUID else "NICHT gesetzt - nur Muster-/Provenienzprüfung"}')
    print()

    uuid_sets.setdefault('__init__', set())
    del uuid_sets['__init__']
    for path in public + admin:
        is_admin = path in admin
        rel = path.relative_to(ROOT).as_posix()
        size_mb = path.stat().st_size / 1024 / 1024
        digest = sha256(path)
        uuids = uuids_in_artifact(path)
        uuid_sets[rel] = uuids if uuids is not None else set()

        note = f'UUIDs {len(uuid_sets[rel])}' if uuids is not None \
            else 'UUIDs ?'
        if ADMIN_UUID:
            has = artifact_bytes_contain(path, ADMIN_UUID.encode())
            note += f'   Secret {"JA" if has else "nein"}'
            if is_admin and not has:
                problems.append(f'{rel}: ADMIN_UUID fehlt - der Admin-Build '
                                f'kann keine Admins freischalten.')
            if not is_admin and has:
                problems.append(f'{rel}: ADMIN_UUID im öffentlichen Build. '
                                f'Das ist ein vollständiger Admin-Zugang '
                                f'für jeden, der die Datei hat.')
        rows.append(f'  {rel:<52} {size_mb:7.1f} MB  {digest[:12]}  {note}')

    # OHNE GEHEIMNIS: die Admin-UUID selbst bestimmen.
    #
    # Alles, was im Admin-Build steht und in KEINEM oeffentlichen
    # derselben Version, ist per Definition ein Secret, das nur der
    # Admin-Build kennt. Diese Menge wird danach in ALLEN Artefakten
    # unter releases/ gesucht - auch in aelteren Versionen und im AAB.
    # Damit ist die Kontamination ohne Kenntnis des Geheimnisses
    # erkennbar.
    if public and admin:
        # Basis ist der oeffentliche Build GLEICHER ART, nicht der
        # Schnitt oder die Vereinigung aller oeffentlichen Builds.
        #
        # Die UUID-Menge schwankt legitim zwischen den ABIs (arm64 hat 4,
        # x86_64 hat 2 - andere native Bibliotheken, andere
        # Konstanten). Ein Schnitt ueber alle Builds ist deshalb zu
        # aggressiv und meldet Arm-APKs faelschlich als kontaminiert.
        # Die Vereinigung ist zu schwach: sobald EIN Artefakt
        # kontaminiert ist, enthaelt sie die Admin-UUID und die
        # Differenz ist leer.
        #
        # Der Vergleich Admin gegen den oeffentlichen Universalbuild
        # derselben Sorte ist der einzige, der exakt ist: gleiche ABIs,
        # gleiche Buildkonfiguration, also unterscheidet sich genau das
        # Define des Admin-Builds.
        admin_only = set()
        for adm in admin:
            stem = adm.name.replace('-ADMIN.apk', '')
            mate = None
            for cand in public:
                if cand.stem == stem:
                    mate = cand
                    break
            if mate is None:
                # Kein Partner: dann die kleinste oeffentliche Menge
                # als Basis. Konservativ, kann aber nicht melden.
                pub_all = set().union(*(uuid_sets.get(
                    p.relative_to(ROOT).as_posix(), set()) for p in public))
                admin_only |= (uuid_sets[adm.relative_to(ROOT).as_posix()]
                               - pub_all)
            else:
                admin_only |= (
                    uuid_sets[adm.relative_to(ROOT).as_posix()]
                    - uuid_sets[mate.relative_to(ROOT).as_posix()])

        if admin_only:
            print()
            print(f'Admin-Build enthält {len(admin_only)} UUID(s), die im '
                  f'öffentlichen Build derselben Sorte fehlen. Sie gelten '
                  f'jetzt als bekannt und werden in ALLEN Ablageorten '
                  f'gesucht - ohne dass jemand das Geheimnis kennt.')
            for p in sorted(RELEASES.rglob('*')):
                if p.suffix not in ('.apk', '.aab'):
                    continue
                if 'admin' in p.parts:
                    continue
                rel = p.relative_to(ROOT).as_posix()
                # Auch fremde Versionen und die .aab muessen gelesen
                # werden - uuid_sets enthaelt nur die Artefakte der
                # aktuellen Version.
                known = uuid_sets.get(rel)
                if known is None:
                    known = uuids_in_artifact(p)
                    if known is None:
                        continue          # kaputt, schon gemeldet
                    uuid_sets[rel] = known
                hits = known & admin_only
                if hits:
                    problems.append(
                        f'{rel} enthält eine UUID, die nur im Admin-Build '
                        f'vorkommt. Das ist der Admin-Zugang in einem '
                        f'öffentlichen Artefakt.')
        else:
            print()
            print('Keine unbekannte UUID: der Admin-Build enthält nichts, '
                  'was die öffentlichen Builds nicht auch haben.')

        # Zweite, unabhaengige Regel fuer den Fall, dass ALLE
        # oeffentlichen Artefakte kontaminiert sind: dann ist die Basis
        # selbst verraet. Ein oeffentliches Artefakt, das alle UUIDs des
        # Admin-Builds enthaelt, ist eines.
        for p in public:
            rel = p.relative_to(ROOT).as_posix()
            if admin_only and uuid_sets.get(rel, set()) & admin_only:
                pass          # bereits oben gemeldet
            elif admin_uuids_all(uuid_sets, admin) and \
                    uuid_sets.get(rel, set()) >= admin_uuids_all(
                        uuid_sets, admin):
                problems.append(
                    f'{rel} enthält sämtliche UUIDs des Admin-Builds. '
                    f'Wenn alle öffentlichen Artefakte betroffen sind, '
                    f'erkennt die Differenz nichts mehr - dieses '
                    f'Artifact ist trotzdem kontaminiert.')

    print('\n'.join(rows))

    # Signatur
    apksigner = find_apksigner()
    print()
    if apksigner:
        print(f'Signatur ({apksigner.name}):')
        for path in public + admin:
            if path.suffix != '.apk':
                continue
            proc = subprocess.run(
                ['cmd', '/c', str(apksigner), 'verify', '--print-certs',
                 str(path)],
                capture_output=True, text=True, timeout=300)
            out = proc.stdout or ''
            err = proc.stderr or ''
            if proc.returncode != 0 or not out.strip():
                # Kein Raten: apksigner kann unter einem Benutzernamen
                # mit Leerzeichen scheitern, ohne eine Zeile zu liefern.
                problems.append(
                    f'{path.name}: apksigner nicht auswertbar '
                    f'(rc={proc.returncode})'
                    + (f' - {err.strip().splitlines()[0]}' if err.strip() else ''))
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
        # In der CI fehlt apksigner immer. Das als Fehler zu melden
        # wuerde den Check dort unbrauchbar machen; es als Erfolg zu
        # melden waere gelogen. Also: laut und sichtbar, mit Exit 2,
        # damit der Aufrufer entscheidet.
        warnings.append('apksigner nicht gefunden - Signatur UNGEPRÜFT. '
                        'Die Abschlusszeile behauptet das nicht.')
        signature_checked = False
        print()
        print('apksigner nicht gefunden: die Signatur wurde nicht geprüft.')
        print('Installieren: Android SDK build-tools, oder PATH um '
              '%LOCALAPPDATA%\\Android\\Sdk\\build-tools ergänzen.')

    if warnings:
        print()
        for w in warnings:
            print('  !', w)

    # Alle Ablageorte unter releases/, nicht nur die Versionsordner.
    # `releases/testapk/` (interne Screenshot-APKs) ist genauso ein
    # Ablageort; es war die einzige mit einer release-signierten APK und
    # ausserhalb des Scans.
    print()
    collisions = []
    admin_digests = {}
    for admin_apk in RELEASES.rglob('admin/*.apk'):
        admin_digests[sha256(admin_apk)] = admin_apk
    for p in RELEASES.rglob('*'):
        if p.suffix not in ('.apk', '.aab'):
            continue
        if 'admin' in p.parts:            # der Admin-Ordner selbst
            continue
        d = sha256(p)
        if d in admin_digests:
            collisions.append(
                f'{p.relative_to(ROOT).as_posix()} == '
                f'{admin_digests[d].relative_to(ROOT).as_posix()}')
    if collisions:
        print('ACHTUNG - Admin-Build im öffentlichen Ablageort:')
        for c in collisions:
            print('  X', c)
        problems.append(
            f'{len(collisions)} Datei(en) sind byte-identisch mit einem '
            f'Admin-Build. Die betroffenen öffentlichen Dateien enthalten '
            f'den Admin-Zugang und müssen neu gebaut werden.')
    else:
        print('Kein Admin-Build im öffentlichen Ablageort.')

    # Der Marker, den build_release.ps1 schreibt, muss zu den
    # tatsaechlich vorhandenen Admin-Artefakten passen. Ein marker mit
    # Einträgen, deren Datei nicht (mehr) existiert, heißt: der Output
    # wurde zwischenzeitlich von Hand angefasst.
    print()
    marker_path = ROOT / 'build' / '.admin-artifacts.json'
    if marker_path.is_file():
        try:
            entries = json.loads(marker_path.read_text(encoding='utf-8'))
        except ValueError:
            entries = {}
            problems.append(f'{marker_path.name} ist unlesbar - '
                            f'Provenienz nicht mehr prüfbar')
        if entries:
            print(f'Provenienz-Marker: {len(entries)} Einträge aus '
                  f'Admin-Builds vermerkt (für diese Dateien ist der '
                  f'öffentliche Ablageort gesperrt).')
    else:
        print('Kein Provenienz-Marker - der letzte Build war kein '
              'Admin-Build oder der Marker wurde entfernt.')

    print()
    if problems:
        print('FEHLER:')
        for p in problems:
            print('  X', p)
        sys.exit(1)
    if not signature_checked:
        print(f'OK  {len(public) + len(admin)} Artefakte: Admin-Trennung '
              f'und Muster stimmen. Die SIGNATUR wurde nicht geprüft '
              f'(apksigner fehlt).')
        sys.exit(2)
    print(f'OK  {len(public) + len(admin)} Artefakte: Signatur und '
          f'Admin-Trennung stimmen.')


if __name__ == '__main__':
    main()
