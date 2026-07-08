<# 
.SYNOPSIS
Crea una App Registration para acceso restringido a un sitio de SharePoint Online mediante Sites.Selected.

# Microsoft Graph permite como máximo 1 año entre startDateTime y endDateTime
# para keyCredentials al cargar certificados en App Registrations.

.REQUISITOS
- PowerShell 7 recomendado.
- Microsoft.Graph.Authentication
- Microsoft.Graph.Applications
- Microsoft.Graph.Sites
- Usuario ejecutor: Global Admin o rol suficiente para crear apps, conceder admin consent y otorgar permisos al sitio.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $AppName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SiteUrl,

    [Parameter(Mandatory)]
    [ValidateSet("Read", "Write", "Manage", "FullControl")]
    [string] $SitePermission,

    [Parameter()]
    [ValidateRange(1, 12)]
    [int] $CertificateValidMonths = 12,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $TenantId,

    [Parameter()]
    [string] $OutputPath = (Join-Path $PWD "AppRegistrationOutput"),

    [Parameter()]
    [switch] $AllowDuplicateDisplayName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MinimumGraphModuleVersion = [Version] "2.20.0"

$GraphResourceAppId = "00000003-0000-0000-c000-000000000000"
$SharePointResourceAppId = "00000003-0000-0ff1-ce00-000000000000"
$RequiredPermissionValue = "Sites.Selected"

function Write-Step {
    param([string] $Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string] $Message)
    Write-Host "OK  $Message" -ForegroundColor Green
}

function Throw-Validation {
    param([string] $Message)
    throw "Validación fallida: $Message"
}

function Assert-GraphModule {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string[]] $Commands
    )

    $module = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $module) {
        throw "No está instalado el módulo $Name. Instalá o actualizá con: Install-Module Microsoft.Graph -Scope CurrentUser -Force"
    }

    if ($module.Version -lt $MinimumGraphModuleVersion) {
        throw "El módulo $Name está en versión $($module.Version). Se espera $MinimumGraphModuleVersion o superior. Actualizá con: Update-Module Microsoft.Graph"
    }

    Import-Module $Name -MinimumVersion $MinimumGraphModuleVersion -ErrorAction Stop

    foreach ($command in $Commands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "El cmdlet $command no está disponible. Revisá la instalación del módulo $Name."
        }
    }

    Write-Ok "$Name $($module.Version)"
}

function Escape-ODataString {
    param([string] $Value)
    return $Value.Replace("'", "''")
}

