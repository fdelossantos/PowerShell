# Parámetros
$sourceFile = "E:\temp\2025-05-19_data_script.sql"
$outputDir  = "E:\temp\chunks"

# Asegura que exista la carpeta de salida
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Abre lector Unicode
$reader = [System.IO.StreamReader]::new($sourceFile, [System.Text.Encoding]::Unicode)

# Variables de control
$fileIndex = 1
$writer    = $null

try {
    # Función para (re)crear el StreamWriter con nombre secuencial
    function New-Writer {
        param($index)
        $fname = "{0:D8}.sql" -f $index
        return [System.IO.StreamWriter]::new(
            ([System.IO.Path]::Combine($outputDir, $fname)),
            $false,                                   # no append
            [System.Text.Encoding]::Unicode
        )
    }

    # Abre el primer archivo
    $writer = New-Writer $fileIndex

    # Bucle de lectura línea a línea
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()

        if ($line.Trim() -ieq "GO") {
            # Cierre el fragmento actual y abra uno nuevo
            $writer.Close()
            $fileIndex++
            $writer = New-Writer $fileIndex
        }
        else {
            # Escribe la línea (con CRLF por defecto)
            $writer.WriteLine($line)
        }
    }
}
finally {
    # Cierra los streams
    if ($writer) { $writer.Close() }
    $reader.Close()
}

Write-Host "División completada: se generaron $fileIndex archivos en $outputDir"
