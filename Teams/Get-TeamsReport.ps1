param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet('D7', 'D30', 'D90', 'D180')]
    [string]$Period = 'D30',

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\Reports\Teams"
)

function Encrypt-String {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [string]$PlainText
    )
    Add-Type -AssemblyName System.Security
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [Convert]::ToBase64String($encryptedBytes)
}

function Decrypt-String {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [string]$EncryptedText
    )
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String($EncryptedText)
    $decryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [Text.Encoding]::UTF8.GetString($decryptedBytes)
}

$decryptedSecret = Decrypt-String $ClientSecret

# Obtener token OAuth2 para Microsoft Graph
$Body = @{
    client_id     = $ClientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = "$decryptedSecret"
    grant_type    = "client_credentials"
}

$TokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $Body
$AccessToken   = $TokenResponse.access_token

$Headers = @{
    Authorization = "Bearer $AccessToken"
}

# Crear carpeta de salida si no existe
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

$uri = "https://graph.microsoft.com/v1.0/reports/getTeamsUserActivityCounts(period='$Period')"
# $uri = "https://graph.microsoft.com/v1.0/reports/getTeamsUserActivityUserDetail(period='$Period')"

$response = Invoke-WebRequest -Method Get -Uri $uri -Headers $Headers

$today   = Get-Date -Format "yyyyMMdd"
$outFile = Join-Path $OutputFolder "getTeamsUserActivityCounts_$Period-$today.csv"
# $outFile = Join-Path $OutputFolder "TeamsUserActivityUserDetail_$Period-$today.csv"

[System.IO.File]::WriteAllBytes($outFile, $response.Content)

Write-Host "Reporte guardado en $outFile"