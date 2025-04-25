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
Param(
    [Parameter(Mandatory)]
    [string]$ConfigFile
)

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
Try {
    $configs = Get-Content -Raw $ConfigFile | ConvertFrom-Json -ErrorAction Stop
} Catch {
    Write-Error "Error cargando archivo de configuración: $_"
    Exit 1
}

# Fuente para eventos en el log de Aplicación
$EventSource = 'AccountInactivityMonitor'
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
    Exit 2
}

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Users.Actions -ErrorAction Stop

foreach ($config in $configs) {
    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3000 -Message "Inicio de script. Config: $ConfigFile"

    # Parámetros de negocio
    $alertDays   = $config.AlertLeftDays
    $disableDays = $config.DisableMaxDays
    $ous         = $config.OU

    # Parámetros de Graph
    $tenantId        = $config.TenantId
    $clientId        = $config.ClientId
    $encryptedSecret = $config.ClientSecret
    $emailFrom       = $config.EmailFrom
    $recipients      = $config.Emails

                # Autenticación con App Registration usando PSCredential
    Try {
        $clientSecretVal = Decrypt-String $encryptedSecret
        $secureSecret    = ConvertTo-SecureString $clientSecretVal -AsPlainText -Force
        $credential      = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)

        Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -ErrorAction Stop -NoWelcome
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3001 -Message "Conectado a Microsoft Graph con PSCredential."
    } Catch {
        Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 3002 -Message "Error autenticando a Graph: $_"
        Exit 3
    }

    # Obtención de usuarios habilitados
    $allUsers = @()
    foreach ($ou in $ous) {
        Try {
            $users = Get-ADUser -Filter * -SearchBase $ou -Properties LastLogonDate,Enabled |
                     Where-Object { $_.Enabled -eq $true }
            $allUsers += $users
        } Catch {
            Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 3003 -Message "Error consultando OU $($ou): $_"
            Exit 4
        }
    }
    $checkedCount = $allUsers.Count

    # Clasificación de usuarios
    $aboutToDisable = @()
    $toDisable      = @()
    $now            = Get-Date
    foreach ($user in $allUsers) {
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
    }

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

    # 2) Alerta de próximos a deshabilitarse
    if ($aboutToDisable.Count -gt 0) {
        $body = "<h2>Usuarios con inactividad en $alertDays días o menos hasta $disableDays días</h2>"
        $body += $aboutToDisable | ConvertTo-Html -Fragment -Property SamAccountName,DisplayName,LastLogonDate,DaysUntilDisable
        Send-GraphMail -Subject 'Alerta de inactividad de cuenta' -BodyHtml $body
    }

    # 3) Deshabilitación por inactividad
    if ($toDisable.Count -gt 0) {
        foreach ($u in $toDisable) {
            Try { Disable-ADAccount -Identity $u.SamAccountName -ErrorAction Stop } Catch {}
            Write-EventLog -LogName Application -Source $EventSource -EntryType Warning -EventId 3006 -Message "Deshabilitado $($u.SamAccountName)."
        }
        $body2 = "<h2>Usuarios deshabilitados por superar $disableDays días de inactividad</h2>"
        $body2 += $toDisable | ConvertTo-Html -Fragment -Property SamAccountName,DisplayName,LastLogonDate,InactivityDays
        Send-GraphMail -Subject 'Reporte de usuarios deshabilitados por inactividad' -BodyHtml $body2
    }

    # 4) Sin deshabilitaciones
    if ($toDisable.Count -eq 0) {
        $body3 = "<p>No se encontraron usuarios para deshabilitar por inactividad. Usuarios revisados: $checkedCount.</p>"
        Send-GraphMail -Subject 'Resultado revisión inactividad de cuentas' -BodyHtml $body3
    }

    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3007 -Message "Fin de script. Revisados: $checkedCount usuarios."
}
