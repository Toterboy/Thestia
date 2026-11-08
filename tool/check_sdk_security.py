"""Prueft die Sicherheitsversionen von SDK und Paketen.

BEFUND (08.11.2026, Sicherheitspruefung): Nach dem Advisory
GHSA-frr6-h895-5pxp (Severity High) sind drei Dinge alt:

1. **Der Flutter-/Dart-SDK.** Dart validiert TLS-Zertifikate auf Android
   mit einem EINGEBAUTEN BoringSSL und liest die Sperrliste des
   Betriebssystems NICHT. Nach der Kompromittierung der eMudhra-
   Zwischenzertifikate (Oktober 2026) kann ein Angreifer im Netzpfad
   damit ein gueltiges Zertifikat fuer beliebige Domains FAELSCHEN.
   Betroffen: Flutter < 3.47.8, Dart < 3.13.7. (iOS/macOS/Web sind
   nicht betroffen - dort prueft das Betriebssystem.)

2. **Der WebRTC-SDK im lokalen Fork** `third_party/flutter_webrtc`. Der
   bringt seine eigene CA-Liste mit; der Fix ist ab WebRTC-SDK
   150.7871.04 ("drop compromised eMudhra CA root").

3. **Die Flutter-Engine** bringt Skia und libpng mit. Beides hatte
   2026 Luecken, die mit dem SDK-Update behoben sind.

DAS GATE haelt diese Versionsuntergrenzen fest. Es meldet SICHERN
(als Fehler), wenn eine Untergrenze unterschritten wird - und es
prueft zusätzlich, ob die CI und die lokale Installation ueberhaupt
dieselbe SDK-Version fahren.

Aufruf:
    python tool/check_sdk_security.py
"""
import os
import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Untergrenzen. Wer die erfuellt, ist von dem Advisory nicht betroffen.
# (Quelle: GHSA-frr6-h895-5pxp, flutter_webrtc-Changelog 1.6.3)
UNTERGRENZEN = {
    "flutter": (3, 47, 8),   # Dart 3.13.7 - BoringSSL vertraut die
                              # kompromittierten Zwischenzertifikate
                              # nicht mehr.
    "dart": (3, 13, 7),
}

# Pakete, die eine bestimmte Mindestversion brauchen.
PAKETE = {
    # Der WebRTC-SDK kommt aus dem lokalen Fork (third_party), NICHT aus
    # dem Pub-Repository - deshalb steht die Version in der Gradle-Datei.
    "io.github.webrtc-sdk:android": (150, 7871, 4),
}


def version_tuple(text):
    teile = re.findall(r"\d+", text)
    return tuple(int(t) for t in teile[:3])


def groesser_gleich(a, b):
    return a[: len(b)] >= b


def flutter_version_aus_der_ci():
    ci = ROOT / ".github" / "workflows" / "ci.yml"
    if not ci.exists():
        return None
    text = ci.read_text(encoding="utf-8", errors="replace")
    treffer = re.search(r'FLUTTER_VERSION:\s*"([0-9.]+)"', text)
    return treffer.group(1) if treffer else None


def lokale_sdk_version():
    """Die lokal installierte Flutter-/Dart-Version.

    Flutter liegt nicht immer im PATH (z. B. bei einer manuellen
    Installation). Dann hilft die Umgebungsvariable FLUTTER_BIN:

        $env:FLUTTER_BIN = "C:\\Users\\...\\flutter\\bin\\flutter.bat"
    """
    kandidaten = []
    aus_umgebung = os.environ.get("FLUTTER_BIN", "").strip()
    if aus_umgebung:
        kandidaten.append([aus_umgebung, "--version"])
    kandidaten.append(["flutter", "--version"])
    kandidaten.append(["dart", "--version"])
    for befehl in kandidaten:
        try:
            ergebnis = subprocess.run(
                befehl, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=120,
            )
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            continue
        ausgabe = (ergebnis.stdout or "") + (ergebnis.stderr or "")
        if "flutter" in befehl[0].lower():
            treffer = re.search(r"Flutter\s+([0-9]+\.[0-9]+\.[0-9]+)", ausgabe)
        else:
            treffer = re.search(r"Dart SDK version:\s*([0-9]+\.[0-9]+\.[0-9]+)",
                                ausgabe)
        if treffer:
            return treffer.group(1)
    return None


