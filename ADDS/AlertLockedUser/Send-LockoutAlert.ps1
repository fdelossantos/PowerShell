[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [string]$ConfigFile
)

# Preparar Event Log
$EventSource = 'LockoutAlert'
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
}


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
    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 3000 -Message "Inicio de script. Config file: $ConfigFile"
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
        $body = "<p>Error autenticando a Graph: $_</p>"
        Send-GraphMail -Subject 'Resultado de revisión de cuentas' -BodyHtml $body
        Exit 3
    }

    # Último 4740
    $evt = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740} -MaxEvents 1
    $xml = [xml]$evt.ToXml()

    $targetUser = ($xml.Event.EventData.Data | Where {$_.Name -eq 'TargetUserName'}).'#text'
    $caller     = ($xml.Event.EventData.Data | Where {$_.Name -eq 'CallerComputerName'}).'#text'
    $dc         = $env:COMPUTERNAME

    $datos = @{Account = $targetUser
               DC      = $dc
               Caller  = $caller
               When    = $($evt.TimeCreated)
            }

    $body = "<h2>Usuario bloqueado en STL</h2>"
    $body += $datos | ConvertTo-Html -Fragment -Property Account,DC,Caller,When | Out-String

    Send-GraphMail -Subject 'Bloqueo de cuenta en STL' -BodyHtml $body
}

