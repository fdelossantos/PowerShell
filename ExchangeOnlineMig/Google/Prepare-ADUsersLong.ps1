<# 
.SYNOPSIS
  Procesa una lista de correos (TXT) y actualiza usuarios en AD + limpia MailContacts en Exchange Online.

.PARAMETER InputFile
  Ruta del .txt con una única columna de direcciones de email (una por línea).

.PARAMETER AdServer
  Controlador/servidor de AD al que se enviarán todas las operaciones (-Server).

.PARAMETER AppId
  Application (client) ID de la App Registration usada para Exchange Online.

.PARAMETER Organization
  Nombre de tenant/organizational domain (por ejemplo: contoso.onmicrosoft.com).

.PARAMETER CertThumbprint
  Huella digital del certificado instalado en el equipo que ejecuta el script.

.PARAMETER OutputNotFoundFile
  Archivo de salida para emails no encontrados en AD (opcional). Si se omite, se genera junto al InputFile con un sufijo.

.EXAMPLE
  .\Procesar-Emails.ps1 -InputFile .\emails.txt -AdServer DC01.miempresa.local -AppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Organization "contoso.onmicrosoft.com" -CertThumbprint "A1B2C3D4E5..." -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$AdServer,

    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$CertThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$OutputNotFoundFile
)

# Carga de módulos
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module ExchangeOnlineManagement -ErrorAction Stop

# Funciones auxiliares
function New-DomainWithSubdomain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,
        [Parameter(Mandatory = $true)]
        [ValidateSet('o365','gsuite')]
        [string]$Subdomain
    )
    # user@domain.tld -> user@<subdomain>.domain.tld
    $parts = $Email.Split('@')
    if ($parts.Count -ne 2) {
        return $Email
    }
    $local = $parts[0]
    $domain = $parts[1]
    $newDomain = "$Subdomain.$domain"
    "$local@$newDomain"
}

function Ensure-ProxyAddresses {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$AdUser,
        [Parameter(Mandatory = $true)]
        [string]$PrimarySmtpAddress,
        [Parameter(Mandatory = $true)]
        [string]$SecondarySmtpAddress,
        [Parameter(Mandatory = $true)]
        [string]$AdServer
    )
    # proxyAddresses: la primaria es "SMTP:direccion" (SMTP en mayúsculas).
    # Las secundarias son "smtp:direccion" (smtp en minúsculas).
    $current = @()
    if ($AdUser.proxyAddresses) {
        $current = @($AdUser.proxyAddresses)
    }

    # Quitar cualquier primaria existente
    $withoutPrimary = @()
    foreach ($addr in $current) {
        if ($addr -notlike 'SMTP:*') {
            $withoutPrimary += $addr
        }
    }

    # Construir el set destino
    $targetSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($addr in $withoutPrimary) {
        $null = $targetSet.Add($addr)
    }

    $primaryValue = "SMTP:$PrimarySmtpAddress"
    $secondaryValue = "smtp:$SecondarySmtpAddress"

    $null = $targetSet.Add($primaryValue)
    $null = $targetSet.Add($secondaryValue)

    $final = @()
    foreach ($addr in $targetSet) {
        $final += $addr
    }

    Set-ADUser -Identity $AdUser.DistinguishedName -Replace @{ proxyAddresses = $final } -Server $AdServer
}

function Ensure-Attribute {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dn,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string]$AdServer
    )
    $hash = @{}
    $hash[$Name] = $Value
    Set-ADUser -Identity $Dn -Replace $hash -Server $AdServer
}

function Try-Remove-MailContact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email
    )
    try {
        # Buscamos coincidencias por PrimarySmtpAddress, ExternalEmailAddress o WindowsEmailAddress
        $found = $null
        $filter = "((PrimarySmtpAddress -eq '$Email') -or (ExternalEmailAddress -eq '$Email') -or (WindowsEmailAddress -eq '$Email'))"
        $found = Get-Recipient -RecipientTypeDetails MailContact -Filter $filter -ErrorAction Stop

        if ($found) {
            foreach ($c in $found) {
                try {
                    Remove-MailContact -Identity $c.Identity -Confirm:$false -ErrorAction Stop
                    Write-Verbose "MailContact eliminado: $($c.Identity)"
                }
                catch {
                    Write-Warning "No se pudo eliminar el MailContact $($c.Identity): $_"
                }
            }
        }
    }
    catch {
        # Si no hay, no es problema
        Write-Verbose "No se encontró MailContact para $Email o no se pudo consultar. Detalle: $_"
    }
}

