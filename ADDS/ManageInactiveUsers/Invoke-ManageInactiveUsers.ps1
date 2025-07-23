<#
.SYNOPSIS
    Monitoreo de inactividad de cuentas de Active Directory y envío de reportes.

.DESCRIPTION
    Este script evalúa usuarios en las OU especificadas en un archivo de configuración JSON,
    alerta por correo HTML vía Microsoft Graph a los que están próximos a ser deshabilitados
    por inactividad, deshabilita los que superan el umbral configurado y registra eventos en
    el log de Aplicación de Windows.

.PARAMETER ConfigFile
    Ruta completa al archivo JSON de configuración con las siguientes propiedades:
    - OU: lista de distinguished names de las OUs a revisar.
    - Emails: lista de direcciones de correo para reportes.
    - AlertLeftDays: días antes de la deshabilitación para enviar alerta.
    - DisableMaxDays: días de inactividad tras los cuales se deshabilita la cuenta.
    - TenantId: ID del tenant de Microsoft 365.
    - ClientId: ID de la App Registration para Graph.
    - ClientSecret: secreto cifrado (base64 DPAPI) de la App.
    - EmailFrom: UPN o buzón desde el cual se envían los mensajes.

.NOTES
    - Ejecútese en un Domain Controller con privilegios de administrador de cuentas.
    - El módulo Microsoft.Graph debe estar instalado (Authentication, Users, Users.Actions).
    - Para cifrar el ClientSecret use la función Encrypt-String incluida.
    - Registra eventos bajo la fuente 'AccountInactivityMonitor' en el log de Aplicación.

.EXAMPLE
    # Encryptar el secreto una sola vez:
    $encrypted = Encrypt-String -PlainText 'MiSecretoSMTP'
    # NOTA: la encriptación está temporalmente deshabilitada y se carga en texto plano.

    # Ejecutar el script:
    .\Invoke-ManageInactiveUsers.ps1 -ConfigFile C:\Scripts\config.json

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
$EventSource = 'AccountInactivityMonitor'
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
    if ($PSBoundParameters['Debug']) { Debug-Log "Fuente de evento '$EventSource' creada. " }
} elseif ($PSBoundParameters['Debug']) { Debug-Log "Fuente de evento '$EventSource' ya existe." }

# Importar módulos necesarios
Import-Module ActiveDirectory -ErrorAction Stop; if ($PSBoundParameters['Debug']) { Debug-Log "ActiveDirectory módulo importado." }
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop; if ($PSBoundParameters['Debug']) { Debug-Log "Microsoft.Graph.Authentication módulo importado." }
Import-Module Microsoft.Graph.Users -ErrorAction Stop; if ($PSBoundParameters['Debug']) { Debug-Log "Microsoft.Graph.Users módulo importado." }
Import-Module Microsoft.Graph.Users.Actions -ErrorAction Stop; if ($PSBoundParameters['Debug']) { Debug-Log "Microsoft.Graph.Users.Actions módulo importado." }

