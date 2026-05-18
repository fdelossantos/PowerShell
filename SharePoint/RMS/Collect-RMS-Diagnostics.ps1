# Collect-RMS-Diagnostics.ps1
# Relevamiento desatendido de configuración AD RMS / IIS / autenticación

param(
    [Parameter(Mandatory = $true)]
    [string]$RmsAliasShortName,

    [Parameter(Mandatory = $true)]
    [string]$RmsAliasFqdn,

    [Parameter(Mandatory = $true)]
    [string]$RmsPhysicalShortName,

    [Parameter(Mandatory = $true)]
    [string]$RmsPhysicalFqdn,

    [Parameter(Mandatory = $true)]
    [string]$AdDomainFqdn,

    [Parameter(Mandatory = $true)]
    [string]$RmsComputerAccount
)

$ErrorActionPreference = "Continue"

$scriptPath = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    $scriptPath = Split-Path `
        -Parent `
        -Path $MyInvocation.MyCommand.Path
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$outputFile = Join-Path `
    -Path $scriptPath `
    -ChildPath "RMS-Diagnostics-$env:COMPUTERNAME-$timestamp.txt"

$securityEventsFile = Join-Path `
    -Path $scriptPath `
    -ChildPath "RMS-Security-4625-$env:COMPUTERNAME-$timestamp.csv"

$iisLogExtractFile = Join-Path `
    -Path $scriptPath `
    -ChildPath "RMS-IIS-WMCS-Logs-$env:COMPUTERNAME-$timestamp.txt"

$rmsUrls = @(
    "http://$RmsAliasShortName/_wmcs/certification/servercertification.asmx",
    "http://$RmsAliasShortName/_wmcs/licensing/license.asmx",
    "http://$RmsAliasFqdn/_wmcs/certification/servercertification.asmx",
    "http://$RmsAliasFqdn/_wmcs/licensing/license.asmx",
    "http://$RmsPhysicalShortName/_wmcs/certification/servercertification.asmx",
    "http://$RmsPhysicalShortName/_wmcs/licensing/license.asmx",
    "http://$RmsPhysicalFqdn/_wmcs/certification/servercertification.asmx",
    "http://$RmsPhysicalFqdn/_wmcs/licensing/license.asmx"
)

$step = 0
$totalSteps = 36

function Write-Section {
    param(
        [string]$Title
    )

    $line = "=" * 100

    Add-Content `
        -Path $outputFile `
        -Value ""

    Add-Content `
        -Path $outputFile `
        -Value $line

    Add-Content `
        -Path $outputFile `
        -Value $Title

    Add-Content `
        -Path $outputFile `
        -Value $line
}

function Invoke-DiagnosticCommand {
    param(
        [string]$Title,
        [string]$CommandText,
        [scriptblock]$ScriptBlock
    )

    $global:step++

    Write-Progress `
        -Activity "Recolectando diagnóstico AD RMS/IIS" `
        -Status $Title `
        -PercentComplete (($global:step / $totalSteps) * 100)

    Write-Section `
        -Title $Title

    Add-Content `
        -Path $outputFile `
        -Value "COMANDO:"

    Add-Content `
        -Path $outputFile `
        -Value $CommandText

    Add-Content `
        -Path $outputFile `
        -Value ""

    Add-Content `
        -Path $outputFile `
        -Value "SALIDA:"

    try {
        $result = & $ScriptBlock 2>&1

        if ($null -eq $result) {
            Add-Content `
                -Path $outputFile `
                -Value "[Sin salida]"
        }
        else {
            $resultText = $result | Out-String

            Add-Content `
                -Path $outputFile `
                -Value $resultText
        }
    }
    catch {
        Add-Content `
            -Path $outputFile `
            -Value "ERROR CAPTURADO:"

        Add-Content `
            -Path $outputFile `
            -Value ($_ | Out-String)

        Add-Content `
            -Path $outputFile `
            -Value "DETALLE DE EXCEPCION:"

        Add-Content `
            -Path $outputFile `
            -Value ($_.Exception | Format-List * -Force | Out-String)
    }
}

"AD RMS / IIS Diagnostics" | Out-File `
    -FilePath $outputFile `
    -Encoding UTF8

