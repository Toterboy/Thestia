# Build-Dokumentation (reproduzierbare Release-Builds)

Ziel: Jede Person kann aus diesem Quellstand **denselben** APK-Bau erzeugen
und verifizieren, dass eine veröffentlichte Datei wirklich zu diesem Code
gehört.

## Voraussetzungen

| Werkzeug | Version |
| --- | --- |
| Flutter SDK | **3.44.6** (stable) – die Version, die `.github/workflows/ci.yml` pinnt und mit der gebaut wurde. `pubspec.yaml` nennt `flutter: ^3.35.0`; das ist das **Minimum**, nicht die getestete Version |
| Java / JDK | 17 (Temurin empfohlen) |
| Android SDK | Platform 37 + Build-Tools (via `flutter doctor` prüfen) |

Konfiguration:

```bash
cp .env.example .env          # SUPABASE_URL/PUBLISHABLE_KEY eintragen
# android/key.properties (Release-Signing) – wird NICHT im Repo liegen;
# ohne diese Datei bricht der Release-Build absichtlich fehl.
```

## Release-Build

**Immer über das Skript.** Nicht über direkte `flutter build`-Aufrufe:

```powershell
# öffentliche Artefakte
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_release.ps1 `
  -Flavor both -UniversalApk -SplitPerAbi -Aab

# Admin-Builds: Geheimnis als Umgebungsvariable, NICHT als Parameter.
# Ein Parameter landet im Klartext in der PowerShell-History und in der
# Prozessliste.
$env:ADMIN_UUID = "<uuid>"
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_release.ps1 `
  -Flavor both -UniversalApk
Remove-Item Env:\ADMIN_UUID
```

Warum das Skript und nicht `flutter build` direkt: der Admin- und der
Universal-Build schreiben auf **denselben** Gradle-Pfad. Wer sie direkt
aufruft, kann einen Admin-Build im öffentlichen Ablageort hinterlassen -
genau das ist bei v0.9.1 passiert (siehe
[ADMIN-UUID.md](ADMIN-UUID.md)). Das Skript verhindert das dreifach:
Admin-Baum wird danach restlos gelöscht, jede öffentliche Kopie prüft
die Herkunft der Datei, und `build/.admin-artifacts.json` vermerkt
jedes Admin-Artefakt als Herkunftsnachweis.

Was das Skript tut, falls du es nachvollziehen willst:

```bash
flutter build apk --release --flavor play --dart-define=FDROID=false
flutter build apk --release --flavor fdroid --dart-define=FDROID=true
```

**Wichtig:** Seit es die Flavors gibt, ist ein Build **ohne** `--flavor`
nicht mehr möglich — Flutter findet die APK sonst nicht (Fehler
„failed to produce an .apk file"). Immer `--flavor play` oder
`--flavor fdroid` angeben. In IntelliJ liegen fertige Run-Konfigurationen
bereit: **„Thestia (play)"** und **„Thestia (fdroid)"** (Dropdown
oben in der Toolbar).

Der `FDROID`-Define schaltet Firebase/FCM im Dart-Code komplett ab
(`constants.fdroidBuild`); die fdroid-Variante MUSS damit gebaut werden,
sonst versucht sie trotzdem, Firebase zu initialisieren (wird zwar
abgefangen, sauber ist der Define).

Ergebnis: `build/app/outputs/flutter-apk/app-<flavor>-release.apk`

**Prüfen vor dem Verteilen** - der Check läuft ohne Geheimnis und findet
eine Kontamination auch dann, wenn niemand die UUID kennt:

```powershell
python tool\check_release_artifacts.py
```

**Dart-Obfuskierung (v0.9.0)**: Release-Builds laufen mit
`--obfuscate --split-debug-info=build/symbols/<flavor>` (im Skript
bereits drin). Admin-Builds bekommen `build/symbols/admin-<flavor>` -
ein eigener Ordner, weil beide sonst dieselben Symbole überschreiben
und die Crash-Analyse des öffentlichen Releases gegen die falschen
Stacks läuft. Die Symbole unter `build/symbols/` (git-ignoriert)
für die Crash-Analyse aufheben – ohne sie sind Release-Stacktraces
nicht deobfuskierbar. R8/Java-Minify ist bewusst AUS (Plugin-
Kompatibilität); der Schutz kommt aus Dart-Obfuskierung + serverseitigen
Checks, nicht aus Java-Verschleierung.

Determinismus-Hinweise:

- Gleicher Flutter-Commit + gleiche `pubspec.lock` + gleicher Gradle-Wrapper
  ⇒ identische APK-Bytes (abgesehen von der Signatur).
- Keine Zeitstempel/Eingaben im Build-Pfad verwenden; Build in einem
  frischen Clone starten.
- Gleiche `--dart-define`-Werte auf beiden Seiten verwenden.

## Verifikation

```bash
# Zertifikat des APKs prüfen (muss dem Upload-Keystore entsprechen):
$ANDROID_HOME/build-tools/37.0.0/apksigner verify --print-certs app-play-release.apk

# Prüfsumme vergleichen mit einer zweiten, unabhängig erstellten Kopie:
sha256sum app-*-release.apk
```

Der SHA-256-Fingerprint des Upload-Zertifikats ist öffentlich in
`passkey-assets/assetlinks.json` hinterlegt und muss zur APK passen.

## Varianten (Flavors)

| Flavor | Firebase/FCM | Zweck |
| --- | --- | --- |
| `play` | ✅ | Standard (auch für `flutter run` ohne Flavor, siehe `missingDimensionStrategy`) |
| `fdroid` | ❌ Plugin wird nicht angewendet | F-Droid-konform; Push später via UnifiedPush |

Dart-seitig initialisiert Firebase defensiv mit try/catch – auf `fdroid`
schlägt das fehl und wird still übersprungen (Push dann ohne Hintergrund-
Benachrichtigungen bis UnifiedPush umgesetzt ist).

## F-Droid Status

Siehe [FDROID.md](FDROID.md) für den konkreten Blocker-Checklistenstand.
