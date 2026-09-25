# Build-Dokumentation (reproduzierbare Release-Builds)

Ziel: Jede Person kann aus diesem Quellstand **denselben** APK-Bau erzeugen
und verifizieren, dass eine veröffentlichte Datei wirklich zu diesem Code
gehört.

## Voraussetzungen

| Werkzeug | Version |
| --- | --- |
| Flutter SDK | 3.35.x (stable) – exakt die Version aus `pubspec.yaml` (`environment.flutter`) |
| Java / JDK | 17 (Temurin empfohlen) |
| Android SDK | Platform 37 + Build-Tools (via `flutter doctor` prüfen) |

Konfiguration:

```bash
cp .env.example .env          # SUPABASE_URL/PUBLISHABLE_KEY eintragen
# android/key.properties (Release-Signing) – wird NICHT im Repo liegen;
# ohne diese Datei bricht der Release-Build absichtlich fehl.
```

## Release-Build

```bash
flutter build apk --release --flavor play --dart-define=FDROID=false
flutter build apk --release --flavor fdroid --dart-define=FDROID=true
```

**Alle Release-Varianten per Skript** (empfohlen): 
`tool/build_release.ps1` baut die Standard-APKs, optional per
`-SplitPerAbi` (pro-CPU-APKs, arm64/armv7 – deutlich kleiner) und
`-Aab` (Play-App-Bundle) sowie mit `-AdminUUID <uuid>` Admin-Builds
(`--dart-define=ADMIN_UUID=…`, nur für das Team, nicht zur Verteilung).

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

**Dart-Obfuskierung (v0.9.0)**: Release-Builds laufen mit
`--obfuscate --split-debug-info=build/symbols/<flavor>` (im Skript
bereits drin). Die Symbole unter `build/symbols/` (git-ignoriert)
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
