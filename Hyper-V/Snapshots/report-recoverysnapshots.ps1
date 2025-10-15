<#
.SYNOPSIS
    Monitoreo de Presencia de snapshots tipo Recovery.

.DESCRIPTION
    Este script...

.PARAMETER ConfigFile
    

.NOTES
    - Ejecútese en un Hyper-V con privilegios de administrador de cuentas.
    - El módulo Microsoft.Graph debe estar instalado (Authentication, Users, Users.Actions).
    - Para cifrar el ClientSecret use la función Encrypt-String incluida.
    - Registra eventos bajo la fuente '...' en el log de Aplicación.

.EXAMPLE
    # Encryptar el secreto una sola vez:
    $encrypted = Encrypt-String -PlainText 'MiSecretoSMTP'

    # Ejecutar el script:
    .\report-rec....ps1 -ConfigFile C:\Scripts\config.json

#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [string]$ConfigFile
)

# Inicialización de debug si corresponde
if ($PSBoundParameters['Debug']) {
    $scriptName = $MyInvocation.MyCommand.Name
    $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile    = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "${timestamp}_$scriptName.log"
    "================ Debug log started at $(Get-Date) ================" | Out-File -FilePath $logFile
    function Debug-Log { param($msg) 
        $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "${time} [DEBUG] $msg" | Out-File -FilePath $logFile -Append
    }
    Debug-Log "Debug mode enabled. Log file: $logFile"
}

# Funciones de cifrado reversible usando DPAPI
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

# Carga de configuración
if ($PSBoundParameters['Debug']) { Debug-Log "Cargando archivo de configuración: $ConfigFile" }
Try {
    $configs = Get-Content -Raw $ConfigFile | ConvertFrom-Json -ErrorAction Stop
    if ($PSBoundParameters['Debug']) { Debug-Log "Configuración cargada: $($configs | ConvertTo-Json -Compress)" }
} Catch {
    Write-Error "Error cargando archivo de configuración: $_"
    if ($PSBoundParameters['Debug']) { Debug-Log "Error cargando configuración: $_" }
    Exit 1
}

# Preparar Event Log
$EventSource = 'VMRecoverySnapshotsMonitor'
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
    if ($PSBoundParameters['Debug']) { Debug-Log "Fuente de evento '$EventSource' creada. " }
} elseif ($PSBoundParameters['Debug']) { Debug-Log "Fuente de evento '$EventSource' ya existe." }

    # Función para enviar correo vía Graph
function Send-GraphMail {
    Param(
        [string]$Subject,
        [string]$BodyHtml
    )

    # Construir parámetros según ejemplo Send-MgUserMail -BodyParameter
    $torec = $recipients | ForEach-Object { 
                @{ emailAddress = @{ address = $_ } }
            }
    $params = @{ 
        message = @{ 
            subject      = "$Subject"
            body         = @{ contentType = 'HTML'
                                content = "$BodyHtml" }
            toRecipients = @(
                                $torec
                            )
        }
    }
    Try {
        Send-MgUserMail -UserId $emailFrom -BodyParameter $params -ErrorAction Stop
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3004 -Message "Correo enviado: $Subject"
    } Catch {
        Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 3005 -Message "Error enviando correo Graph: $_"
        Exit 5
    }
}

foreach ($config in $configs) {
    if ($PSBoundParameters['Debug']) { Debug-Log "Procesando configuración de OU y correo." }
    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3000 -Message "Inicio de script. Config file: $ConfigFile"

    # Parámetros de negocio
    $Servers         = $config.Servers
    if ($PSBoundParameters['Debug']) { Debug-Log "Servers=$($recipients -join ',')" }

    # Parámetros de Graph
    $tenantId        = $config.TenantId
    $clientId        = $config.ClientId
    $encryptedSecret = $config.ClientSecret
    $emailFrom       = $config.EmailFrom
    $recipients      = $config.Emails
    if ($PSBoundParameters['Debug']) { Debug-Log "TenantId=$tenantId, ClientId=$clientId, EmailFrom=$emailFrom, Recipients=$($recipients -join ',')" }

    # Autenticación con App Registration usando PSCredential
    Try {
        if ($PSBoundParameters['Debug']) { Debug-Log "Desencriptando ClientSecret." }
        $clientSecretVal = Decrypt-String $encryptedSecret
        $secureSecret    = ConvertTo-SecureString $clientSecretVal -AsPlainText -Force
        $credential      = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)
        if ($PSBoundParameters['Debug']) { Debug-Log "PSCredential creado." }

        Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -ErrorAction Stop -NoWelcome
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3001 -Message "Conectado a Microsoft Graph con PSCredential."
        if ($PSBoundParameters['Debug']) { Debug-Log "Autenticación Graph exitosa." }
    } Catch {
        Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 3002 -Message "Error autenticando a Graph: $_"
        if ($PSBoundParameters['Debug']) { Debug-Log "Falló autenticación Graph: $_" }
        $body = "<p>Error autenticando a Graph: $_</p>"
        Send-GraphMail -Subject 'Resultado de revisión de cuentas' -BodyHtml $body
        Exit 3
    }

    $resultados = @()
    $Servers | foreach { $resultados += Get-VM -ComputerName $_ | Get-VMSnapshot | where {$_.Snapshottype -eq "Recovery"} }

    # Crear una tabla HTML con $resultados
    $htmlTable = $resultados | Select-Object VMName, SnapshotType, CreationTime | ConvertTo-Html -Fragment -Property VMName, SnapshotType, CreationTime | Out-String

   
    # Alerta de snapshots tipo Recovery
    if ($resultados.Count -gt 0) {
        $body = "<h2>Se encontraron los siguientes snapshots de tipo Recovery:</h2>"
        $body += $htmlTable
        Send-GraphMail -Subject 'Alerta de Snapshots tipo Recovery' -BodyHtml $body
    }

    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3007 -Message "Fin de script. Revisados: $checkedCount usuarios."
    if ($PSBoundParameters['Debug']) { Debug-Log "Fin de procesamiento de configuración." }
}
if ($PSBoundParameters['Debug']) { Debug-Log "Script completado." }
