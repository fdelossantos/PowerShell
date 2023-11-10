$usuarios = Get-ADUser -Filter "*" -Properties proxyAddresses,LegacyExchangeDN
foreach ($usuario in $usuarios) {
    $direccion = $usuario.proxyaddresses | where {$_ -like 'X500:*'}
    if ($null -ne $direccion) {
        Set-ADUser -Identity $usuario.DistinguishedName -Remove @{proxyAddresses="$($direccion)"} 
    }
}