function ConvertTo-GraphDateTimeString {
    param(
        [Parameter(Mandatory)]
        [datetime] $DateTime
    )

    return $DateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-PlainTextFromSecureString {
    param(
        [Parameter(Mandatory)]
        [securestring] $SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-SafeFileName {
    param([string] $Name)

    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $safe = $Name

    foreach ($char in $invalidChars) {
        $safe = $safe.Replace($char, "_")
    }

    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw "El nombre de la aplicación no permite generar un nombre de archivo válido."
    }

    return $safe
}

function Get-ValidatedSharePointSiteUrl {
    param([string] $Url)

    $uri = $null

    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) {
        Throw-Validation "La URL del sitio no es una URL absoluta válida."
    }

    if ($uri.Scheme -ne "https") {
        Throw-Validation "La URL del sitio debe usar HTTPS."
    }

    if ($uri.Host -notmatch "\.sharepoint\.") {
        Throw-Validation "La URL no parece ser de SharePoint Online. Host recibido: $($uri.Host)"
    }

    if ($uri.AbsolutePath -match "/_layouts/" -or $uri.AbsolutePath -match "/forms/" -or $uri.AbsolutePath -match "/Shared%20Documents/") {
        Throw-Validation "Ingresá la URL del sitio, no una URL de biblioteca, carpeta, archivo o página interna."
    }

    $cleanBuilder = [UriBuilder]::new($uri)
    $cleanBuilder.Query = ""
    $cleanBuilder.Fragment = ""

    return $cleanBuilder.Uri
}

function Get-GraphSiteFromUrl {
    param(
        [Parameter(Mandatory)]
        [Uri] $ValidatedSiteUri
    )

    $hostName = $ValidatedSiteUri.Host
    $path = $ValidatedSiteUri.AbsolutePath.TrimEnd("/")

    if ([string]::IsNullOrWhiteSpace($path) -or $path -eq "/") {
        $graphUri = "https://graph.microsoft.com/v1.0/sites/$hostName"
    }
    else {
        $graphUri = "https://graph.microsoft.com/v1.0/sites/$hostName`:$path"
    }

    try {
        return Invoke-MgGraphRequest -Method GET -Uri $graphUri
    }
    catch {
        throw "No se pudo resolver la URL como sitio de SharePoint mediante Microsoft Graph. URL validada: $($ValidatedSiteUri.AbsoluteUri). Detalle: $($_.Exception.Message)"
    }
}

function Get-ApplicationAppRole {
    param(
        [Parameter(Mandatory)]
        $ResourceServicePrincipal,

        [Parameter(Mandatory)]
        [string] $Value
    )

    $role = $ResourceServicePrincipal.AppRoles | Where-Object {
        $_.Value -eq $Value -and
        $_.IsEnabled -eq $true -and
        $_.AllowedMemberTypes -contains "Application"
    } | Select-Object -First 1

    if (-not $role) {
        throw "No se encontró el permiso de aplicación $Value en el recurso $($ResourceServicePrincipal.DisplayName)."
    }

    return $role
}

function Ensure-AppRoleAssignment {
    param(
        [Parameter(Mandatory)]
        [string] $ClientServicePrincipalId,

        [Parameter(Mandatory)]
        $ResourceServicePrincipal,

        [Parameter(Mandatory)]
        $AppRole
    )

    $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientServicePrincipalId -All

    $existing = $assignments | Where-Object {
        $_.ResourceId -eq $ResourceServicePrincipal.Id -and
        $_.AppRoleId -eq $AppRole.Id
    } | Select-Object -First 1

    if ($existing) {
        Write-Ok "Admin consent ya existía para $($ResourceServicePrincipal.DisplayName) / $($AppRole.Value)"
        return $existing
    }

    $body = @{
        principalId = $ClientServicePrincipalId
        resourceId = $ResourceServicePrincipal.Id
        appRoleId = $AppRole.Id
    }

    $assignment = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientServicePrincipalId -BodyParameter $body

    Write-Ok "Admin consent concedido para $($ResourceServicePrincipal.DisplayName) / $($AppRole.Value)"

    return $assignment
}

function New-InMemorySelfSignedCertificate {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [int] $ValidMonths
    )

    $safeSubjectName = $Name -replace '[,=+<>#;"\\]', "_"

    $rsa = [System.Security.Cryptography.RSA]::Create(3072)
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=$safeSubjectName")

    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )

    $basicConstraints = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true)

    $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
        $true
    )

    $subjectKeyIdentifier = [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new(
        $request.PublicKey,
        $false
    )

    $request.CertificateExtensions.Add($basicConstraints)
    $request.CertificateExtensions.Add($keyUsage)
    $request.CertificateExtensions.Add($subjectKeyIdentifier)

    $now = [DateTimeOffset]::UtcNow

    $notBefore = $now.AddMinutes(-5)

    if ($ValidMonths -eq 12) {
        $notAfter = $now.AddDays(364)
    }
    else {
        $notAfter = $now.AddMonths($ValidMonths)
    }

    $certificate = $request.CreateSelfSigned($notBefore, $notAfter)

    $exportableCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx),
        "",
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )

    return [PSCustomObject]@{
        Certificate = $exportableCertificate
        NotBefore = $notBefore
        NotAfter = $notAfter
    }
}

