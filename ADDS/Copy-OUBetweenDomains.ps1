# Definir los DN base del dominio de origen y destino
$sourceBaseDN = "OU=Company,DC=domain,DC=local"
$destBaseDN = "OU=Company,DC=newdomain,DC=local"

# Definir el controlador de dominio para origen y destino
$sourceDomainController = "dc1.domain.local"
$destDomainController = "dc2.newdomain.local"

# Obtener todas las OUs en la OU de origen
$ouList = Get-ADOrganizationalUnit -Filter * -SearchBase $sourceBaseDN -Server $sourceDomainController

# Eliminar la OU base de la lista
$ouList = $ouList | Where-Object { $_.DistinguishedName -ne $sourceBaseDN }

# Ordenar la lista de OUs por la longitud de su DistinguishedName en orden ascendente
$ouList = $ouList | Sort-Object { $_.DistinguishedName.Length }

# Crear las OUs en el dominio de destino
$counter = 0
foreach ($ou in $ouList) {
$counter++
    Write-Host "Origen: $($ou.DistinguishedName)"
    # Calcular el DistinguishedName de la nueva OU en el dominio de destino
    
    $rutas = $ou.DistinguishedName.Split(",")
    $largo = $rutas.Length -3
    $nuevas = $rutas[1..$largo]
    $base = $nuevas -join ","
    $base += ",DC=newdomain,DC=local"

    Write-Host "Ruta nueva: $base"
    Write-Host "Nombre: $($ou.Name)"

    # Crear la OU en el destino
    New-ADOrganizationalUnit -Name $ou.Name -Path $base -Server $destDomainController
    Write-Host "Se ha creado la OU $counter"
}

Write-Host "Copia de OUs completada."
