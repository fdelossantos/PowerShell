<# 
Update Proxy Addresses with Exchange Distinguished Name

For user that does not have a X500 proxy addresses but have a LegacyExchangeDN, builds a new one.

AUTHOR: Federico de los Santos
DATE: 2024-11-15
USAGE:
.\update-proxyaddresseswithEDN.ps1 -SearchBase "OU=MyCompanyOU,DC=mydomain,DC=local"

To be run on a domain controller

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [TypeName]
    $SearchBase
)
$usuarios = Get-ADUser -Filter "*" -Properties LegacyExchangeDN,proxyAddresses -SearchBase $SearchBase

foreach ($usuario in $usuarios) {
    if ($null -ne $usuario.LegacyExchangeDN) {

        if ( ($usuario.proxyAddresses -like "X500:*").Count -eq 0 ) {
            $leDN = "X500:$($usuario.LegacyExchangeDN)"
            Set-ADUser -Identity $usuario.DistinguishedName -Add @{proxyAddresses="$leDN"}
            Write-Host "User $($usuario.Name) got the address: $leDN"
        }
        else {
            Write-Host "User $($usuario.Name) already had an X500 address."
        }
    }
    else {
        Write-host "User $($usuario.Name) does not have a LegacyExchangeDN."
    }
}