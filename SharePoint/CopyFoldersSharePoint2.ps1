<#
.SYNOPSIS  
    Copia de forma recursiva el contenido de una carpeta entre
    bibliotecas de documentos que residen en sitios distintos
    dentro de un mismo tenant de SharePoint Online.
    Versión mejorada con reintentos ante errores de timeout.

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
    [string]$LogFolder,

    # Nuevos parámetros para reintentos
    [int]$MaxRetries = 3,           # Número máximo de reintentos
    [int]$RetryDelaySeconds = 30    # Tiempo de espera entre reintentos
)

#--- Password del certificado (no se guarda en plano) ---
$CertificatePassword = Read-Host -AsSecureString -Prompt "Contraseña del certificado PnP"

#--- Registro de logs ---
if(!(Test-Path $LogFolder)){ New-Item -ItemType Directory -Path $LogFolder -Force }
$LogFile = Join-Path $LogFolder "SPOFolderCopy_$(Get-Date -f yyyyMMdd_HHmmss).log"
function Write-Log{
    param([string]$Msg,[string]$Level='INFO')
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date),$Level,$Msg
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

#--- Función para detectar errores de timeout ---
function Is-TimeoutError {
    param([System.Exception]$Exception)
    
    $errorMessage = $Exception.Message
    $innerException = $Exception.InnerException
    
    # Buscar patrones de timeout en el mensaje de error
    $timeoutPatterns = @(
        "HttpClient.Timeout",
        "timeout",
        "timed out",
        "The operation has timed out",
        "request was canceled due to the configured HttpClient.Timeout"
    )
    
    foreach ($pattern in $timeoutPatterns) {
        if ($errorMessage -like "*$pattern*") {
            return $true
        }
        if ($innerException -and $innerException.Message -like "*$pattern*") {
            return $true
        }
    }
    
    return $false
}

#--- Función para ejecutar operación con reintentos ---
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 30
    )
    
    $attempt = 1
    
    while ($attempt -le $MaxRetries) {
        try {
            Write-Log "Ejecutando $OperationName (intento $attempt/$MaxRetries)"
            & $ScriptBlock
            return # Éxito, salir de la función
        }
        catch {
            $isTimeout = Is-TimeoutError -Exception $_.Exception
            
            if ($isTimeout -and $attempt -lt $MaxRetries) {
                Write-Log "Timeout detectado en $OperationName. Reintentando en $DelaySeconds segundos..." "WARNING"
                Start-Sleep -Seconds $DelaySeconds
                $attempt++
            }
            else {
                if ($isTimeout) {
                    Write-Log "Timeout en $OperationName después de $MaxRetries intentos. Operación fallida." "ERROR"
                }
                else {
                    Write-Log "Error no relacionado con timeout en $($OperationName): $($_.Exception.Message)" "ERROR"
                }
                throw # Re-lanzar la excepción
            }
        }
    }
}

#--- Comprobamos módulo PnP-PowerShell ---
if(-not (Get-Module -ListAvailable -Name PnP.PowerShell)){
    Install-Module PnP.PowerShell -Force -AllowClobber
}
Import-Module PnP.PowerShell

