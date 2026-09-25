# =============================================================================
# generate_icons.ps1
# -----------------------------------------------------------------------------
# Generiert die Icon-Quell-Assets fuer das Thestia-App-Icon (Android + iOS):
#
#   1. assets/images/thestia_icon_foreground.png  (1024x1024)
#      - Transparentes Foreground fuer das Android Adaptive Icon.
#      - Weisse Bereiche (Hintergrund des Basis-PNG) werden per
#        Flood-Fill-Weiss-Keying (verbunden mit dem Bildrand) transparent.
#      - Das Logo-Badge wird auf 66 % des Canvas skaliert und zentriert,
#        damit es in der Safe-Zone jeder Launcher-Maske (Kreis/Squircle)
#        vollstaendig sichtbar ist.
#
#   2. assets/images/thestia_icon_ios.png          (1024x1024)
#      - Voll opake Quadrat-Variante des Basis-PNG fuer iOS (Apple maskt
#        selbst, Quadrat ohne Transparenz ist dort Pflicht).
#
#   3. build/icon_previews/preview_circle.png   (512x512)
#   4. build/icon_previews/preview_squircle.png (512x512)
#      - Simulation der finalen Adaptive-Icon-Darstellung unter einer
#        runden bzw. eckigen (Squircle) Launcher-Maske (Hintergrund weiss,
#        Bereiche ausserhalb der Maske grau markiert).
#      - Zusaetzlich numerische Pruefung: KEIN Pixel des Badges darf
#        ausserhalb der Maske liegen (Ausgabe PASS/FAIL je Maske).
#
# Verwendung:
#   powershell -ExecutionPolicy Bypass -File tool\generate_icons.ps1
#   (danach: flutter pub get && dart run flutter_launcher_icons)
# =============================================================================

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $root 'assets\images\thestia_icon_base.png'
$outForeground = Join-Path $root 'assets\images\thestia_icon_foreground.png'
$outIos = Join-Path $root 'assets\images\thestia_icon_ios.png'
$previewDir = Join-Path $root 'build\icon_previews'

# Weiss-Keying-Schwelle: Pixel mit min(R,G,B) >= $whiteThreshold gelten als
# "weiss". 250 gewaehlt, damit die hellen Herz-Highlights (min ~237) sicher
# erhalten bleiben.
$whiteThreshold = 250

Write-Host "Lade Basis-PNG: $srcPath"
$bmp = New-Object System.Drawing.Bitmap($srcPath)
$w = $bmp.Width
$h = $bmp.Height
Write-Host ("Groesse: {0}x{1}, PixelFormat: {2}" -f $w, $h, $bmp.PixelFormat)

# --- 1. Pixel einmalig in Arrays lesen (schneller BFS ohne GetPixel) ---------
$rArr = New-Object 'byte[]' ($w * $h)
$gArr = New-Object 'byte[]' ($w * $h)
$bArr = New-Object 'byte[]' ($w * $h)
$minArr = New-Object 'byte[]' ($w * $h)
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $p = $bmp.GetPixel($x, $y)
        $i = $y * $w + $x
        $rArr[$i] = $p.R; $gArr[$i] = $p.G; $bArr[$i] = $p.B
        $m = $p.R
        if ($p.G -lt $m) { $m = $p.G }
        if ($p.B -lt $m) { $m = $p.B }
        $minArr[$i] = [byte]$m
    }
}

# --- 2. Flood-Fill-Weiss-Keying vom Rand (verbunden mit aussen => transparent)
$keyed = New-Object 'byte[]' ($w * $h)   # 1 = transparent
$queue = New-Object System.Collections.Generic.Queue[int]

function Test-White([int]$idx) {
    return ($minArr[$idx] -ge $whiteThreshold)
}

function Enqueue-IfWhite([int]$idx) {
    if ($keyed[$idx] -eq 1) { return }
    if ($minArr[$idx] -ge $whiteThreshold) {
        $keyed[$idx] = 1
        $queue.Enqueue($idx)
    }
}

# Startpunkte: alle Randpixel
for ($x = 0; $x -lt $w; $x++) { Enqueue-IfWhite $x; Enqueue-IfWhite (($h - 1) * $w + $x) }
for ($y = 1; $y -lt ($h - 1); $y++) { Enqueue-IfWhite ($y * $w); Enqueue-IfWhite ($y * $w + $w - 1) }

while ($queue.Count -gt 0) {
    $idx = $queue.Dequeue()
    $x = $idx % $w
    $y = [int]($idx / $w)
    if ($x -gt 0) { Enqueue-IfWhite ($idx - 1) }
    if ($x -lt ($w - 1)) { Enqueue-IfWhite ($idx + 1) }
    if ($y -gt 0) { Enqueue-IfWhite ($idx - $w) }
    if ($y -lt ($h - 1)) { Enqueue-IfWhite ($idx + $w) }
}

# --- 3. Bounding-Box der NICHT getkeyten (Badge-)Pixel ------------------------
$minX = $w; $minY = $h; $maxX = -1; $maxY = -1
$whiteIshRemaining = 0
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $i = $y * $w + $x
        if ($keyed[$i] -eq 1) { continue }
        if ($minArr[$i] -ge $whiteThreshold) { $whiteIshRemaining++ }
        if ($x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($y -gt $maxY) { $maxY = $y }
    }
}
Write-Host ("Badge-BBox nach Keying: x={0}..{1} (w={2}), y={3}..{4} (h={5})" -f $minX, $maxX, ($maxX - $minX + 1), $minY, $maxY, ($maxY - $minY + 1))
Write-Host ("Weissliche Pixel INNERHALB der BBox (min>={0}): {1} (muessen im Herz eingeschlossen bleiben, > 0)" -f $whiteThreshold, $whiteIshRemaining)

