# Collect-SharePoint-IRM-Diagnostics.ps1
# Relevamiento desatendido de configuración IRM/RMS desde servidor SharePoint
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
    [string]$AdDomainFqdn
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
    -ChildPath "SharePoint-IRM-Diagnostics-$env:COMPUTERNAME-$timestamp.txt"

$eventFile = Join-Path `
    -Path $scriptPath `
    -ChildPath "SharePoint-Events-$env:COMPUTERNAME-$timestamp.csv"

$ulsFile = Join-Path `
    -Path $scriptPath `
    -ChildPath "SharePoint-ULS-IRM-$env:COMPUTERNAME-$timestamp.log"

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
$totalSteps = 32

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
        -Activity "Recolectando diagnóstico SharePoint IRM/RMS" `
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

"SharePoint IRM/RMS Diagnostics" | Out-File `
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
    -Title "Resolución DNS de servidores RMS" `
    -CommandText "Resolve-DnsName $RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn" `
    -ScriptBlock {
        foreach ($name in @($RmsAliasShortName, $RmsAliasFqdn, $RmsPhysicalShortName, $RmsPhysicalFqdn)) {
            "---- $name ----"
            Resolve-DnsName $name
        }
    }

Invoke-DiagnosticCommand `
    -Title "Conectividad TCP hacia RMS puerto 80" `
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
    -Title "Pruebas HTTP contra endpoints RMS con credenciales actuales" `
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
    -Title "Carga del snap-in de SharePoint" `
    -CommandText "Add-PSSnapin Microsoft.SharePoint.PowerShell" `
    -ScriptBlock {
        Add-PSSnapin Microsoft.SharePoint.PowerShell `
            -ErrorAction SilentlyContinue

        Get-PSSnapin Microsoft.SharePoint.PowerShell
    }

Invoke-DiagnosticCommand `
    -Title "Versión y build de la granja SharePoint" `
    -CommandText "Get-SPFarm | Format-List *" `
    -ScriptBlock {
        Get-SPFarm |
            Format-List Id, DisplayName, BuildVersion, Servers
    }

Invoke-DiagnosticCommand `
    -Title "Servidores de la granja SharePoint" `
    -CommandText "Get-SPServer | Format-Table Address, Role, Status" `
    -ScriptBlock {
        Get-SPServer |
            Select-Object Address, Role, Status |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Configuración IRM de SharePoint" `
    -CommandText "Get-SPIRMSettings | Format-List *" `
    -ScriptBlock {
        Get-SPIRMSettings |
            Format-List *
    }

Invoke-DiagnosticCommand `
    -Title "Configuración IRM desde SPWebService ContentService" `
    -CommandText '$webSvc = [Microsoft.SharePoint.Administration.SPWebService]::ContentService; $webSvc.IrmSettings | Format-List *' `
    -ScriptBlock {
        $webSvc = [Microsoft.SharePoint.Administration.SPWebService]::ContentService

        $webSvc.IrmSettings |
            Format-List *
    }

Invoke-DiagnosticCommand `
    -Title "Web Applications de SharePoint y Application Pools" `
    -CommandText "Get-SPWebApplication | Select DisplayName, Url, ApplicationPool, ApplicationPool.Username" `
    -ScriptBlock {
        Get-SPWebApplication | ForEach-Object {
            [PSCustomObject]@{
                DisplayName = $_.DisplayName
                Url = $_.Url
                ApplicationPool = $_.ApplicationPool.Name
                ApplicationPoolUserName = $_.ApplicationPool.Username
                IisSettings = ($_.IisSettings.Keys -join ", ")
            }
        } |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Managed Accounts de SharePoint" `
    -CommandText "Get-SPManagedAccount | Format-Table UserName, DisplayName" `
    -ScriptBlock {
        Get-SPManagedAccount |
            Select-Object UserName, DisplayName |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Configuración de Alternate Access Mappings" `
    -CommandText "Get-SPAlternateURL | Format-Table IncomingUrl, Zone, PublicUrl" `
    -ScriptBlock {
        Get-SPAlternateURL |
            Select-Object IncomingUrl, Zone, PublicUrl |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Application Pools locales de IIS" `
    -CommandText "Get-ChildItem IIS:\AppPools con identidad" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-ChildItem IIS:\AppPools | ForEach-Object {
            [PSCustomObject]@{
                AppPool = $_.Name
                IdentityType = $_.processModel.identityType
                UserName = $_.processModel.userName
                State = $_.state
                ManagedRuntimeVersion = $_.managedRuntimeVersion
            }
        } |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Sitios IIS locales" `
    -CommandText "Get-Website | Format-Table Name, ID, State, PhysicalPath, Bindings" `
    -ScriptBlock {
        Import-Module WebAdministration

        Get-Website |
            Select-Object Name, ID, State, PhysicalPath, Bindings |
            Format-List
    }

Invoke-DiagnosticCommand `
    -Title "Versión y ubicación de MSIPC.DLL" `
    -CommandText "Buscar MSIPC.DLL en rutas comunes" `
    -ScriptBlock {
        $paths = @(
            "$env:windir\System32\msipc.dll",
            "$env:windir\SysWOW64\msipc.dll",
            "$env:ProgramFiles\Active Directory Rights Management Services Client 2.1\msipc.dll",
            "${env:ProgramFiles(x86)}\Active Directory Rights Management Services Client 2.1\msipc.dll"
        )

        foreach ($path in $paths) {
            "---- $path ----"

            if (Test-Path $path) {
                Get-Item $path |
                    Select-Object FullName, Length, CreationTime, LastWriteTime, VersionInfo |
                    Format-List

                [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path) |
                    Format-List *
            }
            else {
                "No existe"
            }
        }
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
    -Title "Certificados LocalMachine Root cercanos a vencimiento" `
    -CommandText "Get-ChildItem Cert:\LocalMachine\Root" `
    -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\Root |
            Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint |
            Sort-Object NotAfter |
            Format-Table -AutoSize
    }

Invoke-DiagnosticCommand `
    -Title "Certificados LocalMachine CA cercanos a vencimiento" `
    -CommandText "Get-ChildItem Cert:\LocalMachine\CA" `
    -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\CA |
            Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint |
            Sort-Object NotAfter |
            Format-Table -AutoSize
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
    -Title "Klist tickets actuales" `
    -CommandText "klist" `
    -ScriptBlock {
        klist
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
    -Title "Últimos eventos Application/System relevantes" `
    -CommandText "Get-WinEvent Application/System últimos 24h filtrando RMS, IRM, MSIPC, SharePoint, Schannel, Kerberos, NTLM" `
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

                if ($message -match "RMS|IRM|MSIPC|SharePoint|Schannel|Kerberos|NTLM|authentication|certification|licensing|0x800704dc|0x80004005|0x80041056") {
                    $events += $item
                }
            }
        }

        $events |
            Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message |
            Export-Csv `
                -Path $eventFile `
                -NoTypeInformation `
                -Encoding UTF8

        "Archivo exportado: $eventFile"

        $events |
            Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message |
            Format-List
    }

