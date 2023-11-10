param(
    [string]$RutaSalida
)

# Importar el módulo de Azure AD
Import-Module AzureAD

# Conectar a Azure AD
Connect-AzureAD

if ("" -eq $RutaSalida) {
    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain()
    $fechahora = Get-Date -Format "yyyy-MM-dd HH-mm"
    $RutaSalida = ".\$fechahora $domain.csv"
}


# Obtener usuarios de Active Directory local
$adUsers = Get-ADUser -Filter * -Property UserPrincipalName, Mail

# Obtener usuarios de Azure AD
$azureAdUsers = Get-AzureADUser -All $true | Select-Object -Property UserPrincipalName, Mail

# Crear tabla
$table = @()
foreach ($user in $adUsers) {
    $upnAd = $user.UserPrincipalName
    $mailAd = $user.Mail
    $matchedUser = $azureAdUsers | Where-Object { $_.UserPrincipalName -eq $upnAd }
    if ($matchedUser) {
        $SamAccountName = $user.SamAccountName
        $upnAzureAd = $matchedUser.UserPrincipalName
        $mailAzureAd = $matchedUser.Mail
        $status = "Ambos"
    } else {
        $SamAccountName = $user.SamAccountName
        $upnAzureAd = ""
        $mailAzureAd = ""
        $status = "AD Local"
    }
    $row = [PSCustomObject]@{
        "SamAccountName" = $SamAccountName
        "UPN AD Local" = $upnAd
        "UPN Azure AD" = $upnAzureAd
        "Estado" = $status
        "Mail AD Local" = $mailAd
        "Mail Azure AD" = $mailAzureAd
    }
    $table += $row
}

# Mostrar tabla
$table | Format-Table -AutoSize

# Exportar tabla
$table | Export-Csv $RutaSalida -Delimiter ";" -Encoding UTF8 -NoTypeInformation