"Fecha de ejecución: $(Get-Date)" | Add-Content `
    -Path $outputFile

"Servidor: $env:COMPUTERNAME" | Add-Content `
    -Path $outputFile

"Usuario de ejecución: $env:USERDOMAIN\$env:USERNAME" | Add-Content `
    -Path $outputFile

"Carpeta de salida: $scriptPath" | Add-Content `
    -Path $outputFile

"Dominio AD FQDN: $AdDomainFqdn" | Add-Content `
    -Path $outputFile

"RMS Alias Short Name: $RmsAliasShortName" | Add-Content `
    -Path $outputFile

"RMS Alias FQDN: $RmsAliasFqdn" | Add-Content `
    -Path $outputFile

"RMS Physical Short Name: $RmsPhysicalShortName" | Add-Content `
    -Path $outputFile

"RMS Physical FQDN: $RmsPhysicalFqdn" | Add-Content `
    -Path $outputFile

"RMS Computer Account: $RmsComputerAccount" | Add-Content `
    -Path $outputFile

Invoke-DiagnosticCommand `
    -Title "Contexto de ejecución" `
    -CommandText "whoami /all" `
    -ScriptBlock {
        whoami /all
    }

Invoke-DiagnosticCommand `
    -Title "Información básica del sistema operativo" `
    -CommandText "Get-CimInstance Win32_OperatingSystem | Format-List *" `
    -ScriptBlock {
        Get-CimInstance Win32_OperatingSystem |
            Format-List Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime, InstallDate
    }

Invoke-DiagnosticCommand `
    -Title "Nombre del equipo y dominio" `
    -CommandText "Get-CimInstance Win32_ComputerSystem | Format-List *" `
    -ScriptBlock {
        Get-CimInstance Win32_ComputerSystem |
            Format-List Name, Domain, PartOfDomain, Manufacturer, Model
    }

Invoke-DiagnosticCommand `
    -Title "Configuración IP y DNS" `
    -CommandText "ipconfig /all" `
    -ScriptBlock {
        ipconfig /all
    }

Invoke-DiagnosticCommand `
    -Title "Proxy WinHTTP" `
    -CommandText "netsh winhttp show proxy" `
    -ScriptBlock {
        netsh winhttp show proxy
    }

Invoke-DiagnosticCommand `
    -Title "Controlador de dominio detectado" `
    -CommandText "nltest /dsgetdc:$AdDomainFqdn" `
    -ScriptBlock {
        nltest /dsgetdc:$AdDomainFqdn
    }

Invoke-DiagnosticCommand `
    -Title "Resolución DNS de alias y nombre físico RMS" `
    -CommandText "Resolve-DnsName $RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn" `
    -ScriptBlock {
        foreach ($name in @($RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn)) {
            "---- $name ----"
            Resolve-DnsName $name
        }
    }

Invoke-DiagnosticCommand `
    -Title "Conectividad TCP local hacia nombres RMS puerto 80" `
    -CommandText "Test-NetConnection contra $RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn -Port 80" `
    -ScriptBlock {
        foreach ($name in @($RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn)) {
            "---- $name : 80 ----"
            Test-NetConnection `
                -ComputerName $name `
                -Port 80
        }
    }

Invoke-DiagnosticCommand `
    -Title "Pruebas HTTP locales contra endpoints RMS" `
    -CommandText "Invoke-WebRequest contra certification y licensing usando -UseDefaultCredentials" `
    -ScriptBlock {
        foreach ($uri in $rmsUrls) {
            "===================================================================================================="
            "URI: $uri"

            try {
                $response = Invoke-WebRequest `
                    -Uri $uri `
                    -UseBasicParsing `
                    -UseDefaultCredentials `
                    -ErrorAction Stop

                "StatusCode: $($response.StatusCode)"
                "StatusDescription: $($response.StatusDescription)"
                "Headers:"
                $response.Headers | Format-List
                "Contenido inicial:"
                $response.Content.Substring(0, [Math]::Min(1000, $response.Content.Length))
            }
            catch {
                "ERROR:"
                $_ | Out-String
                "EXCEPTION:"
                $_.Exception | Format-List * -Force
                "RESPONSE:"
                $_.Exception.Response | Format-List * -Force
            }
        }
    }

Invoke-DiagnosticCommand `
    -Title "Application Pools IIS" `
    -CommandText "Get-ChildItem IIS:\AppPools con identidad" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-ChildItem IIS:\AppPools | ForEach-Object {
            [PSCustomObject]@{
                AppPool = $_.Name
                State = $_.state
                IdentityType = $_.processModel.identityType
                UserName = $_.processModel.userName
                ManagedRuntimeVersion = $_.managedRuntimeVersion
                Enable32BitAppOnWin64 = $_.enable32BitAppOnWin64
            }
        } |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Sitios IIS y bindings" `
    -CommandText "Get-Website | Format-List" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-Website |
            Select-Object Name, ID, State, PhysicalPath, Bindings |
            Format-List
    }