# Preparar entrada/salida
$emails = Get-Content -Path $InputFile | Where-Object { $_ -and $_.Trim().Length -gt 0 }
$emails = $emails | ForEach-Object { $_.Trim() }

if (-not $emails -or $emails.Count -eq 0) {
    Write-Warning "El archivo $InputFile no contiene emails válidos."
    return
}

if (-not $OutputNotFoundFile -or [string]::IsNullOrWhiteSpace($OutputNotFoundFile)) {
    $dir = Split-Path -Path $InputFile -Parent
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputNotFoundFile = Join-Path $dir "$base-NotFound-$stamp.txt"
}

# Conexión a Exchange Online (App Registration + Cert)
Connect-ExchangeOnline -AppId $AppId -Organization $Organization -CertificateThumbprint $CertThumbprint -ShowBanner:$false -ErrorAction Stop

# Contadores y acumuladores
$total = $emails.Count
$index = 0
$notFound = New-Object System.Collections.Generic.List[string]
$processed = 0

# Proceso principal
foreach ($email in $emails) {
    $index = $index + 1

    $status = "Procesando $index de $total | No encontrados: $($notFound.Count)"
    Write-Progress -Activity "Actualizando AD y EXO" -Status $status -PercentComplete ([int](($index / $total) * 100)) -CurrentOperation $email

    # Buscar en AD por UPN
    $adUser = $null
    try {
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$email'" -Server $AdServer -Properties mail, proxyAddresses, targetAddress, mailNickname
    }
    catch {
        Write-Warning "Error consultando AD para $email en $($AdServer): $_"
        $notFound.Add($email) | Out-Null
        continue
    }

    if (-not $adUser) {
        $notFound.Add($email) | Out-Null
        continue
    }

    # 3) mail si está vacío
    if ([string]::IsNullOrWhiteSpace($adUser.mail)) {
        try {
            Ensure-Attribute -Dn $adUser.DistinguishedName -Name 'mail' -Value $email -AdServer $AdServer
        }
        catch {
            Write-Warning "No se pudo establecer 'mail' para $($email): $_"
        }
    }

    # 4) proxyAddresses: primaria con el email, secundaria con subdominio 'o365'
    $secondaryEmail = New-DomainWithSubdomain -Email $email -Subdomain 'o365'
    try {
        Ensure-ProxyAddresses -AdUser $adUser -PrimarySmtpAddress $email -SecondarySmtpAddress $secondaryEmail -AdServer $AdServer
    }
    catch {
        Write-Warning "No se pudieron establecer proxyAddresses para $($email): $_"
    }

    # 5) targetAddress con subdominio 'gsuite'
    $targetEmail = New-DomainWithSubdomain -Email $email -Subdomain 'gsuite'
    try {
        # targetAddress suele aceptar "SMTP:..." como valor
        Ensure-Attribute -Dn $adUser.DistinguishedName -Name 'targetAddress' -Value ("SMTP:" + $targetEmail) -AdServer $AdServer
    }
    catch {
        Write-Warning "No se pudo establecer 'targetAddress' para $($email): $_"
    }

    # 6) mailNickname = email con arroba -> guion bajo
    $nick = $email.Replace('@', '_')
    try {
        Ensure-Attribute -Dn $adUser.DistinguishedName -Name 'mailNickname' -Value $nick -AdServer $AdServer
    }
    catch {
        Write-Warning "No se pudo establecer 'mailNickname' para $($email): $_"
    }

    # 7) Conectado a EXO: eliminar MailContact que coincida
    Try-Remove-MailContact -Email $email

    $processed = $processed + 1
}

# Progreso final al 100%
Write-Progress -Activity "Actualizando AD y EXO" -Status "Completado. Procesados: $processed | No encontrados: $($notFound.Count) | Total: $total" -PercentComplete 100

# Guardar no encontrados
if ($notFound.Count -gt 0) {
    try {
        $notFound | Set-Content -Path $OutputNotFoundFile -Encoding UTF8
        Write-Host "Emails no encontrados: $($notFound.Count). Archivo: $OutputNotFoundFile"
    }
    catch {
        Write-Warning "No se pudo escribir el archivo de no encontrados: $_"
    }
}
else {
    Write-Host "Todos los emails del archivo tuvieron coincidencia en AD."
}

# Cerrar sesión de EXO
try {
    Disconnect-ExchangeOnline -Confirm:$false
}
catch {
    Write-Verbose "No se pudo cerrar la sesión de Exchange Online limpiamente. $_"
}
