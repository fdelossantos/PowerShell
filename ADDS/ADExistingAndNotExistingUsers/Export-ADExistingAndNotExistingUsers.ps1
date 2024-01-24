param(
    [Parameter(Mandatory)]
    [string]$ArchivoCSV
)

# C:\Users\federicod\Documents\test.csv

Import-Module ActiveDirectory


$leafbase = ((Split-Path $ArchivoCSV -Leaf).ToString()  -split '.', 0, "simplematch")[0]
$parent = Split-Path $ArchivoCSV -Parent
$salidasi = "$parent\$leafbase-existentes.csv"
$salidano = "$parent\$leafbase-noexisten.csv"

$cargados = Import-Csv -Path $ArchivoCSV

$existentes = $cargados | Where-Object { Get-ADUser -Filter "userPrincipalName -eq '$($_.UPN)'"  }
$noexisten = $cargados | Where-Object { $_ -notin $existentes }


$existentes | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $salidasi
$noexisten | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $salidano
Write-Host "Proceso finalizado. Los archivos resultado están en:`n$salidasi`n$salidano"