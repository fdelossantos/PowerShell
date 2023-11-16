param (
    [string]$sourceFolder = ".",
    [Parameter(Mandatory=$true)][string]$destFolder,
    [string]$sourceMask = "*.*"
 )

$archivosorigen = Get-ChildItem "$sourceFolder\$sourceMask"

foreach ($archivo in $archivosorigen) {
    $Error.Clear()
    $nombreArchivo = $archivo.Name
    $objetoHashOrigen = Get-FileHash $archivo -Algorithm SHA1
    $hashOrigen = $objetoHashOrigen[0].Hash
    try {
        $objeto = Get-ChildItem "$destFolder\$nombreArchivo" -Recurse -ErrorAction SilentlyContinue
        if ($Error.Count -eq 0) {
            $objetoHashDestino = Get-FileHash $objeto[0] -Algorithm SHA1 -ErrorAction SilentlyContinue
            $hashDestino = $objetoHashDestino[0].Hash
            if ($hashOrigen -eq $hashDestino) {
                Write-Host "OK: El archivo $nombreArchivo es idéntico"
            }
            else {
                Write-Host "Diff: El archivo $nombreArchivo es diferente"
            }
        }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Host "Not Found: El archivo $nombreArchivo no existe"
    }
    catch [System.Management.Automation.RuntimeException] {
        Write-Host "CRC Error: El archivo $nombreArchivo está dañado"
    }
    catch {
        Write-Host "Unknown Error: El archivo $nombreArchivo ha generado un error no previsto."
        $Error | Select-Object -Property *
    }
}