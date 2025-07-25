param(
    [Parameter(Mandatory = $true)]
    [string]$SourceSite,
    
    [Parameter(Mandatory = $true)]
    [string]$TargetSite,
    
    [Parameter(Mandatory = $true)]
    [string]$LogFolder,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$Tenant
)

$CertificatePassword = Read-Host -Prompt "Introduce la contraseña del certificado" -AsSecureString

# Bibliotecas del sistema que se deben ignorar
$SystemLibraries = @('Form Templates', 'Site Assets', 'SiteAssets', 'Style Library')

# Función para escribir logs
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Función para crear una biblioteca de documentos
function New-DocumentLibrary {
    param(
        [string]$LibraryTitle,
        [string]$LibraryUrl
    )
    
    try {
        Write-Log "Creando biblioteca: $LibraryTitle"
        
        # Crear la biblioteca con template 101 (Document Library)
        New-PnPList -Title $LibraryTitle -Template DocumentLibrary -Url $LibraryUrl
        
        Write-Log "Biblioteca '$LibraryTitle' creada exitosamente" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Error creando biblioteca '$LibraryTitle': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Función para crear carpetas recursivamente
function New-FolderStructure {
    param(
        [string]$LibraryUrl,
        [string]$FolderPath
    )
    
    try {
        $pathParts = $FolderPath.Split('/')
        $currentPath = ""
        
        foreach ($part in $pathParts) {
            if ($part -ne "") {
                $currentPath += if ($currentPath -eq "") { $part } else { "/$part" }
                
                # Verificar si la carpeta existe
                try {
                    Get-PnPFolder -Url "$LibraryUrl/$currentPath" -ErrorAction Stop | Out-Null
                    Write-Log "Carpeta ya existe: $LibraryUrl/$currentPath"
                }
                catch {
                    # La carpeta no existe, crearla
                    Write-Log "Creando carpeta: $LibraryUrl/$currentPath"
                    if ($currentPath -contains "/"){
                        Add-PnPFolder -Name $part -Folder "$LibraryUrl/$($currentPath.Substring(0, $currentPath.LastIndexOf('/')))"
                    }
                    else {
                        Add-PnPFolder -Name $part -Folder "$LibraryUrl"
                    }
                    Write-Log "Carpeta creada: $LibraryUrl/$currentPath" -Level "SUCCESS"
                }
            }
        }
        return $true
    }
    catch {
        Write-Log "Error creando estructura de carpetas '$FolderPath': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Función para copiar archivos
function Copy-FileToTarget {
    param(
        [Microsoft.SharePoint.Client.File]$SourceFile,
        [string]$TargetLibraryUrl,
        [string]$TargetFolderPath = ""
    )
    
    try {
        $fileName = $SourceFile.Name
        $sourceFileUrl = $SourceFile.ServerRelativeUrl
        
        # Descargar el archivo del sitio origen como MemoryStream
        $memoryStream = Get-PnPFile -Url $sourceFileUrl -AsMemoryStream
        
        # Determinar la ruta de destino
        $targetPath = if ($TargetFolderPath -ne "") {
            "$TargetLibraryUrl/$TargetFolderPath/$fileName"
        } else {
            "$TargetLibraryUrl/$fileName"
        }
        
        # Conectar al sitio de destino y subir el archivo
        Connect-PnPOnline -Url $TargetSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
        
        # Determinar la carpeta de destino completa
        $targetFolder = if ($TargetFolderPath -ne "") {
            "$TargetLibraryUrl/$TargetFolderPath"
        } else {
            $TargetLibraryUrl
        }
        
        # Subir el archivo usando el MemoryStream
        Add-PnPFile -Stream $memoryStream -Folder $targetFolder -FileName $fileName
        
        Write-Log "Archivo copiado: $fileName -> $targetPath" -Level "SUCCESS"
        
        # Liberar el MemoryStream
        $memoryStream.Dispose()
        
        # Reconectar al sitio origen
        Connect-PnPOnline -Url $SourceSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
        
        return $true
    }
    catch {
        Write-Log "Error copiando archivo '$($SourceFile.Name)': $($_.Exception.Message)" -Level "ERROR"
        # Asegurarse de liberar el MemoryStream en caso de error
        if ($memoryStream) {
            $memoryStream.Dispose()
        }
        return $false
    }
}

# Función recursiva para procesar carpetas
function Invoke-FolderProcessing {
    param(
        [string]$SourceLibraryUrl,
        [string]$TargetLibraryUrl,
        [string]$FolderPath = ""
    )
    
    try {
        $folderUrl = if ($FolderPath -ne "") {
            "$SourceLibraryUrl/$FolderPath"
        } else {
            $SourceLibraryUrl
        }
        
        Write-Log "Procesando carpeta: $folderUrl"
        
        # Obtener elementos de la carpeta
        if($folderUrl -ne "") {
            $folderItems = Get-PnPFolderItem -FolderSiteRelativeUrl $folderUrl
        } else {
            $folderItems = $null
        }
        
        # Procesar archivos
        foreach ($file in $folderItems | Where-Object { $_.GetType().Name -eq "File" }) {
            Write-Log "Copiando archivo: $($file.Name)"
            Copy-FileToTarget -SourceFile $file -TargetLibraryUrl $TargetLibraryUrl -TargetFolderPath $FolderPath
        }
        
        # Procesar subcarpetas
        $folderToProcess = $folderItems | Where-Object { $_.GetType().Name -eq "Folder" -and ($_.Name -ne "Forms") }
        foreach ($folder in $folderToProcess) {
            $subFolderPath = if ($FolderPath -ne "") {
                "$FolderPath/$($folder.Name)"
            } else {
                $folder.Name
            }
            
            # Crear la carpeta en el destino si no existe
            Connect-PnPOnline -Url $TargetSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
            New-FolderStructure -LibraryUrl $TargetLibraryUrl -FolderPath $subFolderPath
            
            # Reconectar al sitio origen y procesar recursivamente
            Connect-PnPOnline -Url $SourceSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
            Process-Folder -SourceLibraryUrl $SourceLibraryUrl -TargetLibraryUrl $TargetLibraryUrl -FolderPath $subFolderPath
        }
    }
    catch {
        Write-Log "Error procesando carpeta '$FolderPath': $($_.Exception.Message)" -Level "ERROR"
    }
}

# Script principal
try {
    # Configurar logging
    if (!(Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force
    }
    
    $LogFile = Join-Path $LogFolder "SPOContentCopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    Write-Log "=== INICIANDO COPIA DE CONTENIDO DE SHAREPOINT ===" -Level "START"
    Write-Log "Sitio origen: $SourceSite"
    Write-Log "Sitio destino: $TargetSite"
    Write-Log "Carpeta de logs: $LogFolder"
    
    # Verificar que PnP PowerShell esté instalado
    if (!(Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Write-Log "PnP.PowerShell no está instalado. Instalando..." -Level "WARNING"
        Install-Module -Name PnP.PowerShell -Force -AllowClobber
    }
    
    Import-Module PnP.PowerShell
    
    # Conectar al sitio origen
    Write-Log "Conectando al sitio origen..."
    Connect-PnPOnline -Url $SourceSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
    
    # Obtener todas las bibliotecas del sitio origen
    Write-Log "Obteniendo bibliotecas del sitio origen..."
    $sourceLibraries = Get-PnPList | Where-Object { 
        $_.BaseTemplate -eq 101 -and 
        $SystemLibraries -notcontains $_.Title 
    }
    
    Write-Log "Se encontraron $($sourceLibraries.Count) bibliotecas de documentos válidas"
    
    foreach ($sourceLibrary in $sourceLibraries) {
        Write-Log "=== PROCESANDO BIBLIOTECA: $($sourceLibrary.Title) ===" -Level "INFO"
        
        # Determinar la URL de la biblioteca (manejar el caso especial de "Documents")
        $sourceLibraryUrl = if ($sourceLibrary.Title -eq "Documents") {
            "Shared Documents"
        } else {
            $sourceLibrary.EntityTypeName
        }
        
        # Conectar al sitio destino para verificar/crear la biblioteca
        Write-Log "Conectando al sitio destino..."
        Connect-PnPOnline -Url $TargetSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
        
        # Verificar si la biblioteca existe en el destino
        try {
            $targetLibrary = Get-PnPList -Identity $sourceLibrary.Title -ErrorAction Stop
            Write-Log "Biblioteca '$($sourceLibrary.Title)' ya existe en el destino"
        }
        catch {
            # La biblioteca no existe, crearla
            Write-Log "Biblioteca '$($sourceLibrary.Title)' no existe en el destino, creándola..."
            if (!(New-DocumentLibrary -LibraryTitle $sourceLibrary.Title -LibraryUrl $sourceLibraryUrl)) {
                Write-Log "No se pudo crear la biblioteca '$($sourceLibrary.Title)', saltando..." -Level "ERROR"
                continue
            }
        }
        
        # Determinar la URL de la biblioteca de destino
        $targetLibraryUrl = if ($sourceLibrary.Title -eq "Documents") {
            "Shared Documents"
        } else {
            #$sourceLibrary.RootFolder.Name
            $sourceLibrary.EntityTypeName
        }
        
        # Reconectar al sitio origen para procesar el contenido
        Write-Log "Reconectando al sitio origen para procesar contenido..."
        Connect-PnPOnline -Url $SourceSite -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant
        
        # Procesar el contenido de la biblioteca
        Invoke-FolderProcessing -SourceLibraryUrl $sourceLibraryUrl -TargetLibraryUrl $targetLibraryUrl
        
        Write-Log "=== BIBLIOTECA '$($sourceLibrary.Title)' PROCESADA ===" -Level "SUCCESS"
    }
    
    Write-Log "=== COPIA DE CONTENIDO COMPLETADA ===" -Level "SUCCESS"
}
catch {
    Write-Log "Error general en el script: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level "ERROR"
}
finally {
    # Desconectar de SharePoint
    try {
        Disconnect-PnPOnline
        Write-Log "Desconectado de SharePoint"
    }
    catch {
        Write-Log "Error al desconectar: $($_.Exception.Message)" -Level "WARNING"
    }
}