Invoke-DiagnosticCommand `
    -Title "Aplicaciones IIS bajo Default Web Site" `
    -CommandText "Get-WebApplication -Site 'Default Web Site'" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-WebApplication `
            -Site "Default Web Site" |
            Select-Object Path, ApplicationPool, PhysicalPath |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Directorios virtuales IIS bajo Default Web Site" `
    -CommandText "Get-WebVirtualDirectory -Site 'Default Web Site'" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-WebVirtualDirectory `
            -Site "Default Web Site" |
            Select-Object Path, PhysicalPath |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Configuración Windows Authentication en _wmcs/certification" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/certification" /section:system.webServer/security/authentication/windowsAuthentication' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/certification" /section:system.webServer/security/authentication/windowsAuthentication
    }

Invoke-DiagnosticCommand `
    -Title "Configuración Windows Authentication en _wmcs/licensing" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/licensing" /section:system.webServer/security/authentication/windowsAuthentication' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/licensing" /section:system.webServer/security/authentication/windowsAuthentication
    }

Invoke-DiagnosticCommand `
    -Title "Configuración Anonymous Authentication en _wmcs/certification" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/certification" /section:system.webServer/security/authentication/anonymousAuthentication' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/certification" /section:system.webServer/security/authentication/anonymousAuthentication
    }

Invoke-DiagnosticCommand `
    -Title "Configuración Anonymous Authentication en _wmcs/licensing" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/licensing" /section:system.webServer/security/authentication/anonymousAuthentication' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/licensing" /section:system.webServer/security/authentication/anonymousAuthentication
    }

Invoke-DiagnosticCommand `
    -Title "Configuración completa IIS de _wmcs/certification" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/certification"' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/certification"
    }

Invoke-DiagnosticCommand `
    -Title "Configuración completa IIS de _wmcs/licensing" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/licensing"' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/licensing"
    }

Invoke-DiagnosticCommand `
    -Title "Permisos NTFS de _wmcs" `
    -CommandText 'icacls C:\inetpub\wwwroot\_wmcs /T' `
    -ScriptBlock {
        icacls "C:\inetpub\wwwroot\_wmcs" /T
    }

Invoke-DiagnosticCommand `
    -Title "Existencia y metadatos de archivos ASMX RMS" `
    -CommandText "Get-Item servercertification.asmx y license.asmx" `
    -ScriptBlock {
        $files = @(
            "C:\inetpub\wwwroot\_wmcs\certification\servercertification.asmx",
            "C:\inetpub\wwwroot\_wmcs\licensing\license.asmx"
        )

        foreach ($file in $files) {
            "---- $file ----"

            if (Test-Path $file) {
                Get-Item $file |
                    Select-Object FullName, Length, CreationTime, LastWriteTime, Attributes |
                    Format-List
            }
            else {
                "No existe"
            }
        }
    }

Invoke-DiagnosticCommand `
    -Title "SPN relacionados con RMS" `
    -CommandText "setspn -Q HTTP/$RmsAliasShortName, HTTP/$RmsAliasFqdn, HTTP/$RmsPhysicalShortName, HTTP/$RmsPhysicalFqdn" `
    -ScriptBlock {
        $spns = @(
            "HTTP/$RmsAliasShortName",
            "HTTP/$RmsAliasFqdn",
            "HTTP/$RmsPhysicalShortName",
            "HTTP/$RmsPhysicalFqdn"
        )

        foreach ($spn in $spns) {
            "---- $spn ----"
            setspn -Q $spn
        }
    }

Invoke-DiagnosticCommand `
    -Title "SPN registrados en cuenta de equipo RMS" `
    -CommandText "setspn -L $RmsComputerAccount" `
    -ScriptBlock {
        setspn -L $RmsComputerAccount
    }

