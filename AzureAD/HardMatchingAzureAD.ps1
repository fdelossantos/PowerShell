connect-AzureAD 
$todos = Get-ADUser -Filter "*" -SearchBase "OU=UnidadOrg,DC=dominio,DC=com,DC=uy"
#$todos = @()
#$todos += Get-ADUser -Identity "usuario1"
#$todos += Get-ADUser -Identity "usuario2"

$errores = @()
foreach ($usuario in $todos) {
    $ImmutableID = [system.convert]::ToBase64String(([guid]($usuario).ObjectGuid).ToByteArray())
    $ennube = $null
    $ennube = Get-AzureADUser -ObjectId $usuario.UserPrincipalName -ErrorAction SilentlyContinue
    if ($ennube -eq $null){
        Write-Host "No existe: $usuario.UserPrincipalName"
        $errores += $usuario.UserPrincipalName
    }
    else {
        Set-AzureADUser -ObjectId $usuario.UserPrincipalName -ImmutableID $ImmutableID
        Write-Host "Correcto: $($usuario.UserPrincipalName)"
    }
    
 }
 Write-Host "Errores:"
 $errores