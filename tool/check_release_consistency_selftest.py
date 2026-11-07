"""Selbsttest fuer das Release-Konsistenz-Gate.

WARUM (07.11.2026): Bei diesem Gate sind drei Dinge geaendert worden,
die man nur durch Ausprobieren bemerkt:

  1. Der Release-Ordner folgt jetzt der Version aus pubspec.yaml.
     Vorher stand dort fest 'releases/v0.9.2' - die Abnahme von
     v0.10.0 pruefte die Dateien von v0.9.2.
  2. ACCESS_FINE_LOCATION ist nicht mehr verboten, sondern nur noch
     mit maxSdkVersion=30 erlaubt (Android 11 und aelter brauchen die
     genaue Berechtigung fuer den BLE-Scan).
  3. Das AAB wird jetzt ueberhaupt geprueft - es ist die Datei, die
     in den Play Store geht.

Ein Gate, das man nie rot gesehen hat, ist kein Gate. Dieser
Selbsttest baut deshalb ein synthetisches AAB und prueft, dass der
Leser die richtigen Werte findet und dass die Regeln anschlagen.

Aufruf::

    python tool/check_release_consistency_selftest.py
"""

import io
import os
import pathlib
import sys
import tempfile
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

import check_release_consistency as g  # noqa: E402


# =====================================================================
# Ein minimaler Protobuff-Encoder (genug fuer das Manifest)
# =====================================================================
def varint(wert: int) -> bytes:
    aus = bytearray()
    while True:
        byte = wert & 0x7F
        wert >>= 7
        if wert:
            aus.append(byte | 0x80)
        else:
            aus.append(byte)
            return bytes(aus)


def feld(nummer: int, inhalt: bytes) -> bytes:
    """Feld mit Laenge (Wire-Typ 2)."""
    return varint((nummer << 3) | 2) + varint(len(inhalt)) + inhalt


def text(nummer: int, wert: str) -> bytes:
    return feld(nummer, wert.encode("utf-8"))


def attribute(name: str, wert: str) -> bytes:
    """Ein XmlAttribute: namespace (1), name (2), value (3)."""
    return (text(1, 'http://schemas.android.com/apk/res/android')
            + text(2, name) + text(3, wert))


def element(name: str, attribute_rohdaten: bytes = b'',
            kinder: bytes = b'') -> bytes:
    """Ein XmlElement: name (3), attribute (4), child (5)."""
    return text(3, name) + attribute_rohdaten + kinder


def kind(element_rohdaten: bytes) -> bytes:
    """Ein XmlNode: element (1), source (3)."""
    return feld(1, element_rohdaten) + feld(3, b'\x10\x04')


def manifest_rohdaten(version_code: int, version_name: str,
                      berechtigungen) -> bytes:
    """Baut ein Manifest wie das, was im AAB steht."""
    attribute_rohdaten = (feld(4, text(2, 'package')
                               + text(3, 'com.thestia.app'))
                          + feld(4, attribute('versionCode',
                                              str(version_code)))
                          + feld(4, attribute('versionName', version_name)))
    kinder = b''
    for name, maxsdk in berechtigungen:
        attribute_rohdaten_kind = feld(4, attribute('name', name))
        if maxsdk is not None:
            attribute_rohdaten_kind += feld(4, attribute('maxSdkVersion',
                                                         str(maxsdk)))
        kinder += feld(5, kind(element('uses-permission',
                                      attribute_rohdaten_kind)))
    return feld(1, element('manifest', attribute_rohdaten, kinder))


def schreibe_aab(pfad: pathlib.Path, version_code: int, version_name: str,
                  berechtigungen) -> None:
    with zipfile.ZipFile(pfad, "w") as z:
        z.writestr("BundleConfig.pb", b"\x00")
        z.writestr("base/manifest/AndroidManifest.xml",
                   manifest_rohdaten(version_code, version_name,
                                     berechtigungen))


