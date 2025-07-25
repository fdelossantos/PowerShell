<#
.SYNOPSIS  
    Copia de forma recursiva el contenido de una carpeta entre
    bibliotecas de documentos que residen en sitios distintos
    dentro de un mismo tenant de SharePoint Online.

.EXAMPLE  
    .\Copy-SPOFolder.ps1 `
        -SourceUrl  "https://tenant.sharepoint.com/sites/Source/Documentos%20compartidos/Folder1" `
        -TargetUrl  "https://tenant.sharepoint.com/sites/Destination/Documentos%20compartidos/Folder2/Folder3" `
        -CertificatePath  "C:\Certs\certificate-pnp-auth.pfx" `
        -ClientId   "00000000-0000-0000-0000-000000000000" `
        -Tenant     "tenant.onmicrosoft.com" `
        -LogFolder  ".\Logs"
        
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https:\/\/.+\/sites\/.+')]
    [string]$SourceUrl,              # Carpeta origen (URL completa)

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https:\/\/.+\/sites\/.+')]
    [string]$TargetUrl,              # Carpeta destino (URL completa)

    [Parameter(Mandatory=$true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CertificatePath,

    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$Tenant,
    
    [Parameter(Mandatory=$true)]
    [string]$LogFolder
)

#--- Password del certificado (no se guarda en plano) ---
$CertificatePassword = Read-Host -AsSecureString -Prompt "Contraseña del certificado PnP"

#--- Registro de logs ---
if(!(Test-Path $LogFolder)){ New-Item -ItemType Directory -Path $LogFolder -Force }
$LogFile = Join-Path $LogFolder "SPOFolderCopy_$(Get-Date -f yyyyMMdd_HHmmss).log"
function Write-Log{
    param([string]$Msg,[string]$Level='INFO')
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date),$Level,$Msg
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

#--- Comprobamos módulo PnP-PowerShell ---
if(-not (Get-Module -ListAvailable -Name PnP.PowerShell)){
    Install-Module PnP.PowerShell -Force -AllowClobber
}
Import-Module PnP.PowerShell

#--- Funciones auxiliares ---
function Split-SPOPath{
    <#
        Devuelve un objeto con:
        SiteUrl  -> https://tenant/sites/SiteX
        Library  -> "Documentos compartidos"
        Folder   -> "Sub1/Sub2"
    #>
    param([string]$FullUrl)
    $uri = [Uri]$FullUrl
    #$segments = $uri.AbsolutePath.Trim('/') -split '/'
    $segments = $uri.LocalPath.Trim('/') -split '/'
    # Ex.: sites/Balances/Documentos%20compartidos/CarpetaOrigen
    $siteIndex = $segments.IndexOf('sites') + 2      # +2 = /sites/{Sitio}
    $sitePath  = $segments[0..($siteIndex-1)] -join '/'
    #$library   = [System.Web.HttpUtility]::UrlDecode($segments[$siteIndex])
    $library   = $segments[$siteIndex]
    $folder    = ($segments[($siteIndex+1)..($segments.Length-1)]) -join '/'
    return [pscustomobject]@{
        SiteUrl = "$($uri.Scheme)://$($uri.Host)/$sitePath"
        Library = $library
        Folder  = $folder
    }
}

function Ensure-TargetFolder{
    <#
        Crea en destino toda la ruta de carpetas necesaria.
        LibraryUrl    -> URL server-relative de la biblioteca destino ("/sites/.../Documentos compartidos")
        FolderPath    -> "Carpeta1/Carpeta2/CarpetaDestino"
    #>
    param([Parameter(Mandatory=$true)][string]$LibraryUrl,
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)][object]$Conn)
    if([string]::IsNullOrWhiteSpace($FolderPath)){ return }
    $parts = $FolderPath -split '/'
    $current = ""
    foreach($p in $parts){
        $current = if($current){ "$current/$p" } else { $p }
        $exists = Get-PnPFolder -Url "$LibraryUrl/$current" -Connection $Conn -ErrorAction SilentlyContinue
        if(-not $exists){
            Add-PnPFolder -Name $p -Folder "$LibraryUrl/$($current -replace '/[^/]+$','')" -Connection $Conn | Out-Null
            Write-Log "   ✓  Carpeta creada: $current" "SUCCESS"
        }
    }
}

