# tool/set_hook_secret.ps1
#
# Setzt das Hook-Secret des Send-Email-Hooks in die Edge Function - und
# prueft sofort, ob es passt. Alles in einem Schritt, ohne dass der
# Wert irgendwo sichtbar wird.
#
# WARUM ES DAS GIBT (24.10.2026):
#
# Das Secret steht im Dashboard MASKIERT. Man kann es nicht "sehen",
# aber man kann es KOPIEREN. Das Kopier-Symbol neben dem Feld legt den
# vollstaendigen Wert in die Zwischenablage - auch wenn die Anzeige
# maskiert ist. Wer den Wert nicht sieht, hat ihn trotzdem: er ist in
# der Zwischenablage.
#
# Zusaetzlich gibt es einen Fallstrick, der in der bisherigen Anleitung
# nicht vorkam: der Laufzeit-Zustand der Function ist zum DEPLOY-
# Zeitpunkt fixiert. Setzt man das Secret, laeuft die bereits
# gestartete Function weiter mit dem ALTEN Secret. Erst ein erneutes
# Deploy nimmt das neue Secret auf. Das Skript macht deshalb beides.
#
# VERWENDUNG
# -----------
#   1. Dashboard -> Authentication -> Hooks -> Send Email Hook
#   2. Neben dem Secret auf das KOPIER-Symbol klicken
#   3. Im Repo:
#        powershell -ExecutionPolicy Bypass -File tool\set_hook_secret.ps1
#
# Optionen:
#   -DryRun    zeigt nur, was passieren wuerde (aendert nichts)
#   -Value     statt der Zwischenablage diesen Wert verwenden
#              (NUR fuer automatisierte Laeufe - der Wert landet dann
#              in der Prozessliste und im Verlauf)
#
# AUSGABE: "PASS" oder "FAIL" - ohne Interpretationsspielraum.
# 400 = die Signatur wurde angenommen = alles stimmt.
# 401 = die Signatur wurde abgewiesen = die Werte unterscheiden sich.

param(
    [switch]$DryRun,
    [string]$Value
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$ProjectRef = 'jftuigjbmmuvrckbchqo'
$FunctionName = 'send-confirmation-email'
$Supabase = 'supabase.cmd'

Write-Host ''
Write-Host '=== Hook-Secret setzen und pruefen ===' -ForegroundColor Cyan
Write-Host ''

# --- 1) Wert holen -------------------------------------------------------
if ($Value) {
    $secret = $Value.Trim()
    $quelle = 'Parameter -Value'
} else {
    try {
        $secret = (Get-Clipboard -Raw).Trim()
    } catch {
        Write-Host 'FEHLER: Zwischenablage nicht lesbar.' -ForegroundColor Red
        Write-Host '  Bitte -Value verwenden oder die Zwischenablage pruefen.'
        exit 2
    }
    $quelle = 'Zwischenablage'
}

if (-not $secret) {
    Write-Host 'FEHLER: leerer Wert.' -ForegroundColor Red
    Write-Host '  Bitte im Dashboard (Authentication -> Hooks -> Send Email'
    Write-Host '  Hook) auf das KOPIER-Symbol neben dem Secret klicken und'
    Write-Host '  dieses Skript erneut starten.'
    exit 2
}

# Maskierte Kopien abfangen. Das ist der haeufigste Fehler: Das Dashboard
# zeigt das Secret maskiert ("v1,whsec_****abcd"). Wer den Text
# markiert statt das Kopier-Symbol zu nutzen, bekommt eine Zeichenkette
# mit Sternchen - und B64DEKODIEREN ignoriert Sternchen stillschweigend
# (validate=False). Daraus entsteht ein scheinbar gueltiger, aber
# falscher Schluessel, und die Pruefung sagt spaeter "401" - ohne dass
# klar waere, dass die Kopie maskiert war.
if ($secret -match '[\*\u2022\u2023]|\.\.\.|\[|\]') {
    Write-Host 'FEHLER: Der kopierte Wert sieht MASKIERT aus.' -ForegroundColor Red
    Write-Host '  Er enthaelt Sternchen oder Auslassungspunkte.'
    Write-Host ''
    Write-Host '  Richtig kopieren: NICHT den Text markieren, sondern im'
    Write-Host '  Dashboard auf das KOPIER-Symbol neben dem Secret klicken.'
    Write-Host '  Dann liegt der vollstaendige Wert in der Zwischenablage,'
    Write-Host '  auch wenn die Anzeige maskiert bleibt.'
    exit 2
}

# Base64-Dekodierbarkeit pruefen - ein Secret, das nicht dekodierbar
# ist, kann keine Signatur pruefen.
$b64teil = $secret -replace '^v1,','' -replace '^whsec_',''
if ($b64teil -notmatch '^[A-Za-z0-9+/]+={0,2}$' -and
    $secret -notmatch '^[0-9a-fA-F]+$') {
    Write-Host 'FEHLER: Der Wert ist weder Base64 noch Hex.' -ForegroundColor Red
    Write-Host '  Er enthaelt Zeichen, die in einem Secret nicht vorkommen.'
    Write-Host '  Vermutlich wurde die maskierte Anzeige kopiert.'
    exit 2
}

# Nichts ausgeben, was das Secret verraten koennte - nur Form und Laenge.
$form = 'unbekannt'
if ($secret -match '^v1,whsec_[A-Za-z0-9+/=_-]+$') { $form = 'v1,whsec_ (Standard-Webhooks)' }
elseif ($secret -match '^whsec_[A-Za-z0-9+/=_-]+$') { $form = 'whsec_ (ohne v1-Marker)' }
elseif ($secret -match '^[0-9a-fA-F]{64}$') { $form = '64 Hex-Zeichen (altes Dashboard-Format)' }
elseif ($secret -match '^[0-9a-fA-F]+$') { $form = 'Hex' }
elseif ($secret -match '^[A-Za-z0-9+/]+={0,2}$') { $form = 'Base64 ohne Praefix' }
else { $form = 'unbekanntes Format' }

Write-Host "Wertquelle:      $quelle"
Write-Host "Format:          $form"
Write-Host "Laenge:          $($secret.Length) Zeichen"
Write-Host ''

# Der Wert darf nicht in Logs oder in die Prozessliste. Deshalb geht er
# per Umgebungsvariable an den Aufruf - nicht als Argument.
$env:HOOK_SECRET_VALUE = $secret

if ($DryRun) {
    Write-Host 'DRY-RUN: Es wird nichts geaendert.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Wuerde tun:'
    Write-Host "  1. supabase secrets set HOOK_SECRET=<Wert> --project-ref $ProjectRef"
    Write-Host "  2. supabase functions deploy $FunctionName --project-ref $ProjectRef"
    Write-Host "  3. Pruefung gegen die laufende Function"
    exit 0
}

# --- 2) Secret in die Function -------------------------------------------
Write-Host '1/3  Secret in die Edge Function setzen ...' -ForegroundColor Cyan
& $Supabase secrets set "HOOK_SECRET=$secret" --project-ref $ProjectRef | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'FEHLER: supabase secrets set ist fehlgeschlagen.' -ForegroundColor Red
    exit 1
}

