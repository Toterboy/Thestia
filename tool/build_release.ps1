# tool/build_release.ps1
#
# Baut die Release-APKs fuer Thestia korrekt (mit Product Flavors!)
# und legt sie benannt unter releases/<version>/ ab.
#
# HINTERGRUND: Das Projekt definiert zwei Product Flavors ("play" und
# "fdroid", siehe android/app/build.gradle.kts). Der nackte Befehl
#   flutter build apk --release
# kann deshalb KEINE APK zuordnen ("Gradle build failed to produce an
# .apk file"). Immer dieses Skript nutzen bzw. manuell:
#   flutter build apk --release --flavor play
#   flutter build apk --release --flavor fdroid --dart-define=FDROID=true
#
# Verwendung:
#   .\tool\build_release.ps1                  # baut beide Varianten + kopiert
#   .\tool\build_release.ps1 -Flavor play     # nur Play-Variante
#   .\tool\build_release.ps1 -SkipBuild       # nur kopieren/umbenennen
#   .\tool\build_release.ps1 -SplitPerAbi     # pro-CPU-APKs (~55 MB statt 156 MB)
#   .\tool\build_release.ps1 -Aab             # zusätzlich Play-App-Bundle (.aab)
#   .\tool\build_release.ps1 -AdminUUID <uuid> # Team-Admin-Builds nach releases/<version>/admin/
#                                             # (NICHT zur Verteilung; UUID = ADMIN_UUID-Secret)
#
# APK-GRÖSSE (Hintergrund): Ein universelles APK enthält die nativen
# Bibliotheken (Flutter-Engine, WebRTC, ONNX Runtime) DREIMAL - für
# arme64, armv7 und x86_64. Jede Kopie ist ~45 MB. Mit --split-per-abi
# entstehen drei getrennte APKs (~55 MB pro Gerät); der Play Store
# liefert automatisch nur die passende. Für Play-Uploads besser gleich
# -Aab nutzen (das .aab ist das pflichtige Store-Format).
#
# Die Version wird automatisch aus pubspec.yaml gelesen (z. B. 0.7.0+4).

param(
    [ValidateSet("both", "play", "fdroid")]
    [string]$Flavor = "both",

    # Überspringt das Kompilieren (nutzt vorhandene APKs unter
    # build/app/outputs/flutter-apk/) - z. B. nach einem Version-Bump.
    [switch]$SkipBuild,

    # Pro-CPU-APKs bauen (arme64-v8a, armeabi-v7a, x86_64) - deutlich
    # kleinere Downloads als das universelle APK.
    [switch]$SplitPerAbi,

    # Zusätzlich ein Play-App-Bundle (.aab) bauen (pflichtiges
    # Store-Format; Play liefert pro Gerät nur die nötigen ABIs aus).
    [switch]$Aab,

    # Admin-UUID (entspricht dem ADMIN_UUID-Secret der admin-ban-Function):
    # Baut play+fdroid als universelle APKs mit --dart-define=ADMIN_UUID=...
    # nach "<OutDir>/admin/" (Team-intern, NICHT verteilen).
    [string]$AdminUUID = "",

    [string]$OutRoot = "releases"
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

# ---------------------------------------------------------------------
# Version aus pubspec.yaml lesen (version: <name>+<build>)
# ---------------------------------------------------------------------
$pubspecLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*(.+)\+(.+)"
if (-not $pubspecLine) {
    throw "Konnte 'version:' in pubspec.yaml nicht finden."
}
$VersionName = $pubspecLine.Matches[0].Groups[1].Value.Trim()
$VersionCode = $pubspecLine.Matches[0].Groups[2].Value.Trim()
$OutDir = Join-Path $OutRoot "v$VersionName"

Write-Host "==> Thestia v$VersionName (build $VersionCode)" -ForegroundColor Cyan
Write-Host "    Ziel: $OutDir"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Copy-FlavorApk {
    param([string]$FlavorName)
    $src = Join-Path "build\app\outputs\flutter-apk" "app-$FlavorName-release.apk"
    if (-not (Test-Path -LiteralPath $src)) {
        throw "APK nicht gefunden: $src - Bitte zuerst bauen (ohne -SkipBuild)."
    }
    $dst = Join-Path $OutDir "Thestia-v$VersionName-$FlavorName.apk"
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "    OK: $dst" -ForegroundColor Green
}

function Copy-SplitApks {
    param([string]$FlavorName)
    $dir = "build\app\outputs\flutter-apk"
    $abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
    $short = @{ "arm64-v8a" = "arm64"; "armeabi-v7a" = "armv7"; "x86_64" = "x86_64" }
    foreach ($abi in $abis) {
        # Flutter benennt Splits app-<abi>-<flavor>-release.apk (Fix 21.09.2026,
        # vorher wurde app-<flavor>-<abi>-release.apk erwartet und nichts kopiert).
        $src = Join-Path $dir "app-$abi-$FlavorName-release.apk"
        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $OutDir "Thestia-v$VersionName-$FlavorName-$($short[$abi]).apk"
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "    OK: $dst" -ForegroundColor Green
        } else {
            Write-Warning "Split-APK nicht gefunden: $src"
        }
    }
}

