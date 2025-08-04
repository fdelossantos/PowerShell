<#
.SYNOPSIS
    Lista los registros DNS de una zona en Cloudflare.

.DESCRIPTION
    Utiliza la API REST de Cloudflare.  Recibe la zona (ej.: midominio.com) 
    y un API Token con permisos de lectura sobre la zona.
    Si la respuesta contiene la propiedad 'created_on', los registros
    se ordenan por esa fecha ascendentemente y se muestran.

.PARAMETER Zone
    Nombre canónico de la zona tal como se ve en Cloudflare
    (por ejemplo: contoso.com).

.PARAMETER ApiToken
    API Token con permiso "Zone → DNS → Read".

.EXAMPLE
    .\Get-CfDnsRecords.ps1 -Zone "contoso.com" -ApiToken $env:CLOUDFLARE_TOKEN
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Zone,

    [Parameter(Mandatory = $true)]
    [string] $ApiToken
)

# Cabeceras comunes
$Headers = @{
    "Authorization" = "Bearer $ApiToken"
    "Content-Type"  = "application/json"
}

# 1. Obtener el Zone ID de la zona indicada
try {
    $zoneResp = Invoke-RestMethod -Method Get `
        -Uri "https://api.cloudflare.com/client/v4/zones?name=$Zone" `
        -Headers $Headers
} catch {
    throw "Error consultando la zona '$Zone': $_"
}

if (-not $zoneResp.success -or -not $zoneResp.result) {
    throw "No se encontró la zona '$Zone' o la API devolvió error: $($zoneResp.errors)"
}

$zoneId = $zoneResp.result[0].id

# 2. Listar los registros DNS de la zona
try {
    $dnsResp = Invoke-RestMethod -Method Get `
        -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?per_page=200" `
        -Headers $Headers
} catch {
    throw "Error obteniendo los registros DNS de '$Zone': $_"
}

if (-not $dnsResp.success) {
    throw "La llamada DNS devolvió error: $($dnsResp.errors)"
}

$records = $dnsResp.result

# 3. Si existe 'created_on', ordenar y exponerla
$selectProps = @(
    @{Name = 'Name';       Expression = { $_.name       } },
    @{Name = 'Type';       Expression = { $_.type       } },
    @{Name = 'Content';    Expression = { $_.content    } },
    @{Name = 'TTL';        Expression = { $_.ttl        } },
    @{Name = 'Proxied';    Expression = { $_.proxied    } }
)

if ($records[0].PSObject.Properties.Match('created_on').Count -gt 0) {
    $records = $records | Sort-Object created_on
    $selectProps += @{
        Name       = 'CreatedOn'
        Expression = { Get-Date $_.created_on -Format 'yyyy-MM-dd HH:mm:ss' }
    }
}

# 4. Mostrar en pantalla.  Quita el Format-Table si quieres devolver objetos al pipeline.
$records | Select-Object $selectProps | Format-Table -AutoSize