Invoke-DiagnosticCommand `
    -Title "Loopback Check y BackConnectionHostNames" `
    -CommandText "reg query HKLM\SYSTEM\CurrentControlSet\Control\Lsa y MSV1_0" `
    -ScriptBlock {
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v DisableLoopbackCheck
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v BackConnectionHostNames
    }

Invoke-DiagnosticCommand `
    -Title "Políticas NTLM locales relevantes" `
    -CommandText "reg query HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" `
    -ScriptBlock {
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"

        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LmCompatibilityLevel
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v RestrictReceivingNTLMTraffic
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v RestrictSendingNTLMTraffic
        reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v ClientAllowedNTLMServers
    }

Invoke-DiagnosticCommand `
    -Title "Klist tickets actuales" `
    -CommandText "klist" `
    -ScriptBlock {
        klist
    }

Invoke-DiagnosticCommand `
    -Title "Roles y features AD RMS / IIS" `
    -CommandText "Get-WindowsFeature filtrando ADRMS, Web, WAS" `
    -ScriptBlock {
        Get-WindowsFeature |
            Where-Object {
                $_.Name -match "ADRMS|Web-|WAS" -or
                $_.DisplayName -match "Rights Management|IIS|Web Server|Windows Process Activation"
            } |
            Sort-Object Name |
            Format-Table Name, DisplayName, InstallState -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Servicios relevantes" `
    -CommandText "Get-Service filtrando RMS, IIS, W3SVC, WAS" `
    -ScriptBlock {
        Get-Service |
            Where-Object {
                $_.Name -match "RMS|W3SVC|WAS|IIS" -or
                $_.DisplayName -match "Rights|RMS|Internet Information|Web"
            } |
            Sort-Object DisplayName |
            Format-Table Status, Name, DisplayName -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Certificados LocalMachine My" `
    -CommandText "Get-ChildItem Cert:\LocalMachine\My" `
    -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\My |
            Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey |
            Sort-Object NotAfter |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Certificados LocalMachine Root" `
    -CommandText "Get-ChildItem Cert:\LocalMachine\Root" `
    -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\Root |
            Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint |
            Sort-Object NotAfter |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Certificados LocalMachine CA" `
    -CommandText "Get-ChildItem Cert:\LocalMachine\CA" `
    -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\CA |
            Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint |
            Sort-Object NotAfter |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Eventos Security 4625 últimas 24 horas" `
    -CommandText "Get-WinEvent Security EventID 4625 últimos 24h y exportar CSV" `
    -ScriptBlock {
        $startTime = (Get-Date).AddHours(-24)

        $events = Get-WinEvent `
            -FilterHashtable @{
                LogName = "Security"
                Id = 4625
                StartTime = $startTime
            } `
            -ErrorAction SilentlyContinue

        $parsedEvents = foreach ($event in $events) {
            $xml = [xml]$event.ToXml()
            $data = @{}

            foreach ($item in $xml.Event.EventData.Data) {
                $data[$item.Name] = $item.'#text'
            }

            [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                TargetUserName = $data["TargetUserName"]
                TargetDomainName = $data["TargetDomainName"]
                Status = $data["Status"]
                SubStatus = $data["SubStatus"]
                LogonType = $data["LogonType"]
                AuthenticationPackageName = $data["AuthenticationPackageName"]
                WorkstationName = $data["WorkstationName"]
                IpAddress = $data["IpAddress"]
                IpPort = $data["IpPort"]
                FailureReason = $data["FailureReason"]
                Message = $event.Message
            }
        }

        $parsedEvents |
            Export-Csv `
                -Path $securityEventsFile `
                -NoTypeInformation `
                -Encoding UTF8

        "Archivo exportado: $securityEventsFile"

        $parsedEvents |
            Format-List
    }

