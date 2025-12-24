$Domain      = "dominio.com"
$AliasDomain = "gsuite.$Domain"
$OutFile     = "map-$Domain.csv"
$tmpCsv      = Join-Path $env:TEMP "gam-$($Domain)-users.csv"

& gam print users domain $Domain fields primaryEmail > $tmpCsv

$rows = Import-Csv -Path $tmpCsv
$localParts = @()

foreach ($r in $rows) {
    $primary = $r.primaryEmail
    if (-not $primary) { $primary = $r.'Primary Email' }
    if (-not $primary) { continue }

    $lp = $primary.Split('@')[0]
    $localParts += $lp
}

$mapLines = @()
foreach ($lp in $localParts) {
    $mapLines += "$lp@$AliasDomain,$lp@$Domain"
}

$mapLines | Out-File ".\$OutFile" -Encoding UTF8
Write-Host "Listo. Generado: $OutFile  (Entradas: $($mapLines.Count))"