foreach ($config in $configs) {
    if ($PSBoundParameters['Debug']) { Debug-Log "Procesando configuración de OU y correo." }
    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3000 -Message "Inicio de script. Config file: $ConfigFile"

    # Parámetros de negocio
    $alertDays   = $config.AlertLeftDays
    $disableDays = $config.DisableMaxDays
    $expireDays  = $config.AccountExpireLeftDays
    $ous         = $config.OU
    if ($PSBoundParameters['Debug']) { Debug-Log "AlertLeftDays=$alertDays, DisableMaxDays=$disableDays, AccountExpireLeftDays=$expireDays" }

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

    # Obtención de usuarios habilitados
    $allUsers = @()
    foreach ($ou in $ous) {
        Try {
            if ($PSBoundParameters['Debug']) { Debug-Log "Consultando OU: $ou" }
            $users = Get-ADUser -Filter * -SearchBase $ou -Properties LastLogonDate,Enabled,AccountExpirationDate |
                     Where-Object { $_.Enabled -eq $true }
            $allUsers += $users
            if ($PSBoundParameters['Debug']) { Debug-Log "Usuarios obtenidos de $($ou): $($users.Count)" }
        } Catch {
            Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 3003 -Message "Error consultando OU $($ou): $_"
            if ($PSBoundParameters['Debug']) { Debug-Log "Error consultando OU $($ou): $_" }
            $body = "<p>Error consultando OU $($ou): $_</p>"
            Send-GraphMail -Subject 'Resultado de revisión de cuentas' -BodyHtml $body
	        Exit 4
        }
    }
    $checkedCount = $allUsers.Count
    if ($PSBoundParameters['Debug']) { Debug-Log "Total usuarios revisados: $checkedCount" }

    # Clasificar según inactividad y expiración
    $now = Get-Date
    $aboutToDisable = @()
    $toDisable      = @()
    $expiringAccounts = @()
    $now            = Get-Date
    foreach ($user in $allUsers) {
        # Inactividad
        $inactivityDays   = if ($user.LastLogonDate) { ($now - $user.LastLogonDate).TotalDays } else { $disableDays + 1 }
        $daysUntilDisable = $disableDays - $inactivityDays

        if ($daysUntilDisable -le $alertDays -and $daysUntilDisable -ge 0) {
            $aboutToDisable += [PSCustomObject]@{
                SamAccountName   = $user.SamAccountName
                DisplayName      = $user.Name
                LastLogonDate    = $user.LastLogonDate
                DaysUntilDisable = [math]::Round($daysUntilDisable,2)
            }
        } elseif ($inactivityDays -gt $disableDays) {
            $toDisable += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName    = $user.Name
                LastLogonDate  = $user.LastLogonDate
                InactivityDays = [math]::Round($inactivityDays,2)
            }
        }
	# Expiración de cuenta
        if ($user.AccountExpirationDate) {
            $expDate = $user.AccountExpirationDate.Date
            $daysToExpire = ($expDate - $now.Date).TotalDays
            if ($daysToExpire -le $expireDays -and $daysToExpire -ge 0) {
                $expiringAccounts += [PSCustomObject]@{
                    UserPrincipalName = $user.UserPrincipalName
                    SamAccountName    = $user.SamAccountName
                    Name              = $user.Name
                    ExpirationDate    = $expDate.ToString('yyyy-MM-dd')
                }
            }
        }
    }
    if ($PSBoundParameters['Debug']) { Debug-Log "Próximos a deshabilitar: $($aboutToDisable.Count), a deshabilitar: $($toDisable.Count), a expirar: $($expiringAccounts.Count)" }

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
    
    # 2) Alerta inactividad
    if ($aboutToDisable.Count -gt 0) {
        $body = "<h2>Usuarios con inactividad en $alertDays días o menos hasta $disableDays días</h2>"
        $body += $aboutToDisable | ConvertTo-Html -Fragment -Property SamAccountName,Name,LastLogonDate | Out-String
        Send-GraphMail -Subject 'Alerta de inactividad de cuenta' -BodyHtml $body
    }

    # 3) Deshabilitación
    if ($toDisable.Count -gt 0) {
        $toDisable | ForEach-Object { Disable-ADAccount -Identity $_.SamAccountName }
        $body2 = "<h2>Reporte de deshabilitados por inactividad</h2>"
        $body2 += $toDisable | ConvertTo-Html -Fragment -Property SamAccountName,Name,LastLogonDate | Out-String
        Send-GraphMail -Subject 'Reporte de deshabilitados por inactividad' -BodyHtml $body2
    }

    # 5) Alerta expiración de cuenta
    if ($expiringAccounts.Count -gt 0) {
        $body3 = "<h2>Cuentas expirando en menos de $expireDays días</h2>"
        $body3 += $expiringAccounts | ConvertTo-Html -Fragment -Property UserPrincipalName,SamAccountName,Name,ExpirationDate | Out-String
        Send-GraphMail -Subject 'Alerta de expiración de cuentas' -BodyHtml $body3
    }

    # 6) Reporte sin deshabilitaciones ni expiraciones
    if ($aboutToDisable.Count -eq 0 -and $toDisable.Count -eq 0 -and $expiringAccounts.Count -eq 0) {
        $body4 = "<p>No hay cambios. Usuarios revisados: $checkedCount.</p>"
        Send-GraphMail -Subject 'Resultado de revisión de cuentas' -BodyHtml $body4
    }

    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3007 -Message "Fin de script. Revisados: $checkedCount usuarios."
    if ($PSBoundParameters['Debug']) { Debug-Log "Fin de procesamiento de configuración." }
}
if ($PSBoundParameters['Debug']) { Debug-Log "Script completado." }
