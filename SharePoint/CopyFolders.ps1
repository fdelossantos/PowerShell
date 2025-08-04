<#
.SYNOPSIS  
    Copia de forma recursiva el contenido de una carpeta entre
    bibliotecas de documentos que residen en sitios distintos
    dentro de un mismo tenant de SharePoint Online.
    Versión mejorada con reintentos, filtro alfabético y manejo robusto de errores.

.EXAMPLE  
    .\Copy-SPOFolder.ps1 `
        -SourceUrl  "https://tenant.sharepoint.com/sites/Source/Documentos%20compartidos/Folder1" `
        -TargetUrl  "https://tenant.sharepoint.com/sites/Destination/Documentos%20compartidos/Folder2/Folder3" `
        -CertificatePath  "C:\Certs\certificate-pnp-auth.pfx" `
        -ClientId   "00000000-0000-0000-0000-000000000000" `
        -Tenant     "tenant.onmicrosoft.com" `
        -LogFolder  ".\Logs" `
        -StartFromLetter "P" `
        -ContinueOnError
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https:\/\/.+\/sites\/.+')]
    [string]$SourceUrl,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https:\/\/.+\/sites\/.+')]
    [string]$TargetUrl,

    [Parameter(Mandatory=$true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CertificatePath,

    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$Tenant,
    [Parameter(Mandatory=$true)]
    [string]$LogFolder,

    # Nuevos parámetros para reintentos
    [int]$MaxRetries = 3,           # Número máximo de reintentos
    [int]$RetryDelaySeconds = 30,    # Tiempo de espera entre reintentos

    # Filtro alfabético de carpetas
    [string]$StartFromLetter = 'A',

    # No detener ejecución ante errores
    [switch]$ContinueOnError
)
$ContinueOnError = $true
#--- Solicitar contraseña del certificado sin planchar ---
$CertificatePassword = Read-Host -AsSecureString -Prompt "Contraseña del certificado PnP"

#--- Inicializar logging ---
if (!(Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force }
$LogFile = Join-Path $LogFolder "SPOFolderCopy_$(Get-Date -f yyyyMMdd_HHmmss).log"
function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Msg
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

#--- Detectar errores de timeout ---
function Is-TimeoutError {
    param([System.Exception]$Exception)
    $patterns = @('HttpClient.Timeout','timeout','timed out','The operation has timed out')
    foreach ($p in $patterns) {
        if ($Exception.Message -like "*$p*") { return $true }
        if ($Exception.InnerException -and $Exception.InnerException.Message -like "*$p*") { return $true }
    }
    return $false
}

#--- Ejecutar con reintentos y opcional continuar ---
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 30,
        [switch]$ContinueOnError
    )
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            Write-Log "📁 Ejecutando $OperationName (intento $attempt/$MaxRetries)"
            & $ScriptBlock
            Write-Log "✓ $OperationName completado" "SUCCESS"
            return
        }
        catch {
            $ex = $_.Exception
            $isTimeout = Is-TimeoutError -Exception $ex
            if ($isTimeout -and $attempt -lt $MaxRetries) {
                Write-Log "⚠ Timeout en $OperationName. Reintentando en $DelaySeconds s..." "WARNING"
                Start-Sleep -Seconds $DelaySeconds
                $attempt++
                continue
            }
            # Tras últimos intentos o error no-timeout
            if ($isTimeout) {
                Write-Log "✗ Timeout en $OperationName tras $MaxRetries intentos" "ERROR"
            } else {
                Write-Log "✗ Error en $($OperationName): $($ex.Message)" "ERROR"
            }
            if ($ContinueOnError) {
                Write-Log "➤ Continuando pese al error en $OperationName" "WARNING"
                return
            } else {
                throw
            }
        }
    }
}

