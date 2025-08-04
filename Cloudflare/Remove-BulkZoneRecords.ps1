<#
.SYNOPSIS
    Elimina registros DNS de Cloudflare creados dentro de un rango de fechas.

.DESCRIPTION
    • Obtiene el Zone ID a partir del nombre de la zona.  
    • Lista todos los registros DNS de la zona.  
    • Filtra los que posean el campo 'created_on' y cuya fecha (parte
      de calendario) se encuentre entre -StartDate y -EndDate (inclusive).  
    • Para cada registro filtrado, llama a DELETE
      https://api.cloudflare.com/client/v4/zones/{zoneId}/dns_records/{recordId}.  
    • Soporta -WhatIf / -Confirm porque usa ShouldProcess.

.PARAMETER Zone
    Nombre de la zona (e.g. contoso.com).

.PARAMETER ApiToken
    API Token con permiso "Zone → DNS → Edit".

.PARAMETER StartDate
    Fecha inicial (yyyy-MM-dd). Se interpreta a 00:00 hs.

.PARAMETER EndDate
    Fecha final (yyyy-MM-dd). Se interpreta a 00:00 hs.

.EXAMPLE
    .\Remove-CfDnsRecordsByDate.ps1 -Zone "contoso.com" `
        -ApiToken $env:CLOUDFLARE_TOKEN `
        -StartDate "2024-01-01" -EndDate "2024-03-31" -Verbose

.NOTES
    Usa per_page=5000; ajusta paginación si tu zona supera ese número.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string] $Zone,

    [Parameter(Mandatory = $true)]
    [string] $ApiToken,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string] $StartDate,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string] $EndDate
)

#region 1 – Conversión y validación de fechas
try {
    $from = [DateTime]::ParseExact($StartDate, 'yyyy-MM-dd', $null).Date
    $to   = [DateTime]::ParseExact($EndDate,   'yyyy-MM-dd', $null).Date
} catch {
    throw "Las fechas deben estar en formato yyyy-MM-dd."
}
if ($to -lt $from) { throw "-EndDate no puede ser anterior a -StartDate." }
#endregion

#region 2 – Cabeceras comunes y búsqueda del Zone ID
$Headers = @{
    "Authorization" = "Bearer $ApiToken"
    "Content-Type"  = "application/json"
}

Write-Verbose "Obteniendo Zone ID para '$Zone'..."
$zoneResp = Invoke-RestMethod -Method GET `
    -Uri "https://api.cloudflare.com/client/v4/zones?name=$Zone" `
    -Headers $Headers
if (-not $zoneResp.success -or -not $zoneResp.result) {
    throw "Zona '$Zone' no encontrada o error de API: $($zoneResp.errors)"
}
$zoneId = $zoneResp.result[0].id
#endregion

#region 3 – Descarga de registros DNS
Write-Verbose "Descargando registros DNS..."
$dnsResp = Invoke-RestMethod -Method GET `
    -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?per_page=5000" `
    -Headers $Headers
if (-not $dnsResp.success) {
    throw "Error al obtener los registros DNS: $($dnsResp.errors)"
}
$records = $dnsResp.result
#endregion

#region 4 – Filtrado por rango de fechas
$filterable = $records | Where-Object {
    $_.PSObject.Properties.Match('created_on').Count -gt 0
}

$toDelete = $filterable | Where-Object {
    $recDate = ([DateTime]$_.created_on).Date
    ($recDate -ge $from) -and ($recDate -le $to)
}

if ($toDelete.Count -eq 0) {
    Write-Host "No se encontraron registros entre $StartDate y $EndDate."
    return
}

Write-Host "Se encontraron $($toDelete.Count) registro(s) para eliminar:`n" -ForegroundColor Cyan
$toDelete | Select-Object name, type, content, @{N='CreatedOn';E={($_.created_on).Substring(0,10)}} |
    Format-Table -AutoSize
#endregion

#region 5 – Eliminación con ShouldProcess
$deleted  = 0
$failures = 0

foreach ($rec in $toDelete) {
    $target = "$($rec.name) [$($rec.type)]"
    if ($PSCmdlet.ShouldProcess($target, "Eliminar")) {
        try {
            Invoke-RestMethod -Method DELETE `
                -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$($rec.id)" `
                -Headers $Headers | Out-Null
            Write-Verbose "✓ Eliminado $target"
            $deleted++
        } catch {
            Write-Warning "✗ Falló al eliminar $target : $_"
            $failures++
        }
    }
}

Write-Host "`nResumen: $deleted eliminados, $failures errores."
#endregion
