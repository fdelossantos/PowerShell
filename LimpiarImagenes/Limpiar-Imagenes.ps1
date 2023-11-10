$origen = Get-ChildItem -Path "C:\Users\usuario\OneDrive\Pictures\Álbum de cámara" -Recurse

foreach ($foto in $origen) {
    $nombre = $foto.Name
    $size = $foto.Length

    if($foto.Name[0] -eq "S" -or $foto.Name[0] -eq "I" -or $foto.Name[0] -eq "V" -or $foto.Name[0] -eq "T" -or $foto.Name -contains "Office Lens") {
        Write-Host "No procesando $($foto.Name)."
        # Escribir la parte que procesa imágenes y videos de Whatsapp


    }
    else {
        if ($foto.PSIsContainer -eq $false) {
            Write-Host "Buscando $nombre"
            $encontrado = Get-ChildItem -Path "C:\Users\usuario\OneDrive\Pictures\Imágenes Personales" -Recurse -Name $nombre -ErrorAction Stop
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
                $resultadoCarpetaDestino = Get-ChildItem -Path "C:\Users\usuario\OneDrive\Pictures\Imágenes Personales" -Recurse -Name "$fechStr*" -ErrorAction Stop
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
                    $carpetaDestino = Get-Item -Path "C:\Users\usuario\OneDrive\Pictures\Imágenes Personales\$nombreCarpetaDestino" -ErrorAction Stop
                }
                else {
                    # No hay un album, crear carpeta sin nombre
                    $carpetaDestino = New-Item -Path "C:\Users\usuario\OneDrive\Pictures\Imágenes Personales\$year" -Name $fechStr -ItemType Directory -ErrorAction Stop
                }
                Write-Host "Carpeta destino: $($carpetaDestino.Name)"
                Move-Item $foto.FullName -Destination $carpetaDestino.FullName -Verbose -ErrorAction Stop
            }
        }
    }
    #Read-Host
}