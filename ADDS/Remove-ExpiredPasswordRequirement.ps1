# Obtener todos los usuarios en Active Directory
$users = Get-ADUser -Filter * -Property Name, SamAccountName, PasswordLastSet, PasswordNeverExpires

# Filtrar los usuarios que tienen la marca de cambio de contraseña en el próximo inicio de sesión
$usersToModify = $users | Where-Object { $_.PasswordLastSet -eq $null -and $_.PasswordNeverExpires -eq $false }

# Inicializar un arreglo para almacenar los resultados
$results = @()

# Recorrer cada usuario y tratar de eliminar la marca
foreach ($user in $usersToModify) {
    try {
        # Intentar remover la marca de cambio de contraseña en el próximo inicio de sesión
        Set-ADUser -Identity $user.SamAccountName -Clear PasswordLastSet
        # Agregar al reporte que el usuario fue modificado exitosamente
        $results += [pscustomobject]@{
            UserName  = $user.Name
            Status    = "Modificado exitosamente"
        }
    } catch {
        # En caso de error, agregar al reporte que no se pudo modificar
        $results += [pscustomobject]@{
            UserName  = $user.Name
            Status    = "No se pudo modificar"
        }
    }
}

# Mostrar el reporte en pantalla
$results | Format-Table -AutoSize
