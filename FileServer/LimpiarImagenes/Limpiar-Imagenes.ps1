#$folder = "C:\Users\feder\OneDrive\Pictures\Álbum de cámara"
$folder = "C:\Users\feder\OneDrive\Pictures\Samsung Gallery\DCIM\Camera"
$destFolder = "C:\Users\feder\OneDrive\Pictures\Imágenes Personales"

$origen = Get-ChildItem -Path $folder -Recurse

foreach ($foto in $origen) {
    $nombre = $foto.Name
    $size = $foto.Length

    if($foto.Name -contains "Office Lens"){
        Write-Host "No procesando $($foto.Name)."
    }
    elseif($foto.Name[0] -eq "S" -or $foto.Name[0] -eq "I" -or $foto.Name[0] -eq "V" -or $foto.Name[0] -eq "T") {
        Write-Host "Procesando imagen o video de WhatsApp: $($foto.Name)."
        # Procesar imágenes y videos de WhatsApp
        if ($foto.PSIsContainer -eq $false) {
            $nombre = $foto.Name
            $encontrado = Get-ChildItem -Path $destFolder -Recurse -Name $nombre -ErrorAction SilentlyContinue
    
            if($encontrado -ne $null) { 
                Write-Host "Archivo encontrado. Eliminando en origen..."
                Remove-Item $foto.FullName -Verbose -ErrorAction Stop
            }
            else {
                $fecha = $foto.LastWriteTime
                $year = $fecha.ToString("yyyy")
                $fechStr = $fecha.ToString("yyyy-MM-dd")
                Write-Host "Fecha foto: $fechStr"
    
                # Buscar o crear el directorio de destino
                $resultadoCarpetaDestino = Get-ChildItem -Path $destFolder -Recurse -Name "$fechStr*" -ErrorAction SilentlyContinue
                $nombreCarpetaDestino = ""
                if ($resultadoCarpetaDestino -is [Array]) {
                    $nombreCarpetaDestino = $resultadoCarpetaDestino[0]
                } else {
                    $nombreCarpetaDestino = $resultadoCarpetaDestino
                }
    
                if ($nombreCarpetaDestino -ne $null) {
                    $carpetaDestino = Get-Item -Path "$destFolder\$nombreCarpetaDestino" -ErrorAction SilentlyContinue
                } else {
                    # No hay un álbum, crear carpeta sin nombre
                    $carpetaDestino = New-Item -Path "$destFolder\$year" -Name $fechStr -ItemType Directory -ErrorAction SilentlyContinue -Verbose
                }
    
                # Crear o usar la subcarpeta 'WP' dentro de la carpeta de destino
                $carpetaWP = "$($carpetaDestino.FullName)\WP"
                if (-not (Test-Path $carpetaWP)) {
                    New-Item -Path $carpetaWP -ItemType Directory -ErrorAction SilentlyContinue -Verbose
                }
    
                Write-Host "Carpeta destino: $($carpetaWP)"
                Move-Item $foto.FullName -Destination $carpetaWP -ErrorAction SilentlyContinue -Verbose
            }
        }

    }
    else {
        if ($foto.PSIsContainer -eq $false) {
            Write-Host "Buscando $nombre"
            $encontrado = Get-ChildItem -Path $destFolder -Recurse -Name $nombre -ErrorAction SilentlyContinue
            if($encontrado -ne $null) { 
                Write-Host "Archivo encontrado. Eliminando en origen..."
                Remove-Item $foto.FullName -Verbose -ErrorAction Stop
            }
            else {
                $fecha = $foto.LastWriteTime
                $year = $fecha.ToString("yyyy")
                $fechStr = $fecha.ToString("yyyy-MM-dd")
                Write-Host "Fecha foto: $fechStr"
                # Buscar si ya hay un directorio
                $resultadoCarpetaDestino = Get-ChildItem -Path $destFolder -Recurse -Name "$fechStr*" -ErrorAction SilentlyContinue
                $nombreCarpetaDestino = ""
                if ($resultadoCarpetaDestino -is [Array])
                {
                    $nombreCarpetaDestino = $resultadoCarpetaDestino[0]
                }
                else
                {
                    $nombreCarpetaDestino = $resultadoCarpetaDestino
                }
                if ($nombreCarpetaDestino -ne $null) {
                    $carpetaDestino = Get-Item -Path "$destFolder\$nombreCarpetaDestino" -ErrorAction SilentlyContinue
                }
                else {
                    # No hay un album, crear carpeta sin nombre
                    $carpetaDestino = New-Item -Path "$destFolder\$year" -Name $fechStr -ItemType Directory -ErrorAction SilentlyContinue -Verbose
                    # TODO: si es una imagen de WhatsApp, además crea otra carpeta llamada WP dentro de la $carpetaDestino y la copia ahí adentro
                }
                Write-Host "Carpeta destino: $($carpetaDestino.Name)"
                Move-Item $foto.FullName -Destination $carpetaDestino.FullName -ErrorAction SilentlyContinue -Verbose
            }
        }
    }
}