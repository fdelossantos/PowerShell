# Script PowerShell para convertir CSV con JSON anidado a JSON puro
# Archivo: ConvertAuditDataToJson.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$InputCsvPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputJsonPath
)

function ConvertTo-DecodedJson {
    param([object]$InputObject)
    
    if ($InputObject -is [string]) {
        # Intentar parsear si parece ser JSON
        if (($InputObject.StartsWith('{') -and $InputObject.EndsWith('}')) -or 
            ($InputObject.StartsWith('[') -and $InputObject.EndsWith(']'))) {
            try {
                $parsed = $InputObject | ConvertFrom-Json
                return ConvertTo-DecodedJson $parsed
            }
            catch {
                return $InputObject
            }
        }
        return $InputObject
    }
    elseif ($InputObject -is [array]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ConvertTo-DecodedJson $item
        }
        return $result
    }
    elseif ($InputObject -is [PSCustomObject] -or $InputObject -is [hashtable]) {
        $result = @{}
        $InputObject.PSObject.Properties | ForEach-Object {
            $result[$_.Name] = ConvertTo-DecodedJson $_.Value
        }
        return [PSCustomObject]$result
    }
    
    return $InputObject
}

Write-Host "Leyendo archivo CSV: $InputCsvPath" -ForegroundColor Green

# Leer el CSV
try {
    $csvData = Import-Csv -Path $InputCsvPath -Encoding UTF8
    Write-Host "Archivo CSV cargado correctamente. Registros encontrados: $($csvData.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Error leyendo el archivo CSV: $($_.Exception.Message)"
    exit 1
}

Write-Host "Procesando datos JSON anidados..." -ForegroundColor Yellow

# Procesar cada fila
$processedData = @()
$errorCount = 0

foreach ($row in $csvData) {
    $processedRow = [PSCustomObject]@{}
    
    # Copiar todas las propiedades
    $row.PSObject.Properties | ForEach-Object {
        $processedRow | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value
    }
    
    # Procesar AuditData si existe
    if ($row.AuditData -and $row.AuditData.Trim() -ne "") {
        try {
            $auditDataJson = $row.AuditData | ConvertFrom-Json
            $processedRow.AuditData = ConvertTo-DecodedJson $auditDataJson
        }
        catch {
            Write-Warning "Error procesando AuditData en registro $($row.RecordId): $($_.Exception.Message)"
            $errorCount++
            # Mantener el valor original si hay error
            $processedRow.AuditData = $row.AuditData
        }
    }
    
    $processedData += $processedRow
}

# Crear el objeto final con metadata
$finalObject = [PSCustomObject]@{
    metadata = [PSCustomObject]@{
        originalFile = Split-Path -Leaf $InputCsvPath
        totalRecords = $processedData.Count
        processedDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        columns = ($csvData | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
        errorsEncountered = $errorCount
    }
    records = $processedData
}

Write-Host "Generando archivo JSON..." -ForegroundColor Yellow

# Convertir a JSON y guardar
try {
    $jsonOutput = $finalObject | ConvertTo-Json -Depth 50 -Compress:$false
    $jsonOutput | Out-File -FilePath $OutputJsonPath -Encoding UTF8 -Force
    
    Write-Host "¡Conversión completada exitosamente!" -ForegroundColor Green
    Write-Host "Archivo de salida: $OutputJsonPath" -ForegroundColor Cyan
    Write-Host "Registros procesados: $($processedData.Count)" -ForegroundColor Cyan
    Write-Host "Errores encontrados: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) {"Red"} else {"Green"})
    Write-Host "Tamaño del archivo: $([math]::Round((Get-Item $OutputJsonPath).Length / 1MB, 2)) MB" -ForegroundColor Cyan
}
catch {
    Write-Error "Error guardando el archivo JSON: $($_.Exception.Message)"
    exit 1
}

# Mostrar una muestra del resultado
Write-Host "`nMostrando muestra del primer registro procesado:" -ForegroundColor Magenta
if ($processedData.Count -gt 0) {
    $sample = $processedData[0] | ConvertTo-Json -Depth 3
    if ($sample.Length -gt 1000) {
        $sample = $sample.Substring(0, 1000) + "`n... (truncado)"
    }
    Write-Host $sample -ForegroundColor White
}

Write-Host "`n=== USO ===" -ForegroundColor Yellow
Write-Host "Para usar este script:" -ForegroundColor White
Write-Host ".\ConvertAuditDataToJson.ps1 -InputCsvPath 'ruta\al\archivo.csv'" -ForegroundColor Gray
Write-Host ".\ConvertAuditDataToJson.ps1 -InputCsvPath 'archivo.csv' -OutputJsonPath 'salida.json'" -ForegroundColor Gray