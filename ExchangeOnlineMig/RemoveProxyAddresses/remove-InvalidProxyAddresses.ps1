Import-Module ActiveDirectory

$oldDomain = '*@domain.local'

$count = 0
$usuarios = Get-ADUser -Properties proxyaddresses -Filter {ProxyAddresses -like $oldDomain} 
Write-Host "Found $($usuarios.Count) users with "
$usuarios | ForEach { # Account may have more than one email address in scope so need to loop through each one
        ForEach ($proxyAddress in $_.proxyAddresses) {
            Write-Host "$($_.SamAccountName): $proxyAddress"
            If ($proxyAddress -like $oldDomain) {
                # Write-Host $proxyAddress
                Write-Host "Removing $proxyAddress as a Proxy Address for $($_.SamAccountName)."
                Set-ADUser $_.SamAccountName -Remove @{ProxyAddresses=$proxyAddress} # -WhatIf
                $count++
            }
        }      
    }
Write-Host "Removed $Count proxy addresses for Users."

$count = 0
$grupos = Get-ADGroup -Properties proxyaddresses -Filter {ProxyAddresses -like $oldDomain} 
Write-Host "Found $($grupos.Count) users with "
$grupos | ForEach { # Account may have more than one email address in scope so need to loop through each one
        ForEach ($proxyAddress in $_.proxyAddresses) {
            Write-Host "$($_.SamAccountName): $proxyAddress"
            If ($proxyAddress -like $oldDomain) {
                # Write-Host $proxyAddress
                Write-Host "Removing $proxyAddress as a Proxy Address for $($_.SamAccountName)."
                Set-ADGroup $_.SamAccountName -Remove @{ProxyAddresses=$proxyAddress} # -WhatIf
                $count++
            }
        }      
    }
Write-Host "Removed $Count proxy addresses for Groups."
Write-Host "Done."