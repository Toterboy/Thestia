#!/usr/bin/env python3
"""Prueft, ob alle Release-Artefakte aus EINEM Build stammen.

Anlass (2026-10-05): Bei v0.9.2 lagen Universelle APK und AAB aus
verschiedenen Baustaenden im selben Ordner. Der Grund war ein Werkzeug,
nicht ein Fehler im Code: `build_release.ps1` baut ohne die Schalter
`-UniversalApk` / `-SplitPerAbi` gar nichts und meldet am Ende trotzdem
"Fertig". Ein alter Build wurde daraufhin fuer einen neuen gehalten.

Diese Pruefung beantwortet die Frage, die ein Zeitstempel-Print im
Bauskript nicht zuverlaessig beantwortet: sind die Dateien in diesem
Ordner ueberhaupt ein Release?

Geprueft wird:

1. **Einheitlicher Baustand.** Alle oeffentlichen Artefakte liegen
   innerhalb eines Zeitfensters. Sonst existiert der Ordner neben
   sich selbst.
2. **Berechtigungen im BINÄREN Manifest** jedes APK, nicht in der
   Quelldatei. `ACCESS_FINE_LOCATION` muss weg sein, die
   Speicherzugriffe muessen begrenzt sein.
3. **Keine `.env` im Artefakt.** Release-Builds duerfen die Datei nicht
   enthalten - sie waere sonst ein vollstaendiger Konfigurationsdump im
   Artefakt.
4. **Stammdaten stimmen ueberein.** versionCode, versionName,
   minSdk und targetSdk muessen in allen APKs gleich sein. Ein
   gemischter Ordner faellt hier zuverlaessig durch, auch wenn die
   Zeitstempel einmal taeuschen.
5. **Screenshots vorhanden.** Fuenf Screens als Pflicht fuer den
   Store-Eintrag.

Das Skript beendet sich mit Status 1, wenn etwas nicht stimmt, und
nennt jeden einzelnen Fund. Ein Fehlschlag ist hier kein Aerger,
sondern die Information, auf der ein Release beruht.

Aufruf::

    python tool/check_release_consistency.py

Zusaetzlich ``--allow-mixed`` fuer den Zwischenstand waehrend eines
Builds, wenn erst ein Teil der Artefakte neu ist.
"""

import argparse
import os
import re
import struct
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELEASE_DIR = os.path.join(ROOT, 'releases', 'v0.9.2')
SHOT_DIR = os.path.join(ROOT, 'fastlane', 'metadata', 'android', 'de-DE',
                        'images', 'phoneScreenshots')

# Fenstergroesse in Sekunden. Ein Release baut alle Artefakte in
# wenigen Minuten; zwei Stunden ist weit genug, um einen abgebrochenen
# und neu gestarteten Lauf zu ueberbruecken, und eng genug, um
# "gestern gebaut" zu erkennen.
FRESHNESS_WINDOW_S = 2 * 3600

# v0.10.0: 06_datenschutz ist dazugekommen. Ohne diesen Eintrag haette
# der Check das sechste Bild stillschweigend ignoriert - er meldet nur
# FEHLENDE Bilder, keine ueberzaehligen, und die Erfolgsmeldung stand
# fest auf "5".
EXPECTED_SHOTS = ['01_willkommen', '02_chat', '03_entdecken',
                  '04_anpassen', '05_eisbrecher', '06_datenschutz']

FORBIDDEN_PERMISSIONS = ['android.permission.ACCESS_FINE_LOCATION']
MAXSDK_PERMISSIONS = {
    'android.permission.READ_EXTERNAL_STORAGE': 32,
    'android.permission.WRITE_EXTERNAL_STORAGE': 28,
}


class Report:
    """Sammelt Befunde und haelt sie lesbar."""

    def __init__(self):
        self.failures = []
        self.notes = []

    def fail(self, msg):
        self.failures.append(msg)
        print('FEHLER  %s' % msg)

    def ok(self, msg):
        print('OK      %s' % msg)

    def note(self, msg):
        self.notes.append(msg)
        print('HINWEIS %s' % msg)