# --- 4. Crop (mit 2 px Rand) + quadratisch padden ------------------------------
$pad = 2
$cx0 = [Math]::Max(0, $minX - $pad)
$cy0 = [Math]::Max(0, $minY - $pad)
$cx1 = [Math]::Min($w - 1, $maxX + $pad)
$cy1 = [Math]::Min($h - 1, $maxY + $pad)
$cw = $cx1 - $cx0 + 1
$ch = $cy1 - $cy0 + 1
$side = [Math]::Max($cw, $ch)
$crop = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gCrop = [System.Drawing.Graphics]::FromImage($crop)
$gCrop.Clear([System.Drawing.Color]::Transparent)
$dx = [int](($side - $cw) / 2)
$dy = [int](($side - $ch) / 2)
for ($y = 0; $y -lt $ch; $y++) {
    for ($x = 0; $x -lt $cw; $x++) {
        $i = ($y + $cy0) * $w + ($x + $cx0)
        if ($keyed[$i] -eq 1) { continue }
        $crop.SetPixel($dx + $x, $dy + $y, [System.Drawing.Color]::FromArgb(255, $rArr[$i], $gArr[$i], $bArr[$i]))
    }
}
$gCrop.Dispose()
$bmp.Dispose()
Write-Host ("Crop-Groesse (quadratisch): {0}x{1}" -f $side, $side)

# --- 5. Foreground-Master 1024x1024 (Badge auf 66 % der Safe-Zone) ------------
function New-ScaledCanvas([int]$canvasSize, [System.Drawing.Bitmap]$source, [double]$scale) {
    $canvas = New-Object System.Drawing.Bitmap($canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $target = [int]($canvasSize * $scale)
    $off = [int](($canvasSize - $target) / 2)
    $g.DrawImage($source, $off, $off, $target, $target)
    $g.Dispose()
    return $canvas
}

$masterSize = 1024
$foreground = New-ScaledCanvas $masterSize $crop 0.66
$foreground.Save($outForeground, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("Foreground-Master geschrieben: $outForeground (Badge auf 66 %)")

# --- 6. iOS-Master 1024x1024 (voll opak, Original-Layout) ----------------------
$srcFull = New-Object System.Drawing.Bitmap($srcPath)
$iosMaster = New-ScaledCanvas $masterSize $srcFull 1.0
$iosMaster.Save($outIos, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("iOS-Master geschrieben: $outIos")
$srcFull.Dispose()

# --- 7. Masken-Simulation (rund + squircle) auf 512x512 ------------------------
if (-not (Test-Path -LiteralPath $previewDir)) { New-Item -ItemType Directory -Path $previewDir | Out-Null }

function New-MaskPreview([string]$name, [scriptblock]$InsideMask) {
    $size = 512
    $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.Color]::White)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.DrawImage($foreground, 0, 0, $size, $size)
    $g.Dispose()

    $cx = $size / 2.0; $cy = $size / 2.0; $radius = $size / 2.0
    $badgeOutside = 0
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            $p = $canvas.GetPixel($x, $y)
            $relX = [Math]::Abs($x + 0.5 - $cx)
            $relY = [Math]::Abs($y + 0.5 - $cy)
            if (& $InsideMask $relX $relY $radius) {
                # innerhalb der Maske: unveraendert
            } else {
                # ausserhalb: grau markieren (Maskengrenze sichtbar)
                $canvas.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 200, 200, 200))
                # Badge-Pixel (nicht weiss) ausserhalb der Maske zaehlen
                $m = [Math]::Min($p.R, [Math]::Min($p.G, $p.B))
                if ($p.A -gt 0 -and $m -lt 245) { $badgeOutside++ }
            }
        }
    }
    $canvas.Save((Join-Path $previewDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    if ($badgeOutside -eq 0) {
        Write-Host ("PASS  {0}: 0 Badge-Pixel ausserhalb der Maske" -f $name)
    } else {
        Write-Host ("FAIL  {0}: {1} Badge-Pixel ausserhalb der Maske!" -f $name, $badgeOutside)
    }
    return $badgeOutside
}

$circleMask = { param($rx, $ry, $r) return (($rx * $rx + $ry * $ry) -le ($r * $r)) }
$squircleMask = { param($rx, $ry, $r) return (($rx * $rx * $rx * $rx + $ry * $ry * $ry * $ry) -le ($r * $r * $r * $r)) }

$failCircle = New-MaskPreview 'preview_circle.png' $circleMask
$failSquircle = New-MaskPreview 'preview_squircle.png' $squircleMask

$foreground.Dispose()
$crop.Dispose()

if ($failCircle -gt 0 -or $failSquircle -gt 0) {
    Write-Host "FEHLGESCHLAGEN: Badge ragt in den Masken-Bereich. Skalierung pruefen."
    exit 1
}
Write-Host "OK: Icon-Assets und Masken-Simulation erfolgreich."