function Add-CertificateToApplication {
    param(
        [Parameter(Mandatory)]
        [string] $ApplicationObjectId,

        [Parameter(Mandatory)]
        [string] $DisplayName,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate
    )

    $publicCertificateBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)

    $startDateTime = ConvertTo-GraphDateTimeString -DateTime $Certificate.NotBefore
    $endDateTime = ConvertTo-GraphDateTimeString -DateTime $Certificate.NotAfter.AddSeconds(-1)

    $bodyObject = @{
        keyCredentials = @(
            @{
                displayName = $DisplayName
                type = "AsymmetricX509Cert"
                usage = "Verify"
                key = [Convert]::ToBase64String($publicCertificateBytes)
                startDateTime = $startDateTime
                endDateTime = $endDateTime
            }
        )
    }

    $body = $bodyObject | ConvertTo-Json -Depth 10

    Write-Host "startDateTime enviado a Graph: $startDateTime"
    Write-Host "endDateTime enviado a Graph:   $endDateTime"

    Invoke-MgGraphRequest `
        -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/applications/$ApplicationObjectId" `
        -Body $body `
        -ContentType "application/json"

    Write-Ok "Certificado cargado en la App Registration"
}

function Add-OwnerReference {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("applications", "servicePrincipals")]
        [string] $ObjectType,

        [Parameter(Mandatory)]
        [string] $ObjectId,

        [Parameter(Mandatory)]
        [string] $OwnerDirectoryObjectId
    )

    $body = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$OwnerDirectoryObjectId"
    } | ConvertTo-Json

    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/$ObjectType/$ObjectId/owners/`$ref" -Body $body -ContentType "application/json"
        Write-Ok "Owner agregado en $ObjectType"
    }
    catch {
        if ($_.Exception.Message -match "added object references already exist") {
            Write-Ok "El owner ya existía en $ObjectType"
        }
        else {
            throw
        }
    }
}

Write-Step "Validando módulos Microsoft Graph"

Assert-GraphModule -Name "Microsoft.Graph.Authentication" -Commands @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Invoke-MgGraphRequest"
)

Assert-GraphModule -Name "Microsoft.Graph.Applications" -Commands @(
    "Get-MgApplication",
    "New-MgApplication",
    "Get-MgServicePrincipal",
    "New-MgServicePrincipal",
    "Get-MgServicePrincipalAppRoleAssignment",
    "New-MgServicePrincipalAppRoleAssignment"
)

Assert-GraphModule -Name "Microsoft.Graph.Sites" -Commands @(
    "New-MgSitePermission"
)

Write-Step "Validando parámetros"

$validatedSiteUri = Get-ValidatedSharePointSiteUrl -Url $SiteUrl
$normalizedSitePermission = $SitePermission.ToLowerInvariant()
$safeFileName = Get-SafeFileName -Name $AppName

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$pfxPath = Join-Path $OutputPath "$safeFileName.pfx"
$instructionsPath = Join-Path $OutputPath "$safeFileName-instrucciones.txt"

if (Test-Path $pfxPath) {
    throw "Ya existe el archivo PFX de salida: $pfxPath"
}

Write-Ok "URL validada: $($validatedSiteUri.AbsoluteUri)"
Write-Ok "Permiso solicitado para el sitio: $normalizedSitePermission"

Write-Step "Conectando a Microsoft Graph"

$requiredScopes = @(
    "Application.ReadWrite.All",
    "AppRoleAssignment.ReadWrite.All",
    "Directory.Read.All",
    "Sites.FullControl.All",
    "User.Read"
)

Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -NoWelcome

$context = Get-MgContext

if (-not $context) {
    throw "No se pudo obtener el contexto de Microsoft Graph."
}

$effectiveTenantId = $context.TenantId

Write-Ok "Conectado al tenant $effectiveTenantId con la cuenta $($context.Account)"

Write-Step "Obteniendo usuario ejecutor"