def find_aapt2():
    """Sucht aapt2 in den installierten Android-Build-Tools."""
    local = os.environ.get('LOCALAPPDATA')
    if not local:
        return None
    bt = os.path.join(local, 'Android', 'Sdk', 'build-tools')
    if not os.path.isdir(bt):
        return None
    versions = sorted((d for d in os.listdir(bt)
                       if os.path.isdir(os.path.join(bt, d))),
                      reverse=True)
    for v in versions:
        exe = os.path.join(bt, v, 'aapt2.exe')
        if os.path.exists(exe):
            return exe
        exe = os.path.join(bt, v, 'aapt2')
        if os.path.exists(exe):
            return exe
    return None


def dump_permissions(aapt2, apk):
    """Liest die Berechtigungen aus dem BINAEREN Manifest des APK."""
    try:
        out = subprocess.run([aapt2, 'dump', 'permissions', apk],
                             capture_output=True, text=True, timeout=120)
    except Exception as e:                                  # noqa: BLE001
        return None, str(e)
    perms = {}
    for m in re.finditer(r"uses-permission: name='([^']+)'"
                         r"(?: maxSdkVersion='(\d+)')?", out.stdout):
        perms[m.group(1)] = int(m.group(2)) if m.group(2) else None
    return perms, None


def dump_badging(aapt2, apk):
    """Liest versionCode, versionName, minSdk und targetSdk."""
    try:
        out = subprocess.run([aapt2, 'dump', 'badging', apk],
                             capture_output=True, text=True, timeout=120)
    except Exception as e:                                  # noqa: BLE001
        return None, str(e)
    txt = out.stdout
    def grab(pat, cast=str):
        m = re.search(pat, txt)
        return cast(m.group(1)) if m else None
    return {
        'versionCode': grab(r"versionCode='(\d+)'", int),
        'versionName': grab(r"versionName='([^']+)'"),
        'minSdk': grab(r"minSdkVersion:'(\d+)'", int),
        'targetSdk': grab(r"targetSdkVersion:'(\d+)'", int),
    }, None


def has_env_file(apk):
    """True, wenn das Artefakt eine .env enthaelt."""
    try:
        with zipfile.ZipFile(apk) as z:
            for n in z.namelist():
                if n.endswith('/.env') or n == '.env':
                    return True
    except zipfile.BadZipFile:
        return None
    return False