# =====================================================================
# Die Proben
# =====================================================================
def main() -> int:
    print("=" * 70)
    print("SELBSTTEST: das Release-Konsistenz-Gate")
    print("=" * 70)

    fehlgeschlagen = []

    # --- 1) Der AAB-Leser findet die Werte ---------------------------
    with tempfile.TemporaryDirectory() as tmp:
        aab = pathlib.Path(tmp) / "test.aab"
        schreibe_aab(aab, 38, "0.10.0", [
            ("android.permission.RECORD_AUDIO", None),
            ("android.permission.ACCESS_FINE_LOCATION", 30),
            ("android.permission.READ_EXTERNAL_STORAGE", 32),
        ])
        daten, err = g.dump_aab_manifest(str(aab))
        if daten is None:
            fehlgeschlagen.append("der AAB-Leser kam nicht durch: %s" % err)
            print("  X der AAB-Leser kam nicht durch: %s" % err)
        else:
            erwartet = {
                "versionCode": 38,
                "versionName": "0.10.0",
                "package": "com.thestia.app",
                "permissions": {
                    "android.permission.RECORD_AUDIO": None,
                    "android.permission.ACCESS_FINE_LOCATION": 30,
                    "android.permission.READ_EXTERNAL_STORAGE": 32,
                },
            }
            for schluessel, wert in erwartet.items():
                if daten.get(schluessel) != wert:
                    fehlgeschlagen.append(
                        "%s: gelesen %r, erwartet %r"
                        % (schluessel, daten.get(schluessel), wert))
                    print("  X %s: gelesen %r, erwartet %r"
                          % (schluessel, daten.get(schluessel), wert))
                else:
                    print("  OK %s = %r" % (schluessel, wert))

    # --- 2) Die Berechtigungs-Regeln ----------------------------------
    print()
    print("  Die Berechtigungs-Regeln:")

    # 2a) Der Zustand von v0.10.0 muss durchgehen.
    gut = {
        "android.permission.RECORD_AUDIO": None,
        "android.permission.ACCESS_FINE_LOCATION": 30,
        "android.permission.READ_EXTERNAL_STORAGE": 32,
        "android.permission.WRITE_EXTERNAL_STORAGE": 28,
        "android.permission.BLUETOOTH": 30,
    }
    probleme = g.berechtigungs_probleme(gut)
    if probleme:
        fehlgeschlagen.append("der v0.10.0-Zustand wird abgelehnt: %s"
                              % "; ".join(probleme))
        print("  X der v0.10.0-Zustand wird abgelehnt: %s"
              % "; ".join(probleme))
    else:
        print("  OK der v0.10.0-Zustand wird akzeptiert")

    # 2b) ACCESS_FINE_LOCATION OHNE Obergrenze muss anschlagen -
    #     das ist genau der Fall, den Play moniert.
    ohne = dict(gut)
    ohne["android.permission.ACCESS_FINE_LOCATION"] = None
    probleme = g.berechtigungs_probleme(ohne)
    if not probleme:
        fehlgeschlagen.append("ACCESS_FINE_LOCATION ohne maxSdkVersion "
                              "wird nicht gemeldet")
        print("  X ACCESS_FINE_LOCATION ohne maxSdkVersion wird nicht "
              "gemeldet")
    else:
        print("  OK ACCESS_FINE_LOCATION ohne maxSdkVersion schlaegt an")

    # 2c) Eine falsche Obergrenze muss anschlagen.
    falsch = dict(gut)
    falsch["android.permission.ACCESS_FINE_LOCATION"] = 31
    probleme = g.berechtigungs_probleme(falsch)
    if not probleme:
        fehlgeschlagen.append("ACCESS_FINE_LOCATION mit maxSdkVersion=31 "
                              "wird nicht gemeldet")
        print("  X ACCESS_FINE_LOCATION mit maxSdkVersion=31 wird nicht "
              "gemeldet")
    else:
        print("  OK eine falsche Obergrenze schlaegt an")

    # 2d) Eine verbotene Berechtigung muss anschlagen.
    verboten = dict(gut)
    verboten["android.permission.ACCESS_BACKGROUND_LOCATION"] = None
    probleme = g.berechtigungs_probleme(verboten)
    if not probleme:
        fehlgeschlagen.append("ACCESS_BACKGROUND_LOCATION wird nicht "
                              "gemeldet")
        print("  X ACCESS_BACKGROUND_LOCATION wird nicht gemeldet")
    else:
        print("  OK eine verbotene Berechtigung schlaegt an")

    # --- 3) Der Release-Ordner folgt der Version ----------------------
    print()
    ordner = g.release_dir_aus_pubspec()
    if not ordner:
        fehlgeschlagen.append("der Release-Ordner laesst sich nicht "
                              "aus pubspec.yaml lesen")
        print("  X der Release-Ordner laesst sich nicht aus pubspec.yaml "
              "lesen")
    else:
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        import re
        version = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+",
                            pubspec, re.M).group(1)
        erwartet = os.path.join(str(ROOT), "releases", "v" + version)
        if os.path.normpath(ordner) != os.path.normpath(erwartet):
            fehlgeschlagen.append("der Release-Ordner ist %r, erwartet %r"
                                  % (ordner, erwartet))
            print("  X der Release-Ordner ist %r, erwartet %r"
                  % (ordner, erwartet))
        else:
            print("  OK der Release-Ordner folgt der Version: %s"
                  % os.path.basename(ordner))

    print()
    if fehlgeschlagen:
        print("FEHLER: %d Probe(n) gescheitert:" % len(fehlgeschlagen))
        for f in fehlgeschlagen:
            print("  - %s" % f)
        return 1

    print("OK: alle Proben bestanden - das Gate prueft wirklich.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
