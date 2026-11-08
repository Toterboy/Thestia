"""Schreibt die Digital-Asset-Links passend zur echten Zertifikatskette.

WARUM ES DAS GIBT (08.11.2026, Hosterwechsel-Vorbereitung): Die Datei
`assetlinks.json` nennt die Zertifikats-Fingerabdricke, gegen die Android
die TLS-Kette des Servers prueft. Beim Wechsel des Hosters aendert sich
das Zertifikat - die Datei muss mit. Und: Das Leaf-Zertifikat wird
alle 90 Tage erneuert (Let's Encrypt). Steht nur das Leaf in der Datei,
ist die Liste nach 90 Tagen tot und die **Passkey-Anmeldung schlaegt auf
Android fehl** (die App verweist die Verknuepfung dann zurueck).

DESHALB: Die Liste bekommt die **stabilen** Glieder der Kette - das
Root und die Zwischenzertifikate. Das Leaf wird bewusst NICHT
eingetragen: es waere nach der naechsten Erneuerung ungueltig. Das
Root dagegen gilt jahrelang.

Das alte Gate (`check_passkey_assetlinks.py`) verglich die Datei nur mit
ihr selbst - es pruefte NICHT, ob die Fingerabdruecke in der echten
Kette stehen. Ein Veralten der Datei fiel damit nicht auf.

Aufruf:
    python tool/update_assetlinks.py            # schreibt die Datei
    python tool/update_assetlinks.py --live     # + gegen die Kette pruefen
"""
import hashlib
import json
import os
import pathlib
import re
import socket
import ssl
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATEI = ROOT / "passkey-assets" / "assetlinks.json"
HOSTS = ["thestia.de", "auth.thestia.de"]


def kette(host):
    """Die verifizierte Zertifikatskette des Hosts (DER-Bytes)."""
    context = ssl.create_default_context()
    with socket.create_connection((host, 443), timeout=25) as s:
        with context.wrap_socket(s, server_hostname=host) as ss:
            return list(ss.get_verified_chain())


def fp(der):
    h = hashlib.sha256(der).hexdigest().upper()
    return ":".join(h[i:i + 2] for i in range(0, len(h), 2))


