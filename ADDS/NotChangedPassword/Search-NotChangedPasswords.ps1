param(
    [Parameter(Mandatory)]
    [string]$ArchivoSalida,
    [string]$Delimitador=";"
)
Import-Module ActiveDirectory

$usuariosCoincidentes = @()
$usuariosSinPassLastSet = @()

$usuarios = Get-ADUser -Properties PasswordLastSet,whenCreated -Filter *
$TotalUsuarios = $usuarios.Count
$avance = 0

foreach ($usuario in $usuarios) {
    $avance++
    $porcentaje = [Math]::Round($avance * 100 / $TotalUsuarios)
    Write-Progress -Activity "Analizando usuarios" -Status "Usuario: $($usuario.Name)" -PercentComplete $porcentaje
    if ($null -eq $usuario.PasswordLastSet.Date){
        $usuariosSinPassLastSet += [PSCustomObject]@{
            Nombre = $usuario.Name
            Cuenta = $usuario.SamAccountName
            DistinguishedName = $usuario.DistinguishedName
            Creado = $usuario.whenCreated
            UltimaPassword = $null
        }
            
        Write-Host "Usuario sin PasswordLastSet: $($usuario.Name)"

    }
    else {
        if ($usuario.whenCreated.Date -eq $usuario.PasswordLastSet.Date) {
            $usuariosCoincidentes += [PSCustomObject]@{
                Nombre = $usuario.Name
                Cuenta = $usuario.SamAccountName
                DistinguishedName = $usuario.DistinguishedName
                Creado = $usuario.whenCreated
                UltimaPassword = $usuario.PasswordLastSet
            }
            
            Write-Host "Usuario encontrado: $($usuario.Name)"
        }
    }
}

$totalUsuarios = $usuariosCoincidentes.Count
Write-Host "Total de usuarios con fecha de creación y cambio de contraseña coincidentes: $totalUsuarios"
$totalUsuarios = $usuariosSinPassLastSet.Count
Write-Host "Total de usuarios sin PasswordLastSet: $totalUsuarios"
$usuariosCoincidentes + $usuariosSinPassLastSet | Export-Csv -Path $ArchivoSalida -NoTypeInformation -Delimiter $Delimitador -Encoding utf8