$me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me?`$select=id,displayName,userPrincipalName"

if (-not $me.id) {
    throw "No se pudo resolver el usuario ejecutor con /me."
}

Write-Ok "Usuario ejecutor: $($me.userPrincipalName)"

Write-Step "Resolviendo service principals de Microsoft Graph y SharePoint"

$graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphResourceAppId'" -Property "id,appId,displayName,appRoles" | Select-Object -First 1
$sharePointSp = Get-MgServicePrincipal -Filter "appId eq '$SharePointResourceAppId'" -Property "id,appId,displayName,appRoles" | Select-Object -First 1

if (-not $graphSp) {
    throw "No se encontró el service principal de Microsoft Graph."
}

if (-not $sharePointSp) {
    throw "No se encontró el service principal de SharePoint Online. Validá que el tenant tenga SharePoint Online provisionado."
}

$graphSitesSelectedRole = Get-ApplicationAppRole -ResourceServicePrincipal $graphSp -Value $RequiredPermissionValue
$sharePointSitesSelectedRole = Get-ApplicationAppRole -ResourceServicePrincipal $sharePointSp -Value $RequiredPermissionValue

Write-Ok "Microsoft Graph / Sites.Selected: $($graphSitesSelectedRole.Id)"
Write-Ok "SharePoint / Sites.Selected: $($sharePointSitesSelectedRole.Id)"

Write-Step "Validando duplicados de App Registration"

$escapedAppName = Escape-ODataString -Value $AppName
$existingApps = Get-MgApplication -Filter "displayName eq '$escapedAppName'" -Property "id,appId,displayName" -All

if ($existingApps -and -not $AllowDuplicateDisplayName) {
    $existingList = $existingApps | ForEach-Object { "$($_.DisplayName) / ClientId: $($_.AppId) / ObjectId: $($_.Id)" }
    throw "Ya existe una App Registration con DisplayName '$AppName'. Usá otro nombre o ejecutá con -AllowDuplicateDisplayName. Existentes: $($existingList -join " | ")"
}

Write-Step "Creando App Registration"

$requiredResourceAccess = @(
    @{
        resourceAppId = $GraphResourceAppId
        resourceAccess = @(
            @{
                id = $graphSitesSelectedRole.Id
                type = "Role"
            }
        )
    },
    @{
        resourceAppId = $SharePointResourceAppId
        resourceAccess = @(
            @{
                id = $sharePointSitesSelectedRole.Id
                type = "Role"
            }
        )
    }
)

$appBody = @{
    displayName = $AppName
    signInAudience = "AzureADMyOrg"
    requiredResourceAccess = $requiredResourceAccess
}

$app = New-MgApplication -BodyParameter $appBody

Write-Ok "App Registration creada"
Write-Ok "ClientId: $($app.AppId)"
Write-Ok "Application ObjectId: $($app.Id)"

Write-Step "Creando Enterprise Application / Service Principal"

$clientSp = New-MgServicePrincipal -AppId $app.AppId

Write-Ok "Service Principal creado"
Write-Ok "Service Principal ObjectId: $($clientSp.Id)"

Write-Step "Asignando owner"

Add-OwnerReference -ObjectType "applications" -ObjectId $app.Id -OwnerDirectoryObjectId $me.id
Add-OwnerReference -ObjectType "servicePrincipals" -ObjectId $clientSp.Id -OwnerDirectoryObjectId $me.id

Write-Step "Concediendo Admin Consent a Sites.Selected"

Ensure-AppRoleAssignment -ClientServicePrincipalId $clientSp.Id -ResourceServicePrincipal $graphSp -AppRole $graphSitesSelectedRole | Out-Null
Ensure-AppRoleAssignment -ClientServicePrincipalId $clientSp.Id -ResourceServicePrincipal $sharePointSp -AppRole $sharePointSitesSelectedRole | Out-Null

Write-Step "Generando certificado autofirmado en memoria"

$certificateInfo = New-InMemorySelfSignedCertificate -Name $AppName -ValidMonths $CertificateValidMonths
$certificate = $certificateInfo.Certificate
$notBefore = $certificateInfo.NotBefore
$notAfter = $certificateInfo.NotAfter

Write-Ok "Certificado generado"
Write-Ok "Thumbprint: $($certificate.Thumbprint)"
Write-Ok "Vence UTC: $($notAfter.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ"))"

Write-Step "Cargando certificado público en la App Registration"

Add-CertificateToApplication -ApplicationObjectId $app.Id -DisplayName $AppName -Certificate $certificate

Write-Step "Solicitando contraseña para exportar PFX"

$pfxPassword = Read-Host "Contraseña para el PFX" -AsSecureString
$pfxPasswordConfirm = Read-Host "Confirmar contraseña para el PFX" -AsSecureString

$pfxPasswordPlain = Get-PlainTextFromSecureString -SecureString $pfxPassword
$pfxPasswordConfirmPlain = Get-PlainTextFromSecureString -SecureString $pfxPasswordConfirm

if ($pfxPasswordPlain -ne $pfxPasswordConfirmPlain) {
    throw "Las contraseñas del PFX no coinciden."
}

Write-Step "Exportando certificado PFX"

$pfxBytes = $certificate.Export(
    [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
    $pfxPasswordPlain
)

[IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

Write-Ok "PFX exportado: $pfxPath"

Write-Step "Resolviendo sitio de SharePoint"

$site = Get-GraphSiteFromUrl -ValidatedSiteUri $validatedSiteUri

if (-not $site.id) {
    throw "Microsoft Graph respondió, pero no devolvió SiteId."
}

Write-Ok "Sitio resuelto"
Write-Ok "SiteId: $($site.id)"
Write-Ok "WebUrl: $($site.webUrl)"

Write-Step "Otorgando permiso granular al sitio"

$sitePermissionBody = @{
    roles = @(
        $normalizedSitePermission
    )
    grantedToIdentities = @(
        @{
            application = @{
                id = $app.AppId
                displayName = $AppName
            }
        }
    )
}

$sitePermissionResult = New-MgSitePermission -SiteId $site.id -BodyParameter $sitePermissionBody

Write-Ok "Permiso otorgado al sitio"
Write-Ok "PermissionId: $($sitePermissionResult.Id)"

Write-Step "Generando archivo de instrucciones"

$instructions = @"
App Registration creada para acceso restringido a SharePoint mediante Sites.Selected

Tenant Id:
$effectiveTenantId

Application / Client ID:
$($app.AppId)

Application Object ID:
$($app.Id)

Enterprise Application / Service Principal Object ID:
$($clientSp.Id)

Nombre de la aplicación:
$AppName

Owner asignado:
$($me.displayName) <$($me.userPrincipalName)>

Sitio autorizado:
$($site.webUrl)

Site ID:
$($site.id)

Permiso otorgado al sitio:
$normalizedSitePermission

API permissions concedidos con Admin Consent:
- Microsoft Graph: Sites.Selected / Application
- SharePoint: Sites.Selected / Application

Certificado:
- Nombre: $AppName
- Thumbprint: $($certificate.Thumbprint)
- Válido desde UTC: $($notBefore.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ"))
- Vence UTC: $($notAfter.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ"))
- PFX: $pfxPath

Uso por parte del desarrollador:
- Para Microsoft Graph, solicitar token para https://graph.microsoft.com/.default
- Para SharePoint REST, solicitar token para el recurso SharePoint correspondiente, por ejemplo https://$($validatedSiteUri.Host)/.default
- Autenticación: client credentials con certificado, usando Tenant Id, Client Id y el PFX exportado.

No se creó client secret.
No se otorgaron permisos tenant-wide como Sites.Read.All, Sites.ReadWrite.All ni Sites.FullControl.All a la aplicación creada.
"@

Set-Content -Path $instructionsPath -Value $instructions -Encoding UTF8

Write-Ok "Instrucciones generadas: $instructionsPath"

Write-Host ""
Write-Host "FINALIZADO" -ForegroundColor Green
Write-Host "Tenant Id: $effectiveTenantId"
Write-Host "Client Id: $($app.AppId)"
Write-Host "PFX: $pfxPath"
Write-Host "Vence UTC: $($notAfter.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ"))"
Write-Host "Validez efectiva: menor o igual a 1 año, compatible con Microsoft Graph keyCredentials"
Write-Host "Instrucciones: $instructionsPath"