Invoke-DiagnosticCommand `
    -Title "Eventos Application/System relacionados con RMS, IIS, Kerberos, NTLM, Schannel" `
    -CommandText "Get-WinEvent Application/System últimos 24h filtrando palabras clave" `
    -ScriptBlock {
        $startTime = (Get-Date).AddHours(-24)

        $events = @()

        foreach ($logName in @("Application", "System")) {
            $items = Get-WinEvent `
                -FilterHashtable @{
                    LogName = $logName
                    StartTime = $startTime
                } `
                -ErrorAction SilentlyContinue

            foreach ($item in $items) {
                $message = $item.Message

                if ($message -match "RMS|Rights|IIS|W3SVC|WAS|Kerberos|NTLM|Schannel|certification|licensing|0x800704dc|401\.1|401\.3|servercertification|license\.asmx") {
                    $events += $item
                }
            }
        }

        $events |
            Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message |
            Format-List
    }

Invoke-DiagnosticCommand `
    -Title "Logs AD RMS disponibles" `
    -CommandText "Get-WinEvent -ListLog *RMS*" `
    -ScriptBlock {
        Get-WinEvent -ListLog *RMS* |
            Format-Table LogName, RecordCount, IsEnabled, LogMode, MaximumSizeInBytes -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Eventos AD RMS últimas 24 horas" `
    -CommandText "Get-WinEvent en logs *RMS* últimos 24h" `
    -ScriptBlock {
        $startTime = (Get-Date).AddHours(-24)

        $logs = Get-WinEvent -ListLog *RMS* `
            -ErrorAction SilentlyContinue

        foreach ($log in $logs) {
            "===================================================================================================="
            "Log: $($log.LogName)"

            Get-WinEvent `
                -FilterHashtable @{
                    LogName = $log.LogName
                    StartTime = $startTime
                } `
                -ErrorAction SilentlyContinue |
                Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
                Format-List
        }
    }

Invoke-DiagnosticCommand `
    -Title "Extracto de IIS logs para _wmcs últimos 7 días" `
    -CommandText "Buscar _wmcs, 401, servercertification.asmx, license.asmx en C:\inetpub\logs\LogFiles" `
    -ScriptBlock {
        $logRoot = "C:\inetpub\logs\LogFiles"
        $startTime = (Get-Date).AddDays(-7)

        if (Test-Path $logRoot) {
            $files = Get-ChildItem `
                -Path $logRoot `
                -Recurse `
                -Filter "*.log" |
                Where-Object {
                    $_.LastWriteTime -ge $startTime
                }

            "Archivos revisados:"
            $files |
                Select-Object FullName, LastWriteTime, Length |
                Format-Table -AutoSize

            $matches = foreach ($file in $files) {
                Select-String `
                    -Path $file.FullName `
                    -Pattern "_wmcs","servercertification.asmx","license.asmx"," 401 ","401.1","401.3" `
                    -ErrorAction SilentlyContinue
            }

            $matches |
                ForEach-Object {
                    "$($_.Path):$($_.LineNumber): $($_.Line)"
                } |
                Out-File `
                    -FilePath $iisLogExtractFile `
                    -Encoding UTF8

            "Archivo exportado: $iisLogExtractFile"

            if (Test-Path $iisLogExtractFile) {
                Get-Content `
                    -Path $iisLogExtractFile `
                    -Tail 300
            }
        }
        else {
            "No existe $logRoot"
        }
    }

Invoke-DiagnosticCommand `
    -Title "Hotfixes instalados recientemente" `
    -CommandText "Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 80" `
    -ScriptBlock {
        Get-HotFix |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 80 |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Configuración .NET ASP.NET ISAPI handlers para ASMX" `
    -CommandText 'appcmd list config "Default Web Site/_wmcs/certification" /section:handlers' `
    -ScriptBlock {
        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/certification" /section:handlers

        & "$env:windir\system32\inetsrv\appcmd.exe" list config "Default Web Site/_wmcs/licensing" /section:handlers
    }

Invoke-DiagnosticCommand `
    -Title "Resumen de archivos generados" `
    -CommandText "Listar archivos generados por el script" `
    -ScriptBlock {
        Get-ChildItem `
            -Path $scriptPath `
            -Filter "*$timestamp*" |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    }

Write-Progress `
    -Activity "Recolectando diagnóstico AD RMS/IIS" `
    -Completed

Write-Host "Diagnóstico finalizado."
Write-Host "Archivo principal: $outputFile"
Write-Host "Eventos Security 4625: $securityEventsFile"
Write-Host "Extracto IIS logs: $iisLogExtractFile"