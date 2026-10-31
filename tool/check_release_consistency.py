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

# Interne Screenshot-APKs (31.10.2026).
#
# BEFUND: Die Screenshot-APK war eine KOPIE des Play-APKs. Damit galt
# FLAG_SECURE - und Android blockiert mit FLAG_SECURE jeden Screenshot.
# In der installierten APK war es deshalb unmoeglich, die Store-Bilder
# aufzunehmen. Die Screenshot-APK wird jetzt mit
# THESTIA_ALLOW_SCREENSHOTS=true gebaut (build_release.ps1
# -ScreenshotApk), und der Check stellt das hier sicher.
TESTAPK_DIR = os.path.join(ROOT, 'releases', 'testapk')

# Fenstergroesse in Sekunden. Ein Release baut alle Artefakte in
# wenigen Minuten; zwei Stunden ist weit genug, um einen abgebrochenen
# und neu gestarteten Lauf zu ueberbruecken, und eng genug, um
# "gestern gebaut" zu erkennen.
FRESHNESS_WINDOW_S = 2 * 3600

# v0.10.0: 06_datenschutz ist dazugekommen. Ohne diesen Eintrag haette
# der Check das sechste Bild stillschweigend ignoriert - er meldet nur
# FEHLENDE Bilder, keine ueberzaehligen, und die Erfolgsmeldung stand
# fest auf "5".
#
# 31.10.2026: Die Kacheln sind neu nummeriert (die Aktuelles-Kachel
# kam als zweite dazu, der Hell/Dunkel-Split als sechste). Die Namen
# hier sind die KACHELNamen - sie muessen mit dem Store-Ordner
# uebereinstimmen, sonst meldet der Check zu Recht ein fehlendes Bild.
EXPECTED_SHOTS = ['01_willkommen', '02_aktuelles', '03_chat',
                  '04_entdecken', '05_anpassen', '06_hell_dunkel',
                  '07_eisbrecher', '08_datenschutz']

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


def manifest_meta(aapt2, apk, name):
    """Liest den Wert eines <meta-data>-Eintrags aus dem Manifest.

    Gibt den Wert als String zurueck, oder None wenn es den Eintrag
    nicht gibt.

    ACHTUNG - der Typ ist nicht stabil (31.10.2026): aapt2 kompiliert
    den Wert "true"/"false" als BOOLEAN, nicht als String. Im
    Manifest-Text sieht das so aus:

        A: ...android:value(0x01010024)=false

    Ein String-Wert dagegen kommt als

        A: ...android:value(0x01010024)=(type 0x12)0xffffffff (Raw: "true")

    Deshalb werden beide Formen gelesen. Wer nur nach `Raw: "..."`
    sucht, findet bei einem Boolean-Wert nichts und faelschlich
    "kein Eintrag".
    """
    try:
        out = subprocess.run(
            [aapt2, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'],
            capture_output=True, text=True, timeout=120)
    except Exception as e:                                  # noqa: BLE001
        return None, str(e)
    if out.returncode != 0:
        return None, out.stderr.strip() or 'aapt2-Ausgabe nicht lesbar'

    # Der Manifest-Baum ist eine Klammerhierarchie: jeder Block beginnt
    # mit "E: " (eingerueckt) und endet vor dem naechsten "E: ".
    bloecke = re.split(r'\n(?=\s*E: )', out.stdout)
    for block in bloecke:
        if 'android:name(0x01010003)="%s"' % name not in block:
            continue
        # Nur das WERT-Attribut lesen - der Block enthaelt auch das
        # name-Attribut, und dessen "Raw: ..." waere der Name, nicht
        # der Wert.
        treffer = re.search(
            r'android:value\(0x01010024\)=([^\n]*)', block)
        if not treffer:
            return '', None
        rest = treffer.group(1).strip()
        # Form 1: String - der lesbare Inhalt steht hinter "Raw: ".
        roh = re.search(r'Raw: "([^"]*)"', rest)
        if roh:
            return roh.group(1), None
        # Form 2: Boolean/Zahl - direkt hinter dem Gleichheitszeichen.
        kurz = re.match(r'([A-Za-z][A-Za-z0-9_-]*|0x[0-9a-fA-F]+)', rest)
        if kurz:
            return kurz.group(1), None
        return rest, None
    return None, None


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

    # --- 4b) Screenshot-Freigabe ---------------------------------------
    #
    # Zwei gegenlaeufige Anforderungen, beide geprueft:
    #
    # 1) Die oeffentlichen APKs duerfen KEINE Screenshots erlauben.
    #    FLAG_SECURE (MainActivity) ist ein Privatsphaerenschutz: ohne
    #    ihn kann jeder ein Foto eines Chats oder eines Profils einer
    #    fremden Person machen. Ein oeffentlicher Build mit
    #    "allowScreenshots=true" waere eine stille Abschaltung genau
    #    dieses Schutzes - und die waere im Store nicht sichtbar.
    #
    # 2) Die Screenshot-APK MUSS Screenshots erlauben. Sie ist genau
    #    dafuer da - sonst laesst sich damit kein Store-Bild
    #    aufnehmen. Bis 31.10.2026 war sie eine Kopie des Play-APKs
    #    (also "false"), und genau deshalb war es in der installierten
    #    APK unmoeglich, Screenshots zu machen.
    #
    # Beide Werte werden aus dem BINAREN Manifest gelesen, nicht aus
    # dem Quelltext - nur so zaehlt, was tatsaechlich im Artefakt ist.
    if aapt2:
        for apk in apks:
            name = os.path.basename(apk)
            wert, err = manifest_meta(aapt2, apk, 'allowScreenshots')
            if err:
                rep.fail('%s: Manifest nicht lesbar (%s)' % (name, err))
                continue
            if wert == 'true':
                rep.fail('%s erlaubt Screenshots (allowScreenshots=true) - '
                         'das ist fuer eine oeffentliche APK nicht erlaubt: '
                         'FLAG_SECURE schuetzt Chats und fremde Profile.'
                         % name)

        shot_apks = []
        if os.path.isdir(TESTAPK_DIR):
            shot_apks = sorted(
                os.path.join(TESTAPK_DIR, f)
                for f in os.listdir(TESTAPK_DIR)
                if f.endswith('.apk') and 'screenshot' in f)
        if not shot_apks:
            rep.note('keine Screenshot-APK unter %s - nicht geprueft'
                     % os.path.relpath(TESTAPK_DIR, ROOT))
        for apk in shot_apks:
            name = os.path.basename(apk)
            wert, err = manifest_meta(aapt2, apk, 'allowScreenshots')
            if err:
                rep.fail('%s: Manifest nicht lesbar (%s)' % (name, err))
                continue
            if wert != 'true':
                rep.fail('%s erlaubt KEINE Screenshots - damit laesst sich '
                         'kein Store-Bild aufnehmen (FLAG_SECURE blockt '
                         'jeden Screenshot). Neu bauen mit: '
                         'tool\\build_release.ps1 -Flavor play '
                         '-UniversalApk -ScreenshotApk' % name)
            else:
                rep.ok('%s: Screenshots erlaubt (richtig so)' % name)

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