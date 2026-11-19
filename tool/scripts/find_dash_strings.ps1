# tool/scripts/find_dash_strings.ps1 - findet En/Em-Dash (\u2013/\u2014) in String-Literals
$hits = Select-String -Path (Get-ChildItem lib -Recurse -Filter *.dart).FullName -Pattern "[\u2013\u2014]"
Write-Output "Treffer insgesamt: $($hits.Count)"
$inStrings = @()
foreach ($h in $hits) {
    $line = $h.Line
    $guess = $false
    if ($line -match "'[^']*[\u2013\u2014][^']*'") { $guess = $true }
    if ($line -match '"[^"]*[\u2013\u2014][^"]*"') { $guess = $true }
    if ($guess) { $inStrings += $h }
}
Write-Output "In String-Literals: $($inStrings.Count)"
$inStrings | ForEach-Object {
    "$($_.Path):$($_.LineNumber): $($_.Line.Trim())"
} | Out-File "$env:TEMP\dash_hits.txt" -Encoding UTF8
Write-Output "Liste: $env:TEMP\dash_hits.txt"
