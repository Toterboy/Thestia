#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fuehrt genau die Gates aus, die GitHub Actions ausfuehrt - lokal.

.DESCRIPTION
  WARUM DIESES SKRIPT ES GIBT (04.11.2026):

  Die CI ist drei Laeufe lang (#265, #266, #268) an EINER Zeile rot
  gewesen, obwohl lokal alles gruen war:

      test/web_pages_test.dart:186  unnecessary_brace_in_string_interps

  Der Grund ist ein Unterschied zwischen zwei Aufrufen:

      lokal:  flutter analyze                 -> "No issues found"
      CI:     flutter analyze --fatal-infos   -> Hinweis = Fehler

  Der Hinweis ist ein "info", kein "error". Lokal sieht man ihn in der
  Ausgabe, aber der Exit-Code bleibt 0 - man haelt sich fuer gruen.
  In der CI ist derselbe Hinweis ein Fehler, und der Schritt bricht ab.
  Danach wird der Schritt "Tests" gar nicht mehr ausgefuehrt - ein
  zweiter Fehler dahinter bleibt damit unsichtbar.

  Das Skript nimmt deshalb die Schritte aus .github/workflows/ci.yml
  UND die Flags der CI:

      * analyze:  --fatal-infos   (CI-Flag, nicht das bequemere Default)
      * Tests:    mit .env aus .env.example  (so baut die CI es auf)
      * Pruefer:  python3 -> python  (Windows ohne python3-Alias)

  Es aendert NICHTS am Repository. Es ruft nur die vorhandenen Gates
  auf und sammelt das Ergebnis.

  WENN SICH DIE CI AENDERT, muss dieses Skript mitwachsen. Sonst
  laeuft es zwar gruen durch, prueft aber nicht mehr das, was die CI
  prueft - die schlimmste Sorte von gruen.

.PARAMETER Schnell
  Ueberspringt "flutter test" (dauert lokal rund zwei Minuten). Der
  Analyzer laeuft trotzdem mit --fatal-infos - genau der Schritt, der
  dreimal das Problem war.

.PARAMETER Nur
  Nur die angegebenen Gruppen ausfuehren, z. B. -Nur static-checks.
  Zulaessig: analyze-and-test, dependency-audit, static-checks,
  passkey-assets. Ohne Angabe laufen alle vier.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tool\check_local_ci.ps1 -Schnell

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tool\check_local_ci.ps1 -Nur static-checks,passkey-assets
#>
[CmdletBinding()]
param(
    [switch]$Schnell,
    [string[]]$Nur = @()
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

# Die Gruppenliste normalisieren.
#
# Aufruf per "powershell -File" liefert "-Nur a,b" als EINEN String
# ("a,b") - ohne diese Zerlegung wuerde die Gruppe "a" nie gefunden
# und das Skript pruefte gar nichts (und meldete gruen). Genau die
# Sorte von gruen, die nichts prueft.
$Gruppen = @()
foreach ($roh in $Nur) {
    foreach ($teil in ($roh -split ',')) {
        $t = $teil.Trim()
        if ($t) { $Gruppen += $t }
    }
}

$fehler = New-Object System.Collections.Generic.List[string]
$ergebnisse = New-Object System.Collections.Generic.List[string]

# Die CI ruft "python3" auf. Windows hat oft kein python3-Alias,
# deshalb wird hier auf "python" zurueckgefallen.
$py = 'python'
if (Get-Command python3 -ErrorAction SilentlyContinue) { $py = 'python3' }

function Soll {
    param([string]$Gruppe)
    if ($Gruppen.Count -eq 0) { return $true }
    return $Gruppen -contains $Gruppe
}

function Gate {
    <# Ruft einen Befehl auf und wertet seinen Exit-Code aus. #>
    param(
        [string]$Name,
        [string[]]$Argumente
    )
    Write-Host ''
    Write-Host ('-' * 72) -ForegroundColor DarkGray
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host ('-' * 72) -ForegroundColor DarkGray
    # Der Aufruf kann auch aus genau einem Wort bestehen. Dann darf der
    # Bereich 1..0 nicht gebildet werden - er liefe rueckwaerts und
    # waere ein leerer Array, mit dem "& $cmd @()" zwar harmlos, aber
    # in aelteren PowerShell-Versionen eine Fehlerquelle ist.
    $rest = @()
    if ($Argumente.Count -gt 1) { $rest = @($Argumente[1..($Argumente.Count - 1)]) }
    $out = & $Argumente[0] @rest 2>&1 | Out-String
    $code = $LASTEXITCODE
    $text = $out.TrimEnd()
    if ($text) { Write-Host $text -ForegroundColor DarkGray }
    if ($code -eq 0) {
        Write-Host '  -> OK' -ForegroundColor Green
        $ergebnisse.Add("OK    $Name") | Out-Null
    } else {
        Write-Host "  -> FEHLER (Exit $code)" -ForegroundColor Red
        $fehler.Add($Name) | Out-Null
        $ergebnisse.Add("FEHL  $Name") | Out-Null
    }
}

function Gates {
    <# Ruft mehrere Gates nacheinander auf - stoppt bei der ersten
       Abweichung innerhalb einer Gruppe, macht aber mit der naechsten
       Gruppe weiter. #>
    param(
        [string]$Gruppe,
        [array]$Liste
    )
    foreach ($g in $Liste) {
        $voll = "${Gruppe}: " + $g.Name
        Gate -Name $voll -Argumente $g.Argumente
        if ($fehler.Count -gt 0 -and $fehler[-1] -eq $voll) {
            Write-Host "  (Rest der Gruppe '$Gruppe' uebersprungen)" -ForegroundColor Yellow
            break
        }
    }
}

function G {
    param([string]$Name, [string[]]$Argumente)
    return @{ Name = $Name; Argumente = $Argumente }
}

Write-Host ''
Write-Host '  Lokale CI-Gates (Spiegel von .github/workflows/ci.yml)' -ForegroundColor White
Write-Host "  Repository: $root" -ForegroundColor DarkGray

# ---------------------------------------------------------------------
# 0) Die gepinnten Pruef-Abhaengigkeiten (CI: setup-python + pip install
#    -r tool/requirements.txt). Fehlen sie, brechen die Pruefer mit
#    ImportError ab - nicht mit einem Befund.
# ---------------------------------------------------------------------
$fehlend = @()
foreach ($paket in @('sqlglot', 'pglast', 'PIL')) {
    & $py -c "import $paket" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $fehlend += $paket }
}
if ($fehlend.Count -gt 0) {
    Write-Host ''
    Write-Host "  FEHLENDE Pruef-Abhaengigkeiten: $($fehlend -join ', ')" -ForegroundColor Red
    Write-Host '  -> pip install -r tool/requirements.txt' -ForegroundColor Yellow
    $fehler.Add('Pruef-Abhaengigkeiten') | Out-Null
    $ergebnisse.Add('FEHL  Pruef-Abhaengigkeiten') | Out-Null
} else {
    Write-Host "  Pruef-Abhaengigkeiten: vollstaendig ($py)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# analyze-and-test
# ---------------------------------------------------------------------
if (Soll 'analyze-and-test') {
    Gate -Name 'analyze-and-test: flutter analyze --fatal-infos' `
        -Argumente @('flutter', 'analyze', '--fatal-infos')

    # Die Formatierung wird seit dem 06.11.2026 mitgeprueft. Ohne
    # diesen Schritt laeuft der Code still auseinander - niemand
    # merkt es, bis jemand anderes formatiert.
    #
    # third_party/ ist NICHT dabei: das sind fremde Forks, die bei
    # einem Upstream-Update unveraendert bleiben muessen.
    Gate -Name 'analyze-and-test: dart format (Dart 3.12)' `
        -Argumente @('dart', 'format', '--output=none',
                     '--set-exit-if-changed', 'lib', 'test', 'tool')

    if (-not $Schnell) {
        # Die CI baut die .env aus .env.example auf. Der echte lokale
        # .env kann andere Werte haben - dann laeuft der Test lokal
        # gegen einen anderen Zustand als in der CI.
        $envBak = Join-Path $env:TEMP ('thestia-env-' + [guid]::NewGuid().ToString('N'))
        $hatEnv = Test-Path '.env'
        if ($hatEnv) { Copy-Item '.env' $envBak -Force }
        Copy-Item '.env.example' '.env' -Force
        try {
            Gate -Name 'analyze-and-test: flutter test' -Argumente @('flutter', 'test', '--reporter', 'compact')
        } finally {
            if ($hatEnv) {
                Copy-Item $envBak '.env' -Force
                Remove-Item $envBak -Force -ErrorAction SilentlyContinue
            } else {
                Remove-Item '.env' -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Host ''
        Write-Host '  (flutter test uebersprungen -Schnell)' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------
# dependency-audit
# ---------------------------------------------------------------------
if (Soll 'dependency-audit') {
    Gates 'dependency-audit' @(
        (G 'Pin-Audit (--lock)' @($py, 'tool/check_dependency_pins.py', '--lock'))
        (G 'Security-Invarianten' @($py, 'tool/check_security_invariants.py'))
        (G 'Namespace-Migration' @($py, 'tool/check_namespace_migration.py'))
    )
}

# ---------------------------------------------------------------------
# static-checks (Reihenfolge wie in der CI)
# ---------------------------------------------------------------------
if (Soll 'static-checks') {
    Gates 'static-checks' @(
        (G 'SQL-Parser' @($py, 'tool/check_migrations_sql.py'))
        (G 'SQL-Sicherheit' @($py, 'tool/check_migration_safety.py'))
        (G 'Selbtests der Pruefer' @($py, 'tool/check_migrations_sql_selftest.py'))
        (G 'Selbtests der Pruefer (Pfade)' @($py, 'tool/check_migrations_sql_paths_selftest.py'))
        (G 'Selbtests der Pruefer (Namespace)' @($py, 'tool/check_namespace_migration_selftest.py'))
        (G 'Selbtests der Pruefer (Push-Reife)' @($py, 'tool/check_push_readiness_selftest.py'))
        (G 'Selbtests der Pruefer (Push-Duplikate)' @($py, 'tool/check_push_duplicates_selftest.py'))
        (G 'Selbtests der Pruefer (.gitignore)' @($py, 'tool/check_gitignore_selftest.py'))
        (G 'Selbtests der Pruefer (CI-Spiegel)' @($py, 'tool/check_local_ci_sync_selftest.py'))
        (G 'Web-Theme wiederholbar' @($py, 'tool/check_web_theme_idempotenz.py'))
        (G 'Uebrige statische Pruefer' @($py, 'tool/check_security_invariants.py'))
        (G 'Uebrige statische Pruefer (Pins)' @($py, 'tool/check_dependency_pins.py'))
        (G 'Uebrige statische Pruefer (Push-Reife)' @($py, 'tool/check_push_readiness.py'))
        (G 'Uebrige statische Pruefer (Push-Duplikate)' @($py, 'tool/check_push_duplicates.py'))
        (G 'Uebrige statische Pruefer (SDK-Sicherheit)' @($py, 'tool/check_sdk_security.py'))
        (G 'Uebrige statische Pruefer (app_config lesbar)' @($py, 'tool/check_app_config_readable.py'))
        (G 'Uebrige statische Pruefer (Passkey)' @($py, 'tool/check_passkey_assetlinks.py'))
        (G 'Uebrige statische Pruefer (Gedankenstriche)' @($py, 'tool/check_dashes.py'))
        (G 'Uebrige statische Pruefer (Texte)' @($py, 'tool/check_texts.py'))
        (G 'Uebrige statische Pruefer (Schluessel)' @($py, 'tool/check_keys.py'))
        (G 'Uebrige statische Pruefer (CI-Spiegel)' @($py, 'tool/check_local_ci_sync.py'))
        (G 'Uebrige statische Pruefer (Edge-Syntax)' @($py, 'tool/check_edge_syntax.py'))
        (G 'Publish-Ordner vorbereit' @($py, 'tool/check_publish_folder.py'))
        (G 'Nutzungsbedingungen belegt' @($py, 'tool/check_terms_claims.py'))
        (G 'Website-Seiten pruefen' @($py, 'tool/check_web_pages.py'))
        (G 'Website-Pruefer Selbsttest' @($py, 'tool/check_web_pages_selftest.py'))
        (G 'Keine leeren catch-Bloecke' @($py, 'tool/check_no_empty_catches.py'))
        (G 'mounted nach await' @($py, 'tool/check_async_setstate.py'))
        (G 'Provider nur nach dem Frame' @($py, 'tool/check_provider_in_lifecycle.py'))
        (G 'Mojibake' @($py, 'tool/check_mojibake.py', '--skip-known'))
        (G '.gitignore auf Luecken' @($py, 'tool/check_gitignore.py'))
        (G 'PNG-Dateien auf Korruption' @($py, 'tool/check_png_integrity.py'))
        (G 'Store-Screenshots auf Realismus' @($py, 'tool/check_store_screenshots.py'))
        (G 'Workflow-Datei ist gueltiges YAML' @($py, 'tool/check_workflows.py'))
        (G 'Screenshot-Schriftgroesse einheitlich' @($py, 'tool/check_screenshot_consistency.py'))
        (G 'Store-Listen vollstaendig und eigenstaendig' @($py, 'tool/check_store_listing_languages.py'))
        (G 'Store-Text fuer den aktuellen Build' @($py, 'tool/check_store_changelog.py'))
        (G 'Keystore-Passwoerter nicht im Projektverzeichnis' @($py, 'tool/check_keystore_secrets.py'))
        (G 'Release-Checker Selbsttest' @($py, 'tool/check_release_artifacts_selftest.py'))
        (G 'Release-Konsistenz Selbsttest' @($py, 'tool/check_release_consistency_selftest.py'))
        # BEFUND (11.11.2026): Die Release-Notes hatten einen eigenen
        # Pruefsummen-Block, der beim Build nicht mitgepflegt wurde -
        # auf GitHub standen dadurch falsche Summen. Dieses Gate
        # vergleicht die Summen in ALLEN Release-Dokumenten mit den
        # Dateien.
        (G 'Release-Pruefsummen stimmen' @($py, 'tool/check_release_checksums.py'))
    )
}

# ---------------------------------------------------------------------
# passkey-assets
# ---------------------------------------------------------------------
if (Soll 'passkey-assets') {
    Gates 'passkey-assets' @(
        (G 'Passkey-Assets pruefen' @($py, 'tool/check_passkey_assetlinks.py'))
        (G 'Web-Payload und Cache pruefen' @($py, 'tool/check_web_payload.py'))
    )
}

Pop-Location

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor DarkGray
Write-Host '  Ergebnis' -ForegroundColor White
Write-Host ('=' * 72) -ForegroundColor DarkGray
foreach ($z in $ergebnisse) {
    if ($z.StartsWith('OK')) { Write-Host "  $z" -ForegroundColor Green }
    else { Write-Host "  $z" -ForegroundColor Red }
}
Write-Host ''
if ($fehler.Count -eq 0) {
    Write-Host '  ALLE GATES GRUEN - die CI wird ebenfalls gruen sein.' -ForegroundColor Green
    exit 0
} else {
    Write-Host "  $($fehler.Count) GATE(S) ROT:" -ForegroundColor Red
    foreach ($f in $fehler) { Write-Host "    - $f" -ForegroundColor Red }
    exit 1
}
