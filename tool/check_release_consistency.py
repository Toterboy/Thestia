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

# Der Release-Ordner der AKTUELLEN Version.
#
# BEFUND (07.11.2026): Hier stand fest 'releases/v0.9.2'. Der Ordner
# ist damit auf eine alte Version verklebt: die Abnahme von v0.10.0
# pruefte die Dateien von v0.9.2 und meldete "9 Artefakte: ein Build,
# Berechtigungen, Versionen ok" - fuer Dateien, die zwei Versionen alt
# waren. Der Ordner folgt jetzt der Version aus pubspec.yaml; wer einen
# anderen Ordner pruefen will, nennt ihn mit --dir.
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

FORBIDDEN_PERMISSIONS = ['android.permission.ACCESS_BACKGROUND_LOCATION',
                          'android.permission.READ_CONTACTS',
                          'android.permission.READ_CALL_LOG',
                          'android.permission.READ_SMS',
                          'android.permission.QUERY_ALL_PACKAGES']

# Berechtigungen, die nur mit einer Obergrenze erlaubt sind.
#
# BEFUND (07.11.2026): ACCESS_FINE_LOCATION stand hier auf der
# Verbotsliste - richtig fuer v0.9.2, aber falsch fuer v0.10.0. Auf
# Android 11 und aelter verlangt Android fuer den BLE-Scan die genaue
# Standortberechtigung; ohne sie blockiert das System den Scan still
# (der Befund vom 06.11.2026). Die Berechtigung ist deshalb wieder
# da, aber begrenzt auf maxSdkVersion=30 - auf aktuellen Geraeten
# aendert sich nichts.
#
# Die Regel lautet also nicht "darf nicht vorkommen", sondern
# "wenn, dann nur mit dieser Obergrenze". Genau das prueft der Code.
MAXSDK_PERMISSIONS = {
    'android.permission.READ_EXTERNAL_STORAGE': 32,
    'android.permission.WRITE_EXTERNAL_STORAGE': 28,
    'android.permission.ACCESS_FINE_LOCATION': 30,
    'android.permission.BLUETOOTH': 30,
    'android.permission.BLUETOOTH_ADMIN': 30,
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


def _proto_felder(data):
    """Liest die Protobuff-Felder einer Nachricht (AOSP resources.proto)."""
    pos = 0
    n = len(data)
    while pos < n:
        schluessel = 0
        schicht = 0
        while True:
            byte = data[pos]
            pos += 1
            schluessel |= (byte & 0x7F) << schicht
            schicht += 7
            if not byte & 0x80:
                break
        nummer = schluessel >> 3
        art = schluessel & 0x07
        if art == 0:
            wert = 0
            schicht = 0
            while True:
                byte = data[pos]
                pos += 1
                wert |= (byte & 0x7F) << schicht
                schicht += 7
                if not byte & 0x80:
                    break
            yield nummer, art, wert
        elif art == 2:
            laenge = 0
            schicht = 0
            while True:
                byte = data[pos]
                pos += 1
                laenge |= (byte & 0x7F) << schicht
                schicht += 7
                if not byte & 0x80:
                    break
            yield nummer, art, data[pos:pos + laenge]
            pos += laenge
        elif art == 5:
            yield nummer, art, int.from_bytes(data[pos:pos + 4], 'little')
            pos += 4
        elif art == 1:
            yield nummer, art, int.from_bytes(data[pos:pos + 8], 'little')
            pos += 8
        else:
            return


def _proto_text(roh):
    """Ist das lesbarer Text (und kein Protobuff-Zahlenwert)?"""
    try:
        s = roh.decode('utf-8')
    except UnicodeDecodeError:
        return None
    if not s.strip():
        return None
    if not all(32 <= ord(c) < 127 or c in '\r\n\t' for c in s):
        return None
    return s


def _proto_element(roh):
    """Liefert (name, {attribut: wert}, [kinder]) eines XmlElement.

    Das Manifest eines AAB ist Protobuff, kein Binaer-XML - deshalb
    laesst sich aapt2 dafuer nicht benutzen. Das Format (AOSP
    resources.proto):

        XmlElement.name      = 3 (string)
        XmlElement.attribute = 4 (repeated XmlAttribute)
        XmlElement.child     = 5 (repeated XmlNode)
        XmlNode.element      = 1 (XmlElement)
        XmlNode.source       = 3 (Quelle: 1 = Datei, 2 = Zeile)
        XmlAttribute.namespace_uri = 1
        XmlAttribute.name    = 2
        XmlAttribute.value   = 3

    ACHTUNG: Der Quellbezug (XmlNode.source) steht ebenfalls im Feld 3
    und sieht aus wie ein Name, ist aber keiner - erkennbar daran,
    dass er kein lesbarer Text ist.
    """
    name = ''
    attribute = {}
    kinder = []
    attribute_rohdaten = []
    kind_rohdaten = []
    eingebettet = []

    for nummer, art, inhalt in _proto_felder(roh):
        if nummer == 1 and art == 2:
            eingebettet.append(inhalt)
        elif nummer == 3 and art == 2:
            text = _proto_text(inhalt)
            if text is not None:
                name = text
        elif nummer == 4 and art == 2:
            attribute_rohdaten.append(inhalt)
        elif nummer == 5 and art == 2:
            kind_rohdaten.append(inhalt)

    if not name:
        for inhalt in eingebettet:
            t_name, t_attr, t_kind = _proto_element(inhalt)
            if t_name:
                name, attribute, kinder = t_name, t_attr, t_kind
                break

    for inhalt in attribute_rohdaten:
        aname = awert = ''
        for n2, a2, i2 in _proto_felder(inhalt):
            if n2 == 2 and a2 == 2:
                aname = i2.decode('utf-8', 'replace')
            elif n2 == 3 and a2 == 2:
                text = _proto_text(i2)
                if text is not None:
                    awert = text
        if aname:
            attribute[aname] = awert

    for inhalt in kind_rohdaten:
        kinder.append(_proto_element(inhalt))

    return name, attribute, kinder


def dump_aab_manifest(aab):
    """Liest versionCode, versionName und die Berechtigungen aus dem AAB.

    WARUM ueberhaupt: In den Play Store geht das AAB, nicht das APK.
    Die APK-Pruefung oben sah bisher nur an den APK-Dateien vorbei -
    die Datei, die tatsaechlich hochgeladen wird, war ungeprueft.
    """
    try:
        with zipfile.ZipFile(aab) as z:
            roh = z.read('base/manifest/AndroidManifest.xml')
    except Exception as e:                                  # noqa: BLE001
        return None, str(e)

    for nummer, art, inhalt in _proto_felder(roh):
        if nummer == 1 and art == 2:
            roh = inhalt
            break

    wurzel = _proto_element(roh)
    attribute = wurzel[1]

    perms = {}
    stack = [wurzel]
    while stack:
        name, attr, kinder = stack.pop()
        if name == 'uses-permission':
            ziel = ''
            for k, v in attr.items():
                if k == 'name' or k.endswith(':name'):
                    ziel = v
            if ziel:
                maxsdk = None
                for k, v in attr.items():
                    if k.endswith('maxSdkVersion'):
                        maxsdk = int(v)
                perms[ziel] = maxsdk
        stack.extend(kinder)

    return {
        'versionCode': int(attribute['versionCode'])
        if attribute.get('versionCode') else None,
        'versionName': attribute.get('versionName'),
        'package': attribute.get('package'),
        'permissions': perms,
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


def berechtigungs_probleme(perms):
    """Prueft eine Berechtigungsliste gegen die Regeln.

    Gibt eine Liste von Fehlertexten zurueck (leer = alles in Ordnung).

    Die Regeln:
      * `FORBIDDEN_PERMISSIONS` duerfen gar nicht vorkommen.
      * `MAXSDK_PERMISSIONS` duerfen vorkommen, aber nur mit genau der
        angegebenen Obergrenze. Ohne Obergrenze waere die Berechtigung
        auf ALLEN Geraeten aktiv - das ist beim Standort genau das,
        was Google Play moniert.

    Getrennt in eine eigene Funktion, damit der Selbsttest sie ohne
    eine fertige APK pruefen kann.
    """
    probleme = []
    for verboten in FORBIDDEN_PERMISSIONS:
        if verboten in perms:
            probleme.append('enthaelt %s' % verboten)
    for perm, maxsdk in MAXSDK_PERMISSIONS.items():
        if perm not in perms:
            continue
        ist = perms[perm]
        if ist != maxsdk:
            probleme.append('%s hat maxSdkVersion=%s, erwartet %s'
                            % (perm, ist, maxsdk))
    return probleme


def release_dir_aus_pubspec():
    """Der Release-Ordner der aktuellen Version aus pubspec.yaml."""
    pfad = os.path.join(ROOT, 'pubspec.yaml')
    try:
        with open(pfad, encoding='utf-8') as f:
            inhalt = f.read()
    except OSError:
        return None
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)',
                  inhalt, re.M)
    if not m:
        return None
    return os.path.join(ROOT, 'releases', 'v' + m.group(1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--allow-mixed', action='store_true',
                    help='Warnung statt Fehler bei gemischtem Baustand')
    ap.add_argument('--dir', default=None,
                    help='Release-Ordner (Vorgabe: die aktuelle Version '
                         'aus pubspec.yaml)')
    args = ap.parse_args()

    global RELEASE_DIR
    RELEASE_DIR = args.dir or release_dir_aus_pubspec() or RELEASE_DIR

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

            for problem in berechtigungs_probleme(perms):
                rep.fail('%s: %s' % (name, problem))


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

    # --- 4c) Das AAB - die Datei, die tatsaechlich hochgeladen wird ---
    #
    # BEFUND (07.11.2026): Das AAB wurde ueberhaupt nicht geprueft. Es
    # ist aber genau die Datei, die in den Play Store geht. Ein AAB
    # aus einem anderen Build (etwa versionCode 37, weil der Ordner
    # noch eine alte Datei enthaelt) waere beim Upload eine
    # Katastrophe - der Store nimmt die hoehere versionCode nicht
    # an, und der Fehler faellt erst nach dem Upload auf.
    aabs = [a for a in arts if a.endswith('.aab')]
    for aab in aabs:
        name = os.path.basename(aab)
        daten, err = dump_aab_manifest(aab)
        if daten is None:
            rep.fail('%s: Manifest nicht lesbar (%s)' % (name, err))
            continue

        if daten['package'] != 'com.thestia.app':
            rep.fail('%s: package=%s, erwartet com.thestia.app'
                     % (name, daten['package']))

        if stammdaten is None:
            rep.fail('%s: kein APK zum Abgleich vorhanden' % name)
            continue

        # Die Split-APKs tragen per Konvention einen ABI-Zusatz
        # (armv7=1030, arm64=2030, x86_64=4030 bei Basis 30). Das AAB
        # traegt den nackten Basis-Wert.
        if (daten['versionCode'] % 1000) != (stammdaten['versionCode'] % 1000):
            rep.fail('%s: versionCode=%s, aber die APKs haben %s '
                     '(gemischter Ordner)'
                     % (name, daten['versionCode'],
                        stammdaten['versionCode']))
        if daten['versionName'] != stammdaten['versionName']:
            rep.fail('%s: versionName=%s, aber die APKs haben %s '
                     '(gemischter Ordner)'
                     % (name, daten['versionName'], stammdaten['versionName']))

        # Die Berechtigungen des AAB gegen dieselben Regeln pruefen
        # wie die der APKs - im Manifest des AAB ist alles enthalten,
        # auch das, was aus den Paketen hineingemerged wurde.
        for problem in berechtigungs_probleme(daten['permissions']):
            rep.fail('%s: %s' % (name, problem))

        if not rep.failures:
            rep.ok('%s: versionCode=%s, versionName=%s, %d Berechtigungen '
                   'wie erwartet'
                   % (name, daten['versionCode'], daten['versionName'],
                      len(daten['permissions'])))

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