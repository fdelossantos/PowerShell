$directorios = Get-ChildItem "\\storage\Usuarios" -Directory -Recurse -ErrorAction SilentlyContinue
$total = $directorios.Count
$haciendo = 1

$salida = @()
$mostrar = $true
foreach ($dir in $directorios) {
    $porcentaje = $haciendo * 100 / $total
    $Error.Clear()
    $acl = get-acl $dir.Fullname -ErrorAction SilentlyContinue
    $pctje = [math]::floor($porcentaje)
    if ($pctje % 2 -eq 0 -and $mostrar) {
        Write-Progress -Activity "Comprobando ACLs" -Status "Van $($salida.Count) errores." -PercentComplete $pctje -CurrentOperation "[$haciendo] $($raiz.Fullname)" 
        $mostrar = $false
    }
    if ($pctje % 2 -eq 1) {
        $mostrar = $true
    }

    if ($acl.Access.Where({$_.IdentityReference -eq 'Domain\Administrator'}, 'First').Count -eq 0) {
        #write-host $dir.Fullname 
    }
        $objeto = [PSCustomObject]@{
            Ruta = $dir.Fullname
            Error = $Error[0].Exception.Message
        }
        $salida += $objeto

    $haciendo ++
}

$salida | Export-Csv -Path ".\Salida.csv" -Delimiter ";" -Encoding utf8 -NoTypeInformation