#--- Cargar módulo PnP ---
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Invoke-WithRetry -OperationName 'Instalar PnP.PowerShell' -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError `
        -ScriptBlock { Install-Module PnP.PowerShell -Force -AllowClobber }
                     
}
Import-Module PnP.PowerShell

#--- Auxiliares de ruta SPO ---
function Split-SPOPath {
    param([string]$FullUrl)
    $uri = [Uri]$FullUrl
    $segments = $uri.LocalPath.Trim('/') -split '/'
    $siteIndex = $segments.IndexOf('sites') + 2
    $obj = [pscustomobject]@{
        SiteUrl = "$($uri.Scheme)://$($uri.Host)/$($segments[0..($siteIndex-1)] -join '/')"
        Library = $segments[$siteIndex]
        Folder  = ($segments[($siteIndex+1)..($segments.Length-1)] -join '/')
    }
    return $obj
}

function Ensure-TargetFolder {
    param(
        [string]$LibraryUrl,
        [string]$FolderPath,
        [object]$Conn
    )
    if ([string]::IsNullOrWhiteSpace($FolderPath)) { return }
    $parts = $FolderPath -split '/'
    $current = ''
    foreach ($p in $parts) {
        $current = if ($current) { "$current/$p" } else { $p }
        $exists = Get-PnPFolder -Url "$LibraryUrl/$current" -Connection $Conn -ErrorAction SilentlyContinue
        if (-not $exists) {
            Invoke-WithRetry -ScriptBlock { Add-PnPFolder -Name $p -Folder "$LibraryUrl/$($current -replace '/[^/]+$','')" -Connection $Conn } `
                             -OperationName "Crear carpeta $current" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError
            Write-Log "✓ Carpeta creada: $current" "SUCCESS"
        }
    }
}

