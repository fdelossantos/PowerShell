[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $SearchBase
)
connect-AzureAD
$allusers = Get-ADUser -Filter "*" -SearchBase $SearchBase

$errors = @()
foreach ($thisuser in $allusers) {
    $guid = [guid]($thisuser).ObjectGuid
    $ImmutableID = [system.convert]::ToBase64String(( $guid ).ToByteArray())
    Write-Host "Immutable ID for $($thisuser.UserPrincipalName) [$guid]: $ImmutableID"
    $oncloud = $null
    $oncloud = Get-AzureADUser -ObjectId $thisuser.UserPrincipalName -ErrorAction SilentlyContinue
    if ($null -eq $oncloud){
        Write-Host "User not found: $($thisuser.UserPrincipalName)"
        $errors += $thisuser.UserPrincipalName
    }
    else {
        Set-AzureADUser -ObjectId $thisuser.UserPrincipalName -ImmutableID $ImmutableID
        Write-Host "Success: $($thisuser.UserPrincipalName)"
    }
    
 }
 Write-Host "Errors:"
 $errors