#--- Funciones auxiliares ---
function Split-SPOPath{
    <#
        Devuelve un objeto con:
        SiteUrl  -> https://tenant/sites/SiteX
        Library  -> "Documentos compartidos"
        Folder   -> "Sub1/Sub2"
    #>
    param([string]$FullUrl)
    $uri = [Uri]$FullUrl
    $segments = $uri.LocalPath.Trim('/') -split '/'
    # Ex.: sites/Balances/Documentos%20compartidos/CarpetaOrigen
    $siteIndex = $segments.IndexOf('sites') + 2      # +2 = /sites/{Sitio}
    $sitePath  = $segments[0..($siteIndex-1)] -join '/'
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
            Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Crear carpeta $current" -ScriptBlock {
                Add-PnPFolder -Name $p -Folder "$LibraryUrl/$($current -replace '/[^/]+$','')" -Connection $Conn | Out-Null
            }
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

    $items = $null
    Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Obtener elementos de carpeta $SrcSubPath" -ScriptBlock {
        $script:items = Get-PnPFolderItem -FolderSiteRelativeUrl "$SrcLibUrl/$SrcSubPath"
    }
    $items = $script:items

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
            $dstFolder = if($DstSubPath){ "$DstLibUrl/$DstSubPath" } else { $DstLibUrl }
            
            # Verificar si el archivo ya existe en el destino
            $fileExists = $false
            Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Verificar existencia de archivo $fileName" -ScriptBlock {
                try {
                    $existingFile = Get-PnPFile -Url "$dstFolder/$fileName" -Connection $Conn -ErrorAction Stop
                    $script:fileExists = $true
                }
                catch {
                    # Si el archivo no existe, Get-PnPFile lanza excepción
                    $script:fileExists = $false
                }
            }
            $fileExists = $script:fileExists
            
            if ($fileExists) {
                Write-Log "   ⚠  $fileName (archivo ya existe, omitido)" "WARNING"
                continue
            }
            
            $stream = $null
            
            # Descargar archivo con reintentos
            Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Descargar archivo $fileName" -ScriptBlock {
                $script:stream = Get-PnPFile -Url $item.ServerRelativeUrl -AsMemoryStream
            }
            $stream = $script:stream

            try {
                # Subir archivo con reintentos
                Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Subir archivo $fileName" -ScriptBlock {
                    Add-PnPFile -Connection $Conn -Stream $stream -Folder $dstFolder -FileName $fileName -ErrorAction Stop
                }

                Write-Log "   ✓  $fileName" "SUCCESS"
            }
            finally {
                if ($stream) {
                    $stream.Dispose()
                }
            }
        }
    }
}

#--- Parseo de URLs ---
$SourceInfo = Split-SPOPath $SourceUrl
$TargetInfo = Split-SPOPath $TargetUrl

Write-Log "Sitio origen : $($SourceInfo.SiteUrl)"
Write-Log "Biblioteca   : $($SourceInfo.Library)"
Write-Log "Carpeta      : $($SourceInfo.Folder)"
Write-Log "-------------"
Write-Log "Sitio destino: $($TargetInfo.SiteUrl)"
Write-Log "Biblioteca   : $($TargetInfo.Library)"
Write-Log "Carpeta      : $($TargetInfo.Folder)"
Write-Log "Configuración de reintentos: Máximo $MaxRetries intentos, espera de $RetryDelaySeconds segundos"
Write-Log "========================================"

try{
    # Conexión sitio origen con reintentos
    Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Conexión al sitio origen" -ScriptBlock {
        Connect-PnPOnline -Url $SourceInfo.SiteUrl -ClientId $ClientId `
                          -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                          -Tenant $Tenant
    }
    Write-Log "Conectado al sitio origen."

    # URL server-relative de la biblioteca con reintentos
    $srcLibUrl = $null
    $miConn = $null
    $dstLibUrl = $null
    
    Invoke-WithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -OperationName "Obtener información de bibliotecas" -ScriptBlock {
        $script:srcLibUrl = (Get-PnPList -Identity $SourceInfo.Library).RootFolder.ServerRelativeUrl
        $script:miConn = Connect-PnPOnline -Url $TargetInfo.SiteUrl -ClientId $ClientId `
                                           -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                                           -Tenant $Tenant -ReturnConnection
        $miLib = Get-PnPList -Identity $TargetInfo.Library -Connection $script:miConn
        $script:dstLibUrl = $miLib.RootFolder.ServerRelativeUrl
    }
    $srcLibUrl = $script:srcLibUrl
    $miConn = $script:miConn
    $dstLibUrl = $script:dstLibUrl
    
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