function Copy-FolderRecursive {
    param(
        [string]$SrcLibUrl, [string]$SrcSubPath,
        [string]$DstLibUrl, [string]$DstSubPath,
        [object]$Conn,
        [switch]$ContinueOnError,
        [switch]$IsRoot = $false
    )
    Write-Log "📁 Procesando carpeta: $SrcSubPath"
    # Obtener items
    $items = $null
    Invoke-WithRetry -ScriptBlock { $script:items = Get-PnPFolderItem -FolderSiteRelativeUrl "$SrcLibUrl/$SrcSubPath" } `
                     -OperationName "Listar elementos en $SrcSubPath" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError
    $items = $script:items
    foreach ($item in $items) {
        try {
            if ($item.GetType().Name -eq 'Folder' -and $item.Name -ne 'Forms') {
                # Filtro alfabético
                if ($IsRoot -and [char]::ToUpper($item.Name[0]) -lt [char]::ToUpper($StartFromLetter)) {
                    Write-Log "⏭ Saltando carpeta raíz '$($item.Name)' (antes de '$StartFromLetter')" "INFO"
                    continue
                }
<#                 if ([char]::ToUpper($item.Name[0]) -lt [char]::ToUpper($StartFromLetter)) {
                    Write-Log "⏭ Saltando carpeta '$($item.Name)' (antes de '$StartFromLetter')" "INFO"
                    continue
                } #>
                $newSrc = if ($SrcSubPath) { "$SrcSubPath/$($item.Name)" } else { $item.Name }
                $newDst = if ($DstSubPath) { "$DstSubPath/$($item.Name)" } else { $item.Name }
                Ensure-TargetFolder -LibraryUrl $DstLibUrl -FolderPath $newDst -Conn $Conn
                Copy-FolderRecursive -SrcLibUrl $SrcLibUrl -SrcSubPath $newSrc `
                                     -DstLibUrl $DstLibUrl -DstSubPath $newDst -Conn $Conn -ContinueOnError:$ContinueOnError
            }
            elseif ($item.GetType().Name -eq 'File') {
                # Procesar archivo
                $fileName = $item.Name
                $dstFolder = if ($DstSubPath) { "$DstLibUrl/$DstSubPath" } else { $DstLibUrl }
                # Comprobar existencia
                $exists = $false
                Invoke-WithRetry -ScriptBlock {
                    try { Get-PnPFile -Url "$dstFolder/$fileName" -Connection $Conn -ErrorAction Stop; $script:exists = $true }
                    catch { $script:exists = $false }
                    $exists = $script:exists
                } -OperationName "Verificar archivo $fileName" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError
                if ($exists) {
                    Write-Log "⚠ Archivo existe: $fileName (omitido)" "WARNING"
                    continue
                }
                # Descargar
                $stream = $null
                Invoke-WithRetry -ScriptBlock { 
                    $script:stream = Get-PnPFile -Url $item.ServerRelativeUrl -AsMemoryStream 
                    
                } -OperationName "Descargar $fileName" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError

                $stream = $script:stream

                # Subir
                Invoke-WithRetry -ScriptBlock { Add-PnPFile -Connection $Conn -Stream $stream -Folder $dstFolder -FileName $fileName -ErrorAction Stop } `
                                 -OperationName "Subir $fileName" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError
                Write-Log "✓ Archivo transferido: $fileName" "SUCCESS"
                if ($stream) { $stream.Dispose() }
            }
        }
        catch {
            Write-Log "✗ Error procesando '$($item.Name)': $($_.Exception.Message)" "ERROR"
            if ($ContinueOnError) { Write-Log "➤ Continuando con siguiente elemento..." "WARNING" } else { throw }
        }
    }
}

#--- Iniciar flujo principal ---
$SourceInfo = Split-SPOPath $SourceUrl
$TargetInfo = Split-SPOPath $TargetUrl
Write-Log "Sitio origen  : $($SourceInfo.SiteUrl)"
Write-Log "Biblioteca    : $($SourceInfo.Library)"
Write-Log "Carpeta origen: $($SourceInfo.Folder)"
Write-Log "Sitio destino : $($TargetInfo.SiteUrl)"
Write-Log "Biblioteca    : $($TargetInfo.Library)"
Write-Log "Carpeta destino: $($TargetInfo.Folder)"
Write-Log "Filtro StartFromLetter: '$StartFromLetter'"
Write-Log "ContinueOnError : $ContinueOnError"

try {
    Invoke-WithRetry -OperationName 'Conexión origen' -MaxRetries $MaxRetries `
        -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError `
        -ScriptBlock { Connect-PnPOnline -Url $SourceInfo.SiteUrl -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant }
                     

    $srcLibUrl = $null; $miConn = $null; $dstLibUrl = $null
    Invoke-WithRetry -OperationName 'Obtener rutas de biblioteca' -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ContinueOnError:$ContinueOnError `
        -ScriptBlock {
        $script:srcLibUrl = (Get-PnPList -Identity $SourceInfo.Library).RootFolder.ServerRelativeUrl
        $script:miConn    = Connect-PnPOnline -Url $TargetInfo.SiteUrl -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant -ReturnConnection
        $script:dstLibUrl = (Get-PnPList -Identity $TargetInfo.Library -Connection $script:miConn).RootFolder.ServerRelativeUrl
    }
    $srcLibUrl = $script:srcLibUrl
    $miConn = $script:miConn
    $dstLibUrl = $script:dstLibUrl

    Ensure-TargetFolder -LibraryUrl $dstLibUrl -FolderPath $TargetInfo.Folder -Conn $miConn

    Write-Log "Iniciando copia recursiva..."
    Copy-FolderRecursive -SrcLibUrl $SourceInfo.Library -SrcSubPath $SourceInfo.Folder `
                         -DstLibUrl $dstLibUrl -DstSubPath $TargetInfo.Folder -Conn $miConn -ContinueOnError:$ContinueOnError -IsRoot
    Write-Log "✓ Copia finalizada." "SUCCESS"
}
catch {
    Write-Log "✗ Falla crítica: $($_.Exception.Message)" "ERROR"
}
finally {
    Invoke-WithRetry -OperationName 'Desconectar' -MaxRetries 1 -DelaySeconds 0 -ContinueOnError `
        -ScriptBlock { Disconnect-PnPOnline -ErrorAction SilentlyContinue } 
}