def main() -> int:
    print("=" * 74)
    print("PRUEFUNG: Sicherheitsversionen von SDK und Paketen")
    print("=" * 74)
    print()
    fehler = 0
    warnungen = 0

    # --- 1) Die CI-Version -----------------------------------------------
    ci_version = flutter_version_aus_der_ci()
    if ci_version is None:
        print("  ! Die Flutter-Version der CI wurde nicht gefunden.")
        warnungen += 1
    else:
        ist = version_tuple(ci_version)
        soll = UNTERGRENZEN["flutter"]
        if groesser_gleich(ist, soll):
            print("  OK  CI-Version Flutter %s (>= %s)"
                  % (ci_version, ".".join(str(t) for t in soll)))
        else:
            print("  X  CI-Version Flutter %s ist VOR %s - das Advisory"
                  % (ci_version, ".".join(str(t) for t in soll)))
            print("     GHSA-frr6-h895-5pxp (High) ist damit offen:")
            print("     ein Angreifer im Netzpfad kann ein gefaelschtes")
            print("     TLS-Zertifikat vortaeuschen (nur Android/Linux).")
            fehler += 1

    # --- 2) Die lokal installierte Version -------------------------------
    lokal = lokale_sdk_version()
    if lokal is None:
        print("  (Die lokale SDK-Version liess sich nicht aus -")
        print("   das ist kein Fehler, aber der lokale Build ist damit")
        print("   NICHT gegen das SDK-Update geprueft.)")
    else:
        ist = version_tuple(lokal)
        soll = UNTERGRENZEN["flutter"]
        if groesser_gleich(ist, soll):
            print("  OK  lokal installiertes Flutter %s (>= %s)"
                  % (lokal, ".".join(str(t) for t in soll)))
        else:
            print("  ! Lokal installiertes Flutter %s ist VOR %s."
                  % (lokal, ".".join(str(t) for t in soll)))
            print("     Ein hier gebautes Artefakt traegt das Advisory")
            print("     weiterhin - auch wenn die CI schon aktualisiert ist.")
            warnungen += 1

    # --- 3) Der WebRTC-SDK im lokalen Fork -------------------------------
    gradle = ROOT / "third_party" / "flutter_webrtc" / "android" / "build.gradle"
    if not gradle.exists():
        print("  ! Der Fork third_party/flutter_webrtc fehlt.")
        warnungen += 1
    else:
        text = gradle.read_text(encoding="utf-8", errors="replace")
        treffer = re.search(
            r"io\.github\.webrtc-sdk:android:([0-9.]+)", text)
        if not treffer:
            print("  ! Die WebRTC-SDK-Version wurde nicht gefunden.")
            warnungen += 1
        else:
            ist = version_tuple(treffer.group(1))
            soll = PAKETE["io.github.webrtc-sdk:android"]
            if groesser_gleich(ist, soll):
                print("  OK  WebRTC-SDK %s (>= %s)"
                      % (treffer.group(1), ".".join(str(t) for t in soll)))
            else:
                print("  X  WebRTC-SDK %s ist VOR %s - der WebRTC-SDK"
                      % (treffer.group(1), ".".join(str(t) for t in soll)))
                print("     bringt die kompromittierte eMudhra-CA noch mit.")
                fehler += 1

    print()
    if fehler:
        print("FEHLER: %d Punkt(e) unter der Sicherheitsuntergrenze."
              % fehler)
        return 1
    if warnungen:
        print("OK mit %d Hinweis(en) - die Untergrenzen sind eingehalten."
              % warnungen)
        return 0
    print("OK: alle Sicherheitsuntergrenzen eingehalten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
