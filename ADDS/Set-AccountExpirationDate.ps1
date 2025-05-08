<#
.SYNOPSIS
  Establece AccountExpirationDate aleatorio (entre 6 meses y 1 año) para todos los usuarios de una OU.

.PARAMETER OU
  DistinguishedName de la OU donde buscar los usuarios, por ejemplo:
  "OU=Usuarios,OU=Ventas,DC=miempresa,DC=com"

.EXAMPLE
  .\Set-RandomAccountExpiration.ps1 -OU "OU=Usuarios,DC=contoso,DC=com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OU
)

# Asegurar que está disponible el módulo de AD
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "Módulo ActiveDirectory no encontrado. Instálalo o ejecuta esto en un DC con las RSAT instaladas."
    exit 1
}
Import-Module ActiveDirectory

# Definir rango de fechas
$fechaInicio = (Get-Date).AddMonths(1)
$fechaFin    = (Get-Date).AddMonths(6)
$diasRango   = ($fechaFin - $fechaInicio).Days

# Obtener todos los usuarios de la OU y asignarles una expiración
Get-ADUser -Filter * -SearchBase $OU -Properties AccountExpirationDate | ForEach-Object -Begin {
    Write-Host "Processing users in $OU..." -ForegroundColor Cyan
} -Process {
    # Generar número aleatorio de días dentro del rango
    $rndDias = Get-Random -Minimum 0 -Maximum $diasRango

    # Calcular fecha de expiración
    $expDate = $fechaInicio.AddDays($rndDias)

    if ($_.AccountExpirationDate -ne $null) {
        Write-Host "User '$($_.SamAccountName)' current expiration date: $($_.AccountExpirationDate)."
    }
    else {
        Write-Host "Setting expiration date for $($_.SamAccountName): $expDate"
        # Aplicar al usuario
        Set-ADUser -Identity $_ -AccountExpirationDate $expDate -ErrorAction SilentlyContinue
        # Log en consola
        Write-Host ("{0,-20} → Expiration: {1:yyyy-MM-dd}" -f $_.SamAccountName, $expDate) -ForegroundColor Green

        Start-Sleep -Milliseconds 100
        $modUser = Get-aduser $_.SamAccountName -Properties AccountExpirationDate
        if ($modUser.AccountExpirationDate -ne $null) {
            Write-Host "Successfully set AccountExpirationDate for $($_.SamAccountName): $($modUser.AccountExpirationDate)"
        }
    }

} -End {
    Write-Host "Done." -ForegroundColor Cyan
}
