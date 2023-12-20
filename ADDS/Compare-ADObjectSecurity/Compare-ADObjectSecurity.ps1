Param(
    [Parameter(Mandatory)]
    [string]
    $Usuario1,
    [Parameter(Mandatory)]
    [string]
    $Usuario2,
    [Parameter(Mandatory)]
    [string]
    $RutaExportacion
)

# Ubicarse en AD para poder obtener las ACL
Set-Location AD:

$user1 = Get-ADUser $Usuario1
$user2 = Get-ADUser $Usuario2

# Obtener las ACL de cada objeto 
$accesos1 = (get-acl $user1).Access
$accesos2 = (get-acl $user2).Access

<#

# Esta comparación no funciona :-( 

foreach ($item in $accesos1) {
    if ($item -notin $accesos2) {
        $item
    }
    else {
        $iguales += 1
    }
}
#>

# Write-Host "Iguales: $iguales"

# Exportar los resultados como CSV para hacerlos facilmente comparables
$accesos1 | export-csv -Path "C:\Work\$Usuario1.csv" -Delimiter ";" -NoTypeInformation -Encoding UTF8
$accesos2 | export-csv -Path "C:\Work\$Usuario2.csv" -Delimiter ";" -NoTypeInformation -Encoding UTF8

# Leer los archivos
$contenidoArchivo1 = Get-Content "C:\Work\$Usuario1.csv"
$contenidoArchivo2 = Get-Content "C:\Work\$Usuario2.csv"

# Obtener el máximo número de líneas
$maxLineas = [Math]::Max($contenidoArchivo1.Count, $contenidoArchivo2.Count)

"usuario`tlinea`tcontenido" | Out-File -FilePath "$RutaExportacion\diferentes.tsv" -Encoding utf8

# Comparar línea por línea
for ($i = 0; $i -lt $maxLineas; $i++) {
    $lineaArchivo1 = $contenidoArchivo1[$i]
    $lineaArchivo2 = $contenidoArchivo2[$i]

    # Verificar si las líneas son diferentes
    if ($lineaArchivo1 -ne $lineaArchivo2) {
        # Imprimir las líneas diferentes
        if ($i -lt $contenidoArchivo1.Count) {
            "$Usuario1`t$i`t$lineaArchivo1" | Out-File -FilePath "$RutaExportacion\diferentes.tsv" -Encoding utf8 -Append
        }

        if ($i -lt $contenidoArchivo2.Count) {
            "$Usuario2`t$i`t$lineaArchivo2" | Out-File -FilePath "$RutaExportacion\diferentes.tsv" -Encoding utf8 -Append
        }
    }
}