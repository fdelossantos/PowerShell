$usuarios = Get-ADUser -Filter "*" -Properties LegacyExchangeDN,proxyAddresses -SearchBase "CN=contenedor,DC=dominio,DC=local"

foreach ($usuario in $usuarios) {
    if ($null -ne $usuario.LegacyExchangeDN) {

        if ( ($usuario.proxyAddresses -like "X500:*").Count -eq 0 ) {
            $leDN = "X500:$($usuario.LegacyExchangeDN)"
            Set-ADUser -Identity $usuario.DistinguishedName -Add @{proxyAddresses="$leDN"}
            Write-Host "Al usuario $($usuario.Name) se le agregó la dirección: $leDN"
        }
        else {
            Write-Host "El usuario $($usuario.Name) ya tiene una dirección X500."
        }
    }
    else {
        Write-host "El usuario $($usuario.Name) no tiene LegacyExchangeDN."
    }
}