def public_artifacts():
    if not os.path.isdir(RELEASE_DIR):
        return []
    out = []
    for name in sorted(os.listdir(RELEASE_DIR)):
        if not (name.endswith('.apk') or name.endswith('.aab')):
            continue
        if 'ADMIN' in name:
            # Admin-Builds sind bewusst quarantanisieriert, werden
            # getrennt geprueft und nicht mitvermischt.
            continue
        out.append(os.path.join(RELEASE_DIR, name))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--allow-mixed', action='store_true',
                    help='Warnung statt Fehler bei gemischtem Baustand')
    args = ap.parse_args()

    rep = Report()

    arts = public_artifacts()
    if not arts:
        print('FEHLER  Keine Release-Artefakte unter %s' % RELEASE_DIR)
        return 1
    rep.ok('%d oeffentliche Artefakte gefunden' % len(arts))

    # --- 1) Einheitlicher Baustand -----------------------------------
    now = time.time()
    zeiten = [(a, os.path.getmtime(a)) for a in arts]
    neueste = max(t for _, t in zeiten)
    alteste = min(t for _, t in zeiten)
    spanne = neueste - alteste

    if spanne > FRESHNESS_WINDOW_S:
        msg = ('Baustand gemischt: aeltestes Artefakt %.1f h, juengstes %.1f h. '
               'Alle Dateien muessen aus einem Build stammen.'
               % (spanne / 3600.0, max(0, now - neueste) / 3600.0))
        for a, t in zeiten:
            print('        %-42s %s' % (os.path.basename(a),
                                        time.strftime('%d.%m. %H:%M',
                                                       time.localtime(t))))
        if args.allow_mixed:
            rep.note(msg + ' (zugelassen mit --allow-mixed)')
        else:
            rep.fail(msg)
    else:
        rep.ok('alle Artefakte aus einem Build (%d s Spanne)' % int(spanne))

    for a, t in zeiten:
        if now - t > FRESHNESS_WINDOW_S:
            rep.note('%s ist %.1f h alt - nicht aus diesem Release-Lauf'
                     % (os.path.basename(a), (now - t) / 3600.0))

    # --- 2/3/4) Inhalt der APKs ---------------------------------------
    aapt2 = find_aapt2()
    apks = [a for a in arts if a.endswith('.apk')]
    stammdaten = None

    if not aapt2:
        rep.fail('aapt2 nicht gefunden - Berechtigungspruefung uebersprungen')
    else:
        rep.ok('aapt2: %s' % os.path.basename(os.path.dirname(aapt2)))

        for apk in apks:
            name = os.path.basename(apk)

            perms, err = dump_permissions(aapt2, apk)
            if perms is None:
                rep.fail('%s: aapt2-Ausgabe nicht lesbar (%s)' % (name, err))
                continue

            for verboten in FORBIDDEN_PERMISSIONS:
                if verboten in perms:
                    rep.fail('%s enthaelt %s' % (name, verboten))

            for perm, maxsdk in MAXSDK_PERMISSIONS.items():
                if perm not in perms:
                    continue
                ist = perms[perm]
                if ist != maxsdk:
                    rep.fail('%s: %s hat maxSdkVersion=%s, erwartet %s'
                             % (name, perm, ist, maxsdk))

            env_drin = has_env_file(apk)
            if env_drin is True:
                rep.fail('%s enthaelt eine .env' % name)
            elif env_drin is None:
                rep.fail('%s ist kein lesbares ZIP/kein APK' % name)

            badging, err = dump_badging(aapt2, apk)
            if badging is None:
                rep.fail('%s: badging nicht lesbar (%s)' % (name, err))
                continue
            if stammdaten is None:
                stammdaten = dict(badging, quelle=name)
                if badging['targetSdk'] != 36:
                    rep.fail('%s: targetSdkVersion=%s, erwartet 36'
                             % (name, badging['targetSdk']))
            else:
                # versionCode NICHT direkt vergleichen: Split-APKs
                # tragen per Konvention einen ABI-Zusatz - armv7=1030,
                # arm64=2030, x86_64=4030 bei Basis 30. Das ist korrekt
                # und kein Mixed-Build. Ohne diese Normalisierung
                # meldet das Skript jeden Release als fehlerhaft.
                def norm(vc):
                    return None if vc is None else vc % 1000

                for k in ('versionName', 'minSdk', 'targetSdk'):
                    if badging[k] != stammdaten[k]:
                        rep.fail('%s: %s=%s, aber %s=%s (gemischter Ordner)'
                                 % (name, k, badging[k],
                                    stammdaten['quelle'], stammdaten[k]))

                if (norm(badging['versionCode'])
                        != norm(stammdaten['versionCode'])):
                    rep.fail('%s: versionCode=%s, aber %s=%s '
                             '(gemischter Ordner)'
                             % (name, badging['versionCode'],
                                stammdaten['quelle'],
                                stammdaten['versionCode']))

        if not rep.failures:
            rep.ok('Berechtigungen, .env-Freiheit und Stammdaten aller APKs ok')

    # --- 5) Screenshots -------------------------------------------------
    if not os.path.isdir(SHOT_DIR):
        rep.fail('Screenshot-Ordner fehlt: %s' % SHOT_DIR)
    else:
        pngs = sorted(f for f in os.listdir(SHOT_DIR) if f.endswith('.png'))
        fehlend = [s for s in EXPECTED_SHOTS
                   if not any(os.path.basename(p).startswith(s) for p in pngs)]
        if fehlend:
            rep.fail('Screenshots fehlen: %s' % ', '.join(fehlend))
        else:
            rep.ok('alle %d Store-Screenshots vorhanden'
                     % len(EXPECTED_SHOTS))

    print('')
    if rep.failures:
        print('%d Befund(e). Dieses Verzeichnis ist kein gueltiges Release.'
              % len(rep.failures))
        return 1

    print('OK  %d Artefakte: ein Build, Berechtigungen, Versionen, '
          'Screenshots stimmen.' % len(arts))
    return 0


if __name__ == '__main__':
    sys.exit(main())