# tool/copy_store_screenshots.ps1
#
# Kopiert die Store-Kacheln (releases/testapk/screenshots/marketing/9x16/)
# in die Fastlane-Metadaten-Struktur fuer Google Play / F-Droid.
#
# Voraussetzung:
#   1) Kacheln erzeugen:
#      $env:STORE_SHOTS="1"
#      flutter test --update-goldens test/screenshots/store_v091_shots_test.dart
#      python tool/make_store_screenshots.py
#   2) Dann dieses Skript (die Kacheln liegen in zwei Varianten vor:
#      9x16 = mit Statusleiste fuer den Store, 9x16-kacheln = ohne).
#
# WICHTIG (31.10.2026): Vorher zeigte dieses Skript auf
# test/screenshots/goldens - ein Ordner, den es im aktuellen Ablauf
# nicht mehr gibt. Es tat damit seit dem Umbau der Screenshot-Erzeugung
# nichts mehr und meldete trotzdem Erfolg. Das Skript zeigt jetzt auf
# den Ordner, aus dem der Composer tatsaechlich schreibt.
#
# Google-Play-Anforderungen (Phone): 1080x1920 erfuellt 9:16 (min 320px,
# max 3840px, Seite 1:2 bis 2:1). Reihenfolge = Upload-Reihenfolge im Play
# Store (Nr. im Dateinamen).

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

$src = "releases\testapk\screenshots\marketing\9x16"
$dest = "fastlane\metadata\android\de-DE\images\phoneScreenshots"

if (-not (Test-Path $src)) {
    throw "Keine Kacheln gefunden: $src - Bitte zuerst generieren (siehe Kopf)."
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item -Path (Join-Path $src "*.png") -Destination $dest -Force

Write-Host "==> Kopiert nach $dest" -ForegroundColor Green
Get-ChildItem $dest | ForEach-Object {
    Write-Host ("    {0}  ({1:N0} KB)" -f $_.Name, ($_.Length / 1KB))
}