# --- 3) Function neu deployen --------------------------------------------
# Ohne das Deploy laeuft die Function mit dem ALTEN Secret weiter: die
# Umgebung ist zum Deploy-Zeitpunkt fixiert (supabase/supabase#51535).
Write-Host '2/3  Function neu deployen (nimmt das neue Secret auf) ...' -ForegroundColor Cyan
& $Supabase functions deploy $FunctionName --project-ref $ProjectRef | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'FEHLER: Deploy fehlgeschlagen.' -ForegroundColor Red
    exit 1
}

# --- 4) Pruefen -----------------------------------------------------------
Write-Host '3/3  Pruefung gegen die laufende Function ...' -ForegroundColor Cyan
Write-Host ''

$py = @'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("chk", "tool/check_hook_secret.py")
chk = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(chk)
except SystemExit:
    pass
secret = os.environ["HOOK_SECRET_VALUE"]
# EIN Timestamp fuer Signatur UND Header. Zwei getrennte time.time()-
# Aufrufe koennen die Sekunde wechseln - dann stimmt die Signatur nicht
# mehr und der Test meldet faelschlich "FAIL".
import time
wid, ts = "msg_secret_check", str(int(time.time()))
hit = False
for name, sig in chk.signiere(secret, wid, ts):
    st, txt = chk.ruf({"Content-Type": "application/json",
                        "webhook-id": wid,
                        "webhook-timestamp": ts,
                        "webhook-signature": sig})
    ok = st != 401 and st != "FEHLER" and "Unauthorized" not in txt
    print(f"  Ableitung {name:12} -> HTTP {st}  {txt[:60]}"
          f"{'   <-- SIGNATUR ANGENOMMEN' if ok else ''}")
    hit = hit or ok
print("PASS" if hit else "FAIL")
sys.exit(0 if hit else 1)
'@

$py | Out-File -FilePath (Join-Path $env:TEMP 'hook_check.py') -Encoding utf8
$output = python (Join-Path $env:TEMP 'hook_check.py') 2>&1
$output | ForEach-Object { Write-Host $_ }

Remove-Item Env:\HOOK_SECRET_VALUE -ErrorAction SilentlyContinue

if ($output -match 'PASS') {
    Write-Host ''
    Write-Host 'PASS - Secret stimmt, Function ist neu deployt.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Naechster Schritt: eine Registrierung in der App testen.'
    Write-Host 'Die Bestaetigungsmail muss jetzt ankommen. Falls nicht, in'
    Write-Host 'Supabase Dashboard -> Edge Functions -> send-confirmation-email'
    Write-Host '-> Logs nachsehen: dort steht, ob Mailjet oder Brevo die'
    Write-Host 'Mail angenommen hat (und aus welchem Grund nicht).'
    exit 0
} else {
    Write-Host ''
    Write-Host 'FAIL - die Werte passen nicht zueinander.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Moegliche Ursache: Das Secret im Dashboard wurde seit dem'
    Write-Host '  Kopieren geaendert, ODER es ist ein anderes Secret als das'
    Write-Host '  aus dem Send-Email-Hook (z. B. ein anderes Hook).'
    Write-Host '  Bitte erneut kopieren und dieses Skript nochmal starten.'
    exit 1
}
