param (
    [String]$DominioOriginal, 
    [String]$NuevoDominio,
    [String]$SearchBase
    )

Import-Module ActiveDirectory

#$DominioOriginal = "@asw.ort.edu.uy"
#$SearchBase = "OU=Estructura 2,DC=asw,DC=ort,DC=edu,DC=uy"

# Obtener todos los usuarios cuyo UPN termine en el dominio original

$parametros = @{
    Filter = "UserPrincipalName -like '*@$DominioOriginal'"
    Properties = "UserPrincipalName"
    SearchBase = $SearchBase
}
$usuarios = Get-ADUser @parametros #-Filter {UserPrincipalName -like "*$DominioOriginal"} -Properties UserPrincipalName -SearchBase $SearchBase


# Iterar a través de los usuarios y cambiar el UPN
foreach ($usuario in $usuarios) {
    $nuevoUPN = $usuario.UserPrincipalName -replace [regex]::Escape($dominioOriginal), $NuevoDominio

    # Mostrar el cambio que se realizará
    Write-Host "Cambiar UPN de $($usuario.SamAccountName) de $($usuario.UserPrincipalName) a $nuevoUPN"

    # Realizar cambio de UPN
    Set-ADUser -Identity $usuario.SamAccountName -UserPrincipalName $nuevoUPN
}

Write-Host "Proceso completado."