# ---------------------------------------------------------------------
# Bauen
# ---------------------------------------------------------------------
if ($SkipBuild) {
    Write-Host "==> -SkipBuild: verwende vorhandene APKs." -ForegroundColor Yellow
} else {
    if ($Flavor -in @("both", "play")) {
        Write-Host "==> Baue PLAY-Variante..." -ForegroundColor Cyan
        $abiArgs = @()
        if ($SplitPerAbi) { $abiArgs += "--split-per-abi" }
        # Dart-Obfuskierung (v0.9.0, Manipulationsschutz): Symbol-Namen
        # werden unlesbar gemacht; Debug-Symbole landen in build/symbols/
        # (git-ignoriert) für spätere Crash-Analyse.
        flutter build apk --release --flavor play @abiArgs --obfuscate --split-debug-info=build/symbols/play
        if ($LASTEXITCODE -ne 0) { throw "Play-Build fehlgeschlagen." }
    }
    if ($Flavor -in @("both", "fdroid")) {
        Write-Host "==> Baue F-DROID-Variante (ohne Google/Firebase)..." -ForegroundColor Cyan
        $abiArgs = @()
        if ($SplitPerAbi) { $abiArgs += "--split-per-abi" }
        flutter build apk --release --flavor fdroid --dart-define=FDROID=true @abiArgs --obfuscate --split-debug-info=build/symbols/fdroid
        if ($LASTEXITCODE -ne 0) { throw "F-Droid-Build fehlgeschlagen." }
    }
    if ($AdminUUID -ne "") {
        $adminDir = Join-Path $OutDir "admin"
        New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
        foreach ($adminFlavor in @("play", "fdroid")) {
            Write-Host "==> Baue ADMIN-Variante ($adminFlavor, nur Team-intern)..." -ForegroundColor Magenta
            $defineArgs = @("--dart-define=ADMIN_UUID=$AdminUUID")
            if ($adminFlavor -eq "fdroid") { $defineArgs += "--dart-define=FDROID=true" }
            flutter build apk --release --flavor $adminFlavor @defineArgs --obfuscate --split-debug-info=build/symbols/admin-$adminFlavor
            if ($LASTEXITCODE -ne 0) { throw "Admin-Build ($adminFlavor) fehlgeschlagen." }
            $src = Join-Path "build\app\outputs\flutter-apk" "app-$adminFlavor-release.apk"
            $dst = Join-Path $adminDir "Thestia-v$VersionName-$adminFlavor-ADMIN.apk"
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "    OK: $dst" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------
# Kopieren & Benennen
# ---------------------------------------------------------------------
if ($SplitPerAbi) {
    if ($Flavor -in @("both", "play")) { Copy-SplitApks -FlavorName "play" }
    if ($Flavor -in @("both", "fdroid")) { Copy-SplitApks -FlavorName "fdroid" }
} else {
    if ($Flavor -in @("both", "play")) { Copy-FlavorApk -FlavorName "play" }
    if ($Flavor -in @("both", "fdroid")) { Copy-FlavorApk -FlavorName "fdroid" }
}

Write-Host ""
Write-Host "==> Fertig: v$VersionName liegt unter $OutDir" -ForegroundColor Cyan
Write-Host "    Hinweis: Vor dem Verteilen DB-Migrationen (056-062) und" 
Write-Host "    Edge Functions deployen + CAPTCHA im Dashboard aktivieren."