function Copy-FolderRecursive{
    param(
        [string]$SrcLibUrl, [string]$SrcSubPath,
        [string]$DstLibUrl, [string]$DstSubPath,
        [Parameter(Mandatory=$true)][object]$Conn
    )

    $items = Get-PnPFolderItem -FolderSiteRelativeUrl "$SrcLibUrl/$SrcSubPath"
    foreach($item in $items){
        if($item.GetType().Name -eq 'Folder' -and $item.Name -ne 'Forms'){
            $newSrc = if($SrcSubPath){ "$SrcSubPath/$($item.Name)" } else { $item.Name }
            $newDst = if($DstSubPath){ "$DstSubPath/$($item.Name)" } else { $item.Name }

            # crear carpeta en destino
            Ensure-TargetFolder -LibraryUrl $DstLibUrl -FolderPath $newDst -Conn $Conn

            # recursión
            Copy-FolderRecursive -SrcLibUrl $SrcLibUrl -SrcSubPath $newSrc `
                                 -DstLibUrl $DstLibUrl -DstSubPath $newDst -Conn $Conn
        }
        elseif($item.GetType().Name -eq 'File'){
            $fileName = $item.Name
            $stream   = Get-PnPFile -Url $item.ServerRelativeUrl -AsMemoryStream

            # Nos movemos al sitio destino (mantener abierta la conexión origen)
            Push-Location
<#             Connect-PnPOnline -Url $TargetInfo.SiteUrl -ClientId $ClientId `
                              -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                              -Tenant $Tenant -ReturnConnection | Set-Variable -Name dstConn #>
            $dstFolder = if($DstSubPath){ "$DstLibUrl/$DstSubPath" } else { $DstLibUrl }
            #Add-PnPFile -Connection $dstConn -Stream $stream -Folder $dstFolder -FileName $fileName -ErrorAction Stop
            Add-PnPFile -Connection $Conn -Stream $stream -Folder $dstFolder -FileName $fileName -ErrorAction Stop
            Pop-Location

            Write-Log "   ✓  $fileName" "SUCCESS"
            $stream.Dispose()
        }
    }
}

#--- Parseo de URLs ---
$SourceInfo = Split-SPOPath $SourceUrl
$TargetInfo = Split-SPOPath $TargetUrl

Write-Log "Sitio origen : $($SourceInfo.SiteUrl)"
Write-Log "Biblioteca   : $($SourceInfo.Library)"
Write-Log "Carpeta      : $($SourceInfo.Folder)"
Write-Log "-------------"
Write-Log "Sitio destino: $($TargetInfo.SiteUrl)"
Write-Log "Biblioteca   : $($TargetInfo.Library)"
Write-Log "Carpeta      : $($TargetInfo.Folder)"
Write-Log "========================================"

try{
    # Conexión sitio origen
    Connect-PnPOnline -Url $SourceInfo.SiteUrl -ClientId $ClientId `
                      -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                      -Tenant $Tenant
    Write-Log "Conectado al sitio origen."

    # URL server-relative de la biblioteca (ej: /sites/Balances/Documentos compartidos)
    $srcLibUrl = (Get-PnPList -Identity $SourceInfo.Library).RootFolder.ServerRelativeUrl
    $miConn = Connect-PnPOnline -Url $TargetInfo.SiteUrl -ClientId $ClientId `
                                     -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                                     -Tenant $Tenant -ReturnConnection
    $miLib = Get-PnPList -Identity $TargetInfo.Library -Connection $miConn
    $dstLibUrl = $miLib.RootFolder.ServerRelativeUrl
    Write-Log "Bibliotecas ubicadas."

    # Crear toda la ruta de destino
    Ensure-TargetFolder -LibraryUrl $dstLibUrl -FolderPath $TargetInfo.Folder -Conn $miConn

    Write-Log "Iniciando copia..."
    Copy-FolderRecursive -SrcLibUrl $SourceInfo.Library -SrcSubPath $SourceInfo.Folder `
                         -DstLibUrl $dstLibUrl -DstSubPath $TargetInfo.Folder -Conn $miConn
    Write-Log "Copia finalizada satisfactoriamente." "SUCCESS"
}
catch{
    Write-Log $_.Exception.Message "ERROR"
}
finally{
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}