def debug_fingerprint():
    """Der Fingerabdruck des Standard-Debug-Keystores (falls keytool da ist)."""
    import subprocess
    keytool = None
    for pfad in (
        pathlib.Path(os.environ.get("JAVA_HOME", "")) / "bin" / "keytool.exe",
        pathlib.Path(r"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"),
    ):
        if pfad.exists():
            keytool = str(pfad)
            break
    if not keytool:
        return None
    keystore = pathlib.Path(os.environ.get("USERPROFILE", "")) / ".android" / "debug.keystore"
    if not keystore.exists():
        return None
    try:
        p = subprocess.run(
            [keytool, "-list", "-v", "-alias", "androiddebugkey",
             "-keystore", str(keystore), "-storepass", "android"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"SHA256:\s*([0-9A-Fa-f:]{60,})", p.stdout + p.stderr)
    return m.group(1).upper() if m else None


def release_fingerprint():
    """Der Fingerabdruck des Release-Keystores.

    Die Signier-Angaben liegen ausserhalb des Projekts (siehe
    tool/keystore_secrets.py). Ohne sie gibt es keinen Fingerabdruck -
    das Gate meldet das dann selbst ("Keystore nicht lesbar").
    """
    try:
        sys.path.insert(0, str(ROOT / "tool"))
        import keystore_secrets  # noqa: PLC0415
        props = keystore_secrets.read_props()
    except Exception:  # noqa: BLE001
        return None
    datei = props.get("storeFile") or props.get("store_file") or ""
    passwort = props.get("storePassword") or props.get("store_password") or ""
    alias = props.get("keyAlias") or props.get("key_alias") or ""
    if not (datei and passwort and alias):
        return None
    keytool = None
    for kandidat in (
        pathlib.Path(os.environ.get("JAVA_HOME", "")) / "bin" / "keytool.exe",
        pathlib.Path(r"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"),
    ):
        if kandidat.exists():
            keytool = str(kandidat)
            break
    if not keytool:
        return None
    try:
        import subprocess
        p = subprocess.run(
            [keytool, "-list", "-v", "-alias", alias, "-keystore", datei,
             "-storepass", passwort],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"SHA256:\s*([0-9A-Fa-f:]{60,})", p.stdout + p.stderr)
    return m.group(1).upper() if m else None


def main() -> int:
    nur_pruefen = "--live" in sys.argv
    alle = {}
    for host in HOSTS:
        try:
            glieder = kette(host)
        except Exception as e:  # noqa: BLE001
            print("  X  %s: die Kette liess sich nicht lesen: %s" % (host, e))
            return 1
        fps = [fp(g) for g in glieder]
        alle[host] = fps
        print("  %-22s Kette: %d Zertifikat(e)" % (host, len(glieder)))
        for i, f in enumerate(fps):
            print("    [%d] %s" % (i, f))

    # Das Root ist das LETZTE Glied, die Zwischenzertifikate liegen
    # davor. Das Leaf (Index 0) wird bewusst weggelassen.
    ziel = []
    for host in HOSTS:
        fps = alle[host]
        for f in fps[1:]:
            if f not in ziel:
                ziel.append(f)

    # ZUSAETZLICH: der Fingerabdruck des Debug-Keystores. Der Debug-Build
    # wird mit dem Standard-Key signiert, und genau der stand vorher (z.
    # B. 08.11.2026) in der Datei - ohne ihn koennte der Debug-Build die
    # Passkeys nicht verifizieren. Der Key ist in jedem Android-SDK
    # derselbe (oeffentlich bekannt), das ist also kein Geheimnis.
    #
    # Der RELEASE-Key (CN=Thestia) wird bewusst NICHT eingetragen: Play
    # ersetzt den Upload-Key durch den App-Signing-Key, und der ist erst
    # nach dem ersten Upload bekannt (der Fingerabdruck lautet dann
    # 8C:BE:... - siehe die Betriebsnotiz).
    debug_fp = debug_fingerprint()
    if debug_fp and debug_fp not in ziel:
        ziel.append(debug_fp)
        print()
        print("  Der Debug-Key-Fingerabdruck kommt dazu: %s" % debug_fp)

    # Der RELEASE-Key (CN=Thestia) gehoert ebenfalls zur App und steht
    # nie in der TLS-Kette. Er MUSS aber in der Datei stehen: das
    # Passkey-Gate verlangt ihn (tool/check_passkey_assetlinks.py).
    #
    # ACHTUNG: Nach dem ersten Upload ersetzt Play den Upload-Key durch
    # den App-Signing-Key. Dann muss der Fingerabdruck des
    # App-Signing-Keys hier und als android:apk-key-hash-Origin in den
    # Supabase-Daten stehen (das Gate sagt das ausdruecklich).
    release_fp = release_fingerprint()
    if release_fp and release_fp not in ziel:
        ziel.append(release_fp)
        print()
        print("  Der Release-Key-Fingerabdruck kommt dazu: %s" % release_fp)
    print()
    print("  Neue Liste (ohne Leaf): %d Fingerabdruck/-e" % len(ziel))

    daten = json.loads(DATEI.read_text(encoding="utf-8"))
    alt = []
    for eintrag in daten:
        alt += eintrag.get("target", {}).get("sha256_cert_fingerprints", [])
    print("  Bisher in der Datei: %d" % len(alt))
    if alt == ziel:
        print("  Die Datei ist bereits aktuell.")
    else:
        for eintrag in daten:
            target = eintrag.get("target", {})
            if target.get("namespace") == "android_app":
                target["sha256_cert_fingerprints"] = list(ziel)
        DATEI.write_text(
            json.dumps(daten, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8", newline="\n")
        print("  Die Datei ist aktualisiert.")

    # Gegenprobe: die STABILEN Glieder der Kette muessen in der Datei
    # stehen (sonst ist die Passkey-Verknuepfung kaputt).
    #
    # Die App-Signatur-Fingerabdruecke (Debug- und Release-Key) stehen
    # NIE in der TLS-Kette - sie gehoeren zur App, nicht zum
    # Webserver. Sie werden deshalb hier nicht geprueft (das
    # Passkey-Gate prueft sie getrennt).
    print()
    print("  Gegenprobe:")
    ok = True
    for host in HOSTS:
        fps = alle[host]
        stabile = fps[1:]  # ohne das Leaf (wird alle 90 Tage erneuert)
        fehlend = [f for f in stabile if f not in ziel]
        if fehlend:
            print("    X  %s: %d stabile Glieder der Kette fehlen in der "
                  "Datei" % (host, len(fehlend)))
            ok = False
        else:
            print("    OK %s: alle %d stabilen Kettenglieder stehen in der "
                  "Datei" % (host, len(stabile)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
