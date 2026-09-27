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

    # Universelle APKs bauen (ohne --split-per-abi). Mit
    # -SplitPerAbi kombinierbar: Flutter liefert bei --split-per-abi
    # NUR Splits, fuer den vollstaendigen Satz braucht es zwei
    # Durchlaeufe - das Skript erledigt beides in einem Lauf.
    [switch]$UniversalApk,
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

# ---------------------------------------------------------------------
# Konfiguration als --dart-define injizieren (Security 2026-09-26)
# ---------------------------------------------------------------------
# Hintergrund: `.env` ist KEIN App-Asset mehr. Eine gebuendelte
# Konfigurationsdatei liegt extrahierbar im APK/IPA. Die Werte werden
# hier beim Bauen aus der lokalen `.env` gelesen und als Defines
# uebergeben - das Ergebnis ist identisch im Build, aber nichts davon
# liegt als Datei im Bundle.
#
# `.env` fehlt -> harter Fehler statt "Bot-Schutz stillschweigend aus".
$EnvFile = Join-Path (Get-Location) ".env"
$ConfigDefines = @()
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($line in Get-Content -LiteralPath $EnvFile -Encoding UTF8) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim('"').Trim("'")
            # Nur die vier oeffentlichen Konfigurationswerte - KEINE Secrets.
            if ($key -in @("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY",
                           "CAPTCHA_PROVIDER", "CAPTCHA_SITEKEY")) {
                $ConfigDefines += "--dart-define=$key=$val"
            }
        }
    }
}
# Kein Release ohne Instanz-URL: sonst baut die App "unkonfiguriert" aus und
# scheitert spaeter zur Laufzeit statt beim Build.
if (-not ($ConfigDefines | Where-Object { $_ -like "--dart-define=SUPABASE_URL=*" })) {
  Write-Warning "Keine SUPABASE_URL in .env gefunden."
  throw "Keine SUPABASE_URL in .env gefunden. Der Release-Build bricht bewusst ab, damit nicht unkonfiguriert ausgeliefert wird."
}

# SECURITY: Ein Build ohne CAPTCHA-Sitekey liefert captchaEnabled == false,
# also ein Release ganz ohne Bot-Schutz. Das war bisher still (CI, fremder
# Rechner). Deshalb Abbruch - ABER nur, wenn laut Konfiguration ueberhaupt
# Bot-Schutz gewollt ist. `CAPTCHA_PROVIDER=none` ist der dokumentierte
# Ausweg (z. B. F-Droid-Build) und darf nicht blockiert werden.
$captchaProvider = "turnstile"
$pd = $ConfigDefines | Where-Object { $_ -like "--dart-define=CAPTCHA_PROVIDER=*" } | Select-Object -First 1
if ($pd) { $captchaProvider = $pd -replace "^--dart-define=CAPTCHA_PROVIDER=", "" }
if ($captchaProvider -ne "none" -and
    -not ($ConfigDefines | Where-Object { $_ -like "--dart-define=CAPTCHA_SITEKEY=*" })) {
  Write-Warning "CAPTCHA_SITEKEY fehlt in .env, CAPTCHA_PROVIDER=$captchaProvider - der Bot-Schutz waere im Build AUS (captchaEnabled == false). Abbruch."
  throw "CAPTCHA_SITEKEY fehlt in .env bei CAPTCHA_PROVIDER=$captchaProvider - refusing to build without bot protection. Zum bewussten Abschalten: CAPTCHA_PROVIDER=none in .env setzen."
}
if ($captchaProvider -eq "none") {
  Write-Warning "CAPTCHA_PROVIDER=none - dieser Build hat bewusst KEINEN Bot-Schutz."
}
Write-Host "    Config: $($ConfigDefines.Count) Defines aus .env (nicht gebuendelt)"

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

