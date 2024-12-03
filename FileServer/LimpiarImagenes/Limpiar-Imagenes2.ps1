param(
    [string]$folder = "C:\Users\feder\OneDrive\Pictures\Samsung Gallery\DCIM\Camera",
    [string]$destFolder = "C:\Users\feder\OneDrive\Pictures\Imágenes Personales",
    [string]$logFile = "C:\Users\feder\OneDrive\Pictures\Imágenes Personales\script_log.txt"
)

# Function to log messages to a text file
function Write-Log {
    param(
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $message"
    Add-Content -Path $logFile -Value $logEntry
}

# Build a hash table of file names in the destination folder for quick lookup
Write-Host "Building list of files in destination folder..."
Write-Log "Building list of files in destination folder..."
$destFiles = Get-ChildItem -Path $destFolder -Recurse -File -ErrorAction SilentlyContinue
$destFileNames = @{}
foreach ($file in $destFiles) {
    $destFileNames[$file.Name] = $true
}
Write-Host "Finished building list of files in destination folder."
Write-Log "Finished building list of files in destination folder."

# Function to process each file
function Process-File {
    param(
        [System.IO.FileInfo]$foto,
        [string]$appType = ""
    )

    $nombre = $foto.Name

    if ($destFileNames.ContainsKey($nombre)) {
        Write-Host "Archivo $nombre encontrado en destino. Eliminando en origen..."
        Remove-Item $foto.FullName -Verbose -ErrorAction Stop
        Write-Log "Eliminado $($foto.FullName) porque ya existe en destino."
    }
    else {
        $fecha = $foto.LastWriteTime
        $year = $fecha.ToString("yyyy")
        $fechStr = $fecha.ToString("yyyy-MM-dd")
        Write-Host "Fecha foto: $fechStr"

        # Build the destination folder path
        $yearFolder = Join-Path $destFolder $year
        if (-not (Test-Path $yearFolder)) {
            New-Item -Path $yearFolder -ItemType Directory -Verbose
            Write-Log "Creada carpeta $yearFolder."
        }

        $albumFolder = Join-Path $yearFolder $fechStr
        if (-not (Test-Path $albumFolder)) {
            New-Item -Path $albumFolder -ItemType Directory -Verbose
            Write-Log "Creada carpeta $albumFolder."
        }

        if ($appType -eq "WA") {
            $destPath = Join-Path $albumFolder "WP"
            if (-not (Test-Path $destPath)) {
                New-Item -Path $destPath -ItemType Directory -Verbose
                Write-Log "Creada carpeta $destPath."
            }
        }
        elseif ($appType -eq "OL") {
            $destPath = Join-Path $albumFolder "OL"
            if (-not (Test-Path $destPath)) {
                New-Item -Path $destPath -ItemType Directory -Verbose
                Write-Log "Creada carpeta $destPath."
            }
        }
        else {
            $destPath = $albumFolder
        }

        Write-Host "Carpeta destino: $destPath"
        Move-Item $foto.FullName -Destination $destPath -ErrorAction SilentlyContinue -Verbose
        Write-Log "Movido $($foto.FullName) a $destPath."
    }
}

# Get all files in the source folder
$origen = Get-ChildItem -Path $folder -Recurse -File

foreach ($foto in $origen) {
    $typeApp = ""
    if($foto.Name[0] -eq "S" -or $foto.Name[0] -eq "I" -or $foto.Name[0] -eq "V" -or $foto.Name[0] -eq "T") {
        Write-Host "Procesando imagen o video de WhatsApp: $($foto.Name)."
        Write-Log "Procesando imagen o video de WhatsApp: $($foto.FullName)."
        $typeApp = "WA"
    }
    elseif ($foto.Name -contains "Office Lens") {
        Write-Host "Procesando imagen de Office Lens: $($foto.Name)."
        Write-Log "Procesando imagen de Office Lens: $($foto.FullName)."
        $typeApp = "OL"
    }
    else {
        Write-Host "Procesando archivo: $($foto.Name)."
        Write-Log "Procesando archivo: $($foto.FullName)."
    }
    Process-File -foto $foto -appType $typeApp
}
