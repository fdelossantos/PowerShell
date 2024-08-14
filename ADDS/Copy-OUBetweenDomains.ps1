# Parámetros obligatorios
param (
    [Parameter(Mandatory=$true)]
    [string]$sourceDomain,

    [Parameter(Mandatory=$true)]
    [string]$targetDomain
)

# Función para obtener todas las OUs de un dominio, excluyendo las predeterminadas
function Get-NonDefaultOUs {
    param (
        [string]$Domain
    )
    
    $OUs = Get-ADOrganizationalUnit -Filter * -Server $Domain -SearchBase 'DC=yourdomain,DC=com' |
        Where-Object {
            $_.Name -notin @('Builtin', 'Users', 'Computers', 'Managed Service Accounts', 'System', 'ForeignSecurityPrincipals', 'Program Data')
        }
    
    return $OUs
}

# Obtener OUs del dominio de origen
$sourceOUs = Get-NonDefaultOUs -Domain $sourceDomain

# Construir la lista de OUs a crear en el dominio de destino
$ouList = $sourceOUs | Select-Object -ExpandProperty DistinguishedName

# Mostrar la lista de OUs al usuario
Write-Host "Se crearán las siguientes OUs en el dominio $($targetDomain):" -ForegroundColor Yellow
$ouList | ForEach-Object { Write-Host $_ }

# Confirmación del usuario
$confirmation = Read-Host "¿Desea continuar con la creación de estas OUs en el dominio $targetDomain? (S/N)"

if ($confirmation -eq 'S' -or $confirmation -eq 's') {
    # Conectar al dominio de destino
    try {
        $targetDomainConnection = Get-ADDomain -Server $targetDomain
    } catch {
        Write-Host "Error al conectar con el dominio de destino: $_" -ForegroundColor Red
        exit
    }
    
    # Crear las OUs en el dominio de destino
    foreach ($ou in $ouList) {
        try {
            $newOU = $ou -replace ",DC=$($sourceDomain -replace '\.', ',DC=')", ",DC=$($targetDomain -replace '\.', ',DC=')"
            New-ADOrganizationalUnit -Name (Get-ADOrganizationalUnit -Identity $ou -Server $sourceDomain).Name -Path ($newOU -replace "OU=.*?,", "") -Server $targetDomain
            Write-Host "OU creada satisfactoriamente: $newOU" -ForegroundColor Green
        } catch {
            Write-Host "Error al crear la OU: $ou en el dominio $targetDomain. Detalles: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "Operación cancelada por el usuario." -ForegroundColor Cyan
}