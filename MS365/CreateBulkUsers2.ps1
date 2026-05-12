# Requiere:
# Install-Module Microsoft.Graph -Scope CurrentUser

function New-RandomPassword {
    param (
        [int]$Length = 10
    )

    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ".ToCharArray()
    $lower = "abcdefghijkmnopqrstuvwxyz".ToCharArray()
    $digits = "23456789".ToCharArray()
    $symbols = "*-+=".ToCharArray()

    $all = $upper + $lower + $digits + $symbols

    $passwordChars = @()
    $passwordChars += $upper | Get-Random
    $passwordChars += $lower | Get-Random
    $passwordChars += $digits | Get-Random
    $passwordChars += $symbols | Get-Random

    for ($i = $passwordChars.Count; $i -lt $Length; $i++) {
        $passwordChars += $all | Get-Random
    }

    $passwordChars = $passwordChars | Sort-Object { Get-Random }

    return -join $passwordChars
}

$csvPath = "C:\temp\usuarios.csv"
$usageLocation = "UY"

# Escopes necesarios para crear usuarios, gestionar grupos y licencias
$Scopes = @(
    "User.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All",
    "GroupMember.ReadWrite.All",
    "LicenseAssignment.ReadWrite.All"
)

# Conectar a Microsoft Graph
Connect-MgGraph -Scopes $Scopes

#Import-Module Microsoft.Graph.Users.Actions

$skuMap = @{
    "Microsoft 365 Business Basic"    = "O365_BUSINESS_ESSENTIALS"
    "Microsoft 365 Business Standard" = "O365_BUSINESS_PREMIUM"
}

$subscribedSkus = Get-MgSubscribedSku -All

$usuarios = Import-Csv -Path $csvPath -Delimiter ";" -Encoding UTF8

$resultados = @()

foreach ($usuario in $usuarios) {

    $nombre = ($usuario.Nombre).Trim()
    $apellido = ($usuario.Apellido).Trim()
    $userPrincipalName = ($usuario.'Email principal').Trim()
    $licencia = ($usuario.Licencia).Trim()
    $cargo = ($usuario.Cargo).Trim()

    if ([string]::IsNullOrWhiteSpace($apellido)) {
        $displayName = $nombre
    }
    else {
        $displayName = "$nombre $apellido"
    }

    if (-not $skuMap.ContainsKey($licencia)) {
        Write-Warning "No hay mapeo de licencia para '$licencia'. Usuario omitido: $userPrincipalName"
        continue
    }

    $skuPartNumber = $skuMap[$licencia]
    $sku = $subscribedSkus | Where-Object { $_.SkuPartNumber -eq $skuPartNumber }

    if (-not $sku) {
        Write-Warning "El tenant no tiene disponible el SKU '$skuPartNumber'. Usuario omitido: $userPrincipalName"
        continue
    }

    $mailNickname = ($userPrincipalName.Split("@")[0]) -replace "[^a-zA-Z0-9._-]", ""

    $plainPassword = New-RandomPassword -Length 10

    $passwordProfile = @{
        Password = $plainPassword
        ForceChangePasswordNextSignIn = $true
    }

$existingUser = Get-MgUser -UserId $userPrincipalName -ErrorAction SilentlyContinue

if ($existingUser) {
    Write-Host "Ya existe: $userPrincipalName. Actualizando datos básicos y asignando licencia..." -ForegroundColor Yellow

    $updateParams = @{
        UserId        = $userPrincipalName
        DisplayName   = $displayName
        GivenName     = $nombre
        UsageLocation = $usageLocation
    }

    if (-not [string]::IsNullOrWhiteSpace($apellido)) {
        $updateParams.Surname = $apellido
    }

    if (-not [string]::IsNullOrWhiteSpace($cargo)) {
        $updateParams.JobTitle = $cargo
    }

    Update-MgUser @updateParams
}
else {
    Write-Host "Creando usuario: $userPrincipalName" -ForegroundColor Cyan

    $newUserParams = @{
        AccountEnabled    = $true
        DisplayName       = $displayName
        GivenName         = $nombre
        UserPrincipalName = $userPrincipalName
        MailNickname      = $mailNickname
        UsageLocation     = $usageLocation
        PasswordProfile   = $passwordProfile
    }

    if (-not [string]::IsNullOrWhiteSpace($apellido)) {
        $newUserParams.Surname = $apellido
    }

    if (-not [string]::IsNullOrWhiteSpace($cargo)) {
        $newUserParams.JobTitle = $cargo
    }

    New-MgUser @newUserParams
}

    Set-MgUserLicense `
        -UserId $userPrincipalName `
        -AddLicenses @(
            @{
                SkuId = $sku.SkuId
            }
        ) `
        -RemoveLicenses @()

    $resultados += [PSCustomObject]@{
        DisplayName = $displayName
        UserPrincipalName = $userPrincipalName
        TemporaryPassword = $plainPassword
        License = $licencia
    }

    Write-Host "OK: $displayName <$userPrincipalName> - $licencia" -ForegroundColor Green
}

$resultados | Export-Csv `
    -Path "C:\temp\usuarios_creados_passwords.csv" `
    -NoTypeInformation `
    -Encoding UTF8