function Copy-Aab {
    param([string]$FlavorName)
    # Ab Flutter 3.35 mit Product Flavors: outputs/bundle/<flavor>Release/
    # Aelter ohne Flavor: outputs/bundle/release/
    $candidates = @(
        (Join-Path "build\app\outputs\bundle" "$FlavorName`Release\app-$FlavorName-release.aab"),
        (Join-Path "build\app\outputs\bundle\release" "app-$FlavorName-release.aab")
    )
    $src = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $src = $c; break }
    }
    if ($null -eq $src) {
        # Letzte Chance: suchen, statt still zu scheitern
        $found = Get-ChildItem -Path "build\app\outputs\bundle" -Recurse -Filter "app-$FlavorName-release.aab" -ErrorAction SilentlyContinue
        if ($found) { $src = $found[0].FullName }
    }
    if ($null -eq $src) {
        throw "AAB nicht gefunden. Gesucht: $($candidates -join " | ") - Bau fehlgeschlagen?"
    }
    $dst = Join-Path $OutDir "Thestia-v$VersionName-$FlavorName.aab"
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "    OK: $dst" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# Bauen
#
# Reihenfolge ist wichtig: Flutter leert build/app/outputs bei jedem
# Aufruf. Deshalb wird nach JEDEM Bau sofort kopiert, sonst fehlen die
# zuvor gebauten Artefakte.
# ---------------------------------------------------------------------
if ($SkipBuild) {
    Write-Host "==> -SkipBuild: verwende vorhandene APKs." -ForegroundColor Yellow
} else {
    # --- 1) Universelle APKs (zuerst, danach sind sie weg) ---
    if ($UniversalApk -and $Flavor -in @("both", "play")) {
        Write-Host "==> Baue PLAY universal..." -ForegroundColor Cyan
        flutter build apk --release --flavor play @ConfigDefines --obfuscate --split-debug-info=build/symbols/play
        if ($LASTEXITCODE -ne 0) { throw "Play-Build fehlgeschlagen." }
        Copy-FlavorApk -FlavorName "play"
    }
    if ($UniversalApk -and $Flavor -in @("both", "fdroid")) {
        Write-Host "==> Baue F-DROID universal..." -ForegroundColor Cyan
        flutter build apk --release --flavor fdroid --dart-define=FDROID=true @ConfigDefines --obfuscate --split-debug-info=build/symbols/fdroid
        if ($LASTEXITCODE -ne 0) { throw "F-Droid-Build fehlgeschlagen." }
        Copy-FlavorApk -FlavorName "fdroid"
    }

    # --- 2) Pro-ABI-APKs (deutlich kleinere Downloads) ---
    if ($SplitPerAbi -and $Flavor -in @("both", "play")) {
        Write-Host "==> Baue PLAY pro ABI..." -ForegroundColor Cyan
        flutter build apk --release --flavor play @ConfigDefines --split-per-abi --obfuscate --split-debug-info=build/symbols/play
        if ($LASTEXITCODE -ne 0) { throw "Play-Split-Build fehlgeschlagen." }
        Copy-SplitApks -FlavorName "play"
    }
    if ($SplitPerAbi -and $Flavor -in @("both", "fdroid")) {
        Write-Host "==> Baue F-DROID pro ABI..." -ForegroundColor Cyan
        flutter build apk --release --flavor fdroid --dart-define=FDROID=true @ConfigDefines --split-per-abi --obfuscate --split-debug-info=build/symbols/fdroid
        if ($LASTEXITCODE -ne 0) { throw "F-Droid-Split-Build fehlgeschlagen." }
        Copy-SplitApks -FlavorName "fdroid"
    }

    # --- 3) Play-App-Bundle (Pflichtformat fuer den Store) ---
    if ($Aab -and $Flavor -in @("both", "play")) {
        Write-Host "==> Baue Play App-Bundle (.aab)..." -ForegroundColor Cyan
        flutter build appbundle --release --flavor play @ConfigDefines --obfuscate --split-debug-info=build/symbols/play
        if ($LASTEXITCODE -ne 0) { throw "App-Bundle-Build fehlgeschlagen." }
        Copy-Aab -FlavorName "play"
    }

    if ($AdminUUID -ne "") {
        $adminDir = Join-Path $OutDir "admin"
        New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
        foreach ($adminFlavor in @("play", "fdroid")) {
            Write-Host "==> Baue ADMIN-Variante ($adminFlavor, nur Team-intern)..." -ForegroundColor Magenta
            $defineArgs = @("--dart-define=ADMIN_UUID=$AdminUUID") + $ConfigDefines
            if ($adminFlavor -eq "fdroid") { $defineArgs += "--dart-define=FDROID=true" }
            flutter build apk --release --flavor $adminFlavor @defineArgs --obfuscate --split-debug-info=build/symbols/$adminFlavor
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
#
# Nur bei -SkipBuild: im normalen Lauf wurde oben direkt nach jedem
# Build kopiert (Flutter leert das Output-Verzeichnis pro Aufruf).
# ---------------------------------------------------------------------
if ($SkipBuild) {
    if ($UniversalApk -or (-not $SplitPerAbi)) {
        if ($Flavor -in @("both", "play")) { Copy-FlavorApk -FlavorName "play" }
        if ($Flavor -in @("both", "fdroid")) { Copy-FlavorApk -FlavorName "fdroid" }
    }
    if ($SplitPerAbi) {
        if ($Flavor -in @("both", "play")) { Copy-SplitApks -FlavorName "play" }
        if ($Flavor -in @("both", "fdroid")) { Copy-SplitApks -FlavorName "fdroid" }
    }
    if ($Aab -and $Flavor -in @("both", "play")) { Copy-Aab -FlavorName "play" }
}

Write-Host ""
Write-Host "==> Fertig: v$VersionName liegt unter $OutDir" -ForegroundColor Cyan
Write-Host "    Hinweis: Vor dem Verteilen DB-Migrationen (123-130) und" 
Write-Host "    Edge Functions deployen + CAPTCHA im Dashboard aktivieren."
