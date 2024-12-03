Param(
    [Parameter(Mandatory=$true)]
    [string]$DomainOrigin,
    [Parameter(Mandatory=$true)]
    [string]$DomainDestination
)

# Importar el módulo ActiveDirectory
Import-Module ActiveDirectory

Write-Host "Obteniendo cuentas de equipo del dominio $DomainOrigin..."
$computersOrigin = Get-ADComputer -Filter * -Server $DomainOrigin -Properties sAMAccountName, DistinguishedName

Write-Host "Obteniendo cuentas de equipo del dominio $DomainDestination..."
$computersDestination = Get-ADComputer -Filter * -Server $DomainDestination -Properties sAMAccountName

# Obtener nombres NetBIOS de las cuentas de equipo
$netbiosNamesOrigin = $computersOrigin | ForEach-Object { $_.sAMAccountName.TrimEnd('$') }
$netbiosNamesDestination = $computersDestination | ForEach-Object { $_.sAMAccountName.TrimEnd('$') }

# Crear un hash table de nombres NetBIOS en el dominio de destino
$destinationNetbiosHash = @{}
foreach ($name in $netbiosNamesDestination) {
    $destinationNetbiosHash[$name] = $true
}

# Identificar las cuentas de equipo que existen en ambos dominios
$computersToDelete = $computersOrigin | Where-Object {
    $destinationNetbiosHash.ContainsKey($_.sAMAccountName.TrimEnd('$'))
}

Write-Host "Se encontraron $($computersToDelete.Count) cuentas de equipo que existen en ambos dominios."

# Eliminar las cuentas de equipo del dominio de origen
foreach ($computer in $computersToDelete) {
    Write-Host "Eliminando la cuenta de equipo: $($computer.Name) del dominio $DomainOrigin..."
    try {
        Remove-ADComputer -Identity $computer.DistinguishedName -Server $DomainOrigin -Confirm:$false
    }
    catch {
        Write-Host "Error al eliminar la cuenta $($computer.Name): $_" -ForegroundColor Red
    }
}