Invoke-DiagnosticCommand `
    -Title "Exportar ULS SharePoint últimos 60 minutos filtrado por IRM/RMS" `
    -CommandText "Merge-SPLogFile -StartTime (Get-Date).AddMinutes(-60) -EndTime (Get-Date) -Overwrite" `
    -ScriptBlock {
        Add-PSSnapin Microsoft.SharePoint.PowerShell `
            -ErrorAction SilentlyContinue

        $start = (Get-Date).AddMinutes(-60)
        $end = Get-Date

        Merge-SPLogFile `
            -Path $ulsFile `
            -StartTime $start `
            -EndTime $end `
            -Overwrite

        "ULS exportado a: $ulsFile"

        if (Test-Path $ulsFile) {
            Select-String `
                -Path $ulsFile `
                -Pattern "IRM","RMS","MSIPC","0x800704dc","0x80004005","0x80041056","Virm","HrEncryptDecrypt" |
                Select-Object LineNumber, Line |
                Format-List
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
    -Title "Servicios relevantes" `
    -CommandText "Get-Service filtrando SharePoint, IIS, RMS, WebClient" `
    -ScriptBlock {
        Get-Service |
            Where-Object {
                $_.Name -match "SP|IIS|W3SVC|WAS|RMS|WebClient" -or
                $_.DisplayName -match "SharePoint|Internet Information|Rights|RMS|WebClient"
            } |
            Sort-Object DisplayName |
            Format-Table Status, Name, DisplayName -AutoSize
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
    -Activity "Recolectando diagnóstico SharePoint IRM/RMS" `
    -Completed

Write-Host "Diagnóstico finalizado."
Write-Host "Archivo principal: $outputFile"
Write-Host "Archivo de eventos: $eventFile"
Write-Host "Archivo ULS: $ulsFile"