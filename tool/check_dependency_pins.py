"""Dependency-Pin-Audit für v0.9.2 (Roadmap-Punkt 6).

Zwei Probleme, die `flutter pub outdated` allein nicht abdeckt:

1. Sicherheitsrelevante Pakete standen auf `^`. Bei Krypto-, Keystore- und
   Transport-Paketen kann ein Minor-Bump das Laufzeitverhalten ändern, ohne
   dass es im Diff auftaucht. Sie sind jetzt auf exakte Versionen gepinnt -
   aufgelöst wird die Version, die tatsächlich ausgeliefert wird.

2. Sieben lokale Forks liegen als `dependency_overrides` mit `path:` vor.
   Für die ist `pub outdated` blind - sie tauchen in keinem
   Dependency-Report auf und müssen gesondert geführt werden.

Aufruf:
    python tool/check_dependency_pins.py           # Prüfung
    python tool/check_dependency_pins.py --lock    # + gegen pubspec.lock
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBSPEC = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8', errors='replace')
LOCK = (ROOT / 'pubspec.lock').read_text(encoding='utf-8', errors='replace')

# ---------------------------------------------------------------- Sicherheitsrelevant
# Begründung je Paket - nicht nur eine Liste, sonst wird das Pinning beim
# nächsten Umbenennen stillschweigend aufgeweicht.
SECURITY_CRITICAL = {
    'flutter_secure_storage': 'Keystore/Keychain - Schlüsselverlust bei Regression',
    'libsignal_protocol_dart': 'E2E-Verschlüsselung, Protokoll-Kompatibilität',
    'pointycastle': 'Krypto-Primitive für Backup-Verschlüsselung',
    'crypto': 'Krypto-Primitive, AES/HMAC',
    'http': 'TLS-Transport zu Supabase/Edge Functions',
    'flutter_webrtc': 'Medien-Transport, DTLS/SRTP',
    'flutter_blue_plus': 'BLE-Scan, Transit Spark',
    'onnxruntime': 'Native Inferenz, CVEs dort sind ausnutzbar',
    'image': 'Dekodiert Nutzerbilder (Decompression-Bomb)',
    'camera': 'Kamerazugriff',
    'firebase_core': 'Push-Transport',
    'firebase_messaging': 'Push-Transport',
    'permission_handler': 'Berechtigungen (Kamera, Mikrofon, Standort)',
    'path_provider': 'Zugriff auf private App-Verzeichnisse',
    'shared_preferences': 'Unverschlüsselte Einstellungen',
    'flutter_local_notifications': 'Lokale Benachrichtigungen',
    'url_launcher': 'Öffnet beliebige URLs aus Nutzerdaten',
}

# Bewusst NICHT gepinnt - mit Begründung, damit die Ausnahme nicht
# stillschweigend zur Regel wird.
ALLOWED_CARET = {
    'intl': 'Von flutter_localizations (Flutter-SDK) gepinnt - eine exakte '
            'Constraint bricht die Abhängigkeitsauflösung',
    'cupertino_icons': 'Reines Icon-Asset ohne Laufzeitverhalten',
    'flutter_lints': 'Nur Analyse-Regeln, kein Laufzeitverhalten',
    'build_runner': 'dev_dependency, Codegenerierung',
    'hive_generator': 'dev_dependency, Codegenerierung',
    'flutter_launcher_icons': 'dev_dependency, Asset-Erzeugung',
    'flutter_native_splash': 'dev_dependency, Asset-Erzeugung',
}

# SDK-Pseudo-Pakete: nicht pinnen, nicht als Drift werten.
SDK_PACKAGES = {'flutter', 'flutter_test', 'flutter_web_plugins', 'integration_test'}

pat_override = re.compile(r'^  ([a-z_0-9]+):\s*\n\s*path:\s*(\S+)', re.M)


def locked_version(pkg):
    m = re.search(rf'\n  {re.escape(pkg)}:\n(?:[^\n]*\n)*?    version: "([^"]+)"', LOCK)
    return m.group(1) if m else None


def direct_deps():
    out = {}
    for m in re.finditer(r'^  ([a-z_0-9]+):\s*(\^[0-9][^\s#]*|[0-9][^\s#]*)\s*$',
                         PUBSPEC, re.M):
        out[m.group(1)] = m.group(2)
    return out


def local_forks():
    return dict(pat_override.findall(PUBSPEC))


def main():
    direct = direct_deps()
    results = []

    def check(ok, label, detail=''):
        results.append((bool(ok), label, detail))

    print('=' * 76)
    print('DEPENDENCY-PIN-AUDIT')
    print('=' * 76)

    caret = {k: v for k, v in direct.items() if v.startswith('^')}
    print(f'\n1) Direkte Abhängigkeiten: {len(direct)} insgesamt, '
          f'{len(caret)} mit "^", {len(direct) - len(caret)} exakt gepinnt')

    print('\n2) Sicherheitsrelevante Pakete')
    unpinned = []
    for pkg, why in sorted(SECURITY_CRITICAL.items()):
        if pkg in ALLOWED_CARET or pkg in local_forks():
            continue
        if pkg not in direct:
            check(False, f'{pkg} fehlt in pubspec (Sicherheitsliste veraltet)')
            print(f'   FEHLT   {pkg}')
            continue
        if direct[pkg].startswith('^'):
            unpinned.append(pkg)
            print(f'   OFFEN   {pkg:32s} {direct[pkg]}')
        else:
            locked = locked_version(pkg)
            same = (locked == direct[pkg])
            check(same, f'{pkg} ist auf die ausgelieferte Version gepinnt',
                  direct[pkg] if same else f'pubspec {direct[pkg]} vs Lock {locked}')
            print(f'   {"OK     " if same else "DRIFT  "}{pkg:32s} {direct[pkg]}')
    check(not unpinned, f'alle sicherheitsrelevanten Pakete gepinnt ({len(unpinned)} offen)')

    print('\n3) Ausnahmen (bewusst nicht gepinnt)')
    for pkg, why in sorted(ALLOWED_CARET.items()):
        present = pkg in direct
        check(present, f'Ausnahme "{pkg}" existiert und ist begründet',
              '' if present else 'nicht in pubspec')
        print(f'   {"OK     " if present else "FEHLT  "}{pkg:32s} {why[:56]}')

    print('\n4) Lokale Forks - für pub outdated blind, manuell zu führen')
    for pkg, path in sorted(local_forks().items()):
        exists = (ROOT / path.replace('/', '\\')).exists() or (ROOT / path).exists()
        check(exists, f'Fork "{pkg}" zeigt auf existierenden Pfad', path)
        print(f'   {"OK     " if exists else "FEHLT  "}{pkg:32s} {path}')

    if '--lock' in sys.argv:
        print('\n5) pubspec.lock-Konsistenz')
        drift = []
        for pkg, cons in direct.items():
            if pkg in SDK_PACKAGES:
                continue
            locked = locked_version(pkg)
            if not locked:
                continue
            if cons.startswith('^'):
                want = cons[1:]
                # nur echte Bruchstellen zaehlen, keine prerelease-Sonderfaelle
                if want.split('.')[0] != locked.split('.')[0]:
                    drift.append((pkg, cons, locked))
            elif locked != cons:
                drift.append((pkg, cons, locked))
        check(not drift, 'Lock passt zu allen Constraints', f'{len(drift)} Abweichungen')
        for pkg, cons, locked in drift:
            print(f'   {pkg}: pubspec {cons} -> Lock {locked}')

    print('\n' + '=' * 76)
    ok = sum(1 for r in results if r[0])
    for passed, label, detail in results:
        if not passed or detail:
            print(f'  {"OK  " if passed else "FEHLT"} {label}'
                  + (f'  [{detail}]' if detail else ''))
    print('=' * 76)
    print(f'{ok}/{len(results)} Prüfungen bestanden')
    return 0 if ok == len(results) else 1


if __name__ == '__main__':